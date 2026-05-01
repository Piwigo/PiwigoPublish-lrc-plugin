"""
FFmpeg — Wrapper transcode vidéo + génération miniature.

Deux opérations principales :
  - transcode()   : convertit une vidéo selon un VideoPreset
  - thumbnail()   : extrait une image JPG à un timestamp donné

Signale la progression via un callback optionnel (pour GlobalStatusFile).
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from . import SUBPROCESS_FLAGS
from .ffprobe import VideoInfo
from .hwaccel import HWAccelDetector, HWAccelConfig
from .presets import VideoPreset, PresetManager


# ---------------------------------------------------------------------------
# Dataclass TranscodeResult
# ---------------------------------------------------------------------------

@dataclass
class TranscodeResult:
    input_path: str
    output_path: str
    width: int
    height: int
    duration: float             # secondes
    size: int                   # octets


@dataclass
class ThumbnailResult:
    input_path: str
    output_path: str
    timestamp: str              # "HH:MM:SS" ou "N%" selon la demande
    size: int                   # octets


# ---------------------------------------------------------------------------
# Classe FFmpeg
# ---------------------------------------------------------------------------

class FFmpeg:
    """Wrapper autour de l'exécutable ffmpeg pour transcode + miniature."""

    def __init__(self, ffmpeg_path: str = "ffmpeg", hwaccel_mode: str = "auto"):
        self.binary = ffmpeg_path
        self._hwaccel_mode = hwaccel_mode
        self._detector = HWAccelDetector(ffmpeg_path)

    # -------------------------------------------------------------------
    # Public API
    # -------------------------------------------------------------------

    def transcode(
        self,
        input_path: str | Path,
        output_path: str | Path,
        preset: VideoPreset,
        preset_manager: PresetManager,
        src_width: int,
        src_height: int,
        src_duration: float,
        progress_callback: Callable[[int], None] | None = None,
        dry_run: bool = False,
        video_info: VideoInfo | None = None,
    ) -> TranscodeResult:
        """
        Transcode une vidéo selon le preset donné.

        - preset Origin  → remux sans réencodage
        - autres presets → réencodage H.264/AAC avec downscale si nécessaire
        - HDR sources    → automatic tonemap to SDR (when not Origin)
        - progress_callback(pct: int) est appelé pendant le traitement (0..100)
        """
        input_path = str(input_path)
        output_path = str(output_path)

        is_hdr = video_info.is_hdr if video_info else False

        scale_filter = ""
        if preset.is_origin:
            cmd = self._build_remux_cmd(input_path, output_path)
            hw_config = None
        else:
            out_w, out_h = preset_manager.compute_output_resolution(
                src_width, src_height, preset
            )
            scale_filter = preset_manager.build_ffmpeg_scale_filter(
                src_width, src_height, preset
            )
            hw_config = self._detector.resolve(
                self._hwaccel_mode, preset.crf, preset.h264_profile, is_hdr
            )
            cmd = self._build_transcode_cmd(
                input_path, output_path, preset, scale_filter,
                is_hdr=is_hdr, hw_config=hw_config,
            )

        if dry_run:
            return TranscodeResult(
                input_path=input_path,
                output_path=output_path,
                width=src_width,
                height=src_height,
                duration=src_duration,
                size=0,
            )

        if hw_config is not None:
            try:
                self._run(cmd, src_duration, progress_callback)
            except FFmpegError:
                # GPU failed — fallback to CPU silently
                cpu_cmd = self._build_transcode_cmd(
                    input_path, output_path, preset, scale_filter,
                    is_hdr=is_hdr, hw_config=None,
                )
                self._run(cpu_cmd, src_duration, progress_callback)
        else:
            self._run(cmd, src_duration, progress_callback)

        out_file = Path(output_path)
        size = out_file.stat().st_size if out_file.exists() else 0

        # Déduire dimensions réelles depuis le preset (approximation)
        if preset.is_origin:
            out_w, out_h = src_width, src_height
        else:
            out_w, out_h = preset_manager.compute_output_resolution(
                src_width, src_height, preset
            )

        return TranscodeResult(
            input_path=input_path,
            output_path=output_path,
            width=out_w,
            height=out_h,
            duration=src_duration,
            size=size,
        )

    def thumbnail(
        self,
        input_path: str | Path,
        output_path: str | Path,
        duration: float,
        timestamp_pct: int = 10,
        max_width: int = 1280,
        dry_run: bool = False,
    ) -> ThumbnailResult:
        """
        Extrait une image JPG depuis la vidéo.

        timestamp_pct : pourcentage de la durée (0–100), défaut 10 %
        max_width      : largeur max du poster (hauteur calculée pour garder le ratio)
        """
        input_path = str(input_path)
        output_path = str(output_path)

        offset = max(0.0, duration * timestamp_pct / 100.0)
        # Jamais plus loin que duration - 1s pour éviter les fins noires
        offset = min(offset, max(0.0, duration - 1.0))
        timestamp_str = _seconds_to_hhmmss(offset)

        cmd = self._build_thumbnail_cmd(
            input_path, output_path, timestamp_str, max_width
        )

        if dry_run:
            return ThumbnailResult(
                input_path=input_path,
                output_path=output_path,
                timestamp=timestamp_str,
                size=0,
            )

        self._run_simple(cmd)

        size = Path(output_path).stat().st_size if Path(output_path).exists() else 0
        return ThumbnailResult(
            input_path=input_path,
            output_path=output_path,
            timestamp=timestamp_str,
            size=size,
        )

    def check_available(self) -> bool:
        """Vérifie que ffmpeg est disponible."""
        try:
            r = subprocess.run(
                [self.binary, "-version"],
                capture_output=True,
                timeout=5,
                **SUBPROCESS_FLAGS,
            )
            return r.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return False

    def get_version(self) -> str | None:
        """Retourne la version de ffmpeg ou None."""
        try:
            r = subprocess.run(
                [self.binary, "-version"],
                capture_output=True,
                text=True,
                timeout=5,
                **SUBPROCESS_FLAGS,
            )
            if r.returncode == 0:
                first_line = r.stdout.splitlines()[0]
                parts = first_line.split()
                if len(parts) >= 3:
                    return parts[2]
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
        return None

    # -------------------------------------------------------------------
    # Construction des commandes
    # -------------------------------------------------------------------

    def _build_transcode_cmd(
        self,
        input_path: str,
        output_path: str,
        preset: VideoPreset,
        scale_filter: str,
        is_hdr: bool = False,
        hw_config: HWAccelConfig | None = None,
    ) -> list[str]:
        vb = preset.video_bitrate
        ab = preset.audio_bitrate

        # Build video filter chain
        if is_hdr:
            # HDR → SDR tonemap pipeline (always CPU — hw_config is None here)
            vf = (
                "zscale=t=linear:npl=100,"
                "format=gbrpf32le,"
                "zscale=p=bt709,"
                "tonemap=tonemap=hable:desat=0,"
                "zscale=t=bt709:m=bt709:r=tv,"
                "format=yuv420p,"
                f"{scale_filter}"
            )
        else:
            vf_prefix = hw_config.extra_vf_prefix if hw_config else ""
            vf = f"{vf_prefix}{scale_filter}"

        # Codec effectif
        video_codec = hw_config.effective_codec if hw_config else preset.video_codec

        # Paramètre qualité : GPU override ou CRF standard
        if hw_config and hw_config.quality_override:
            quality_args = hw_config.quality_override
        elif hw_config:
            # VideoToolbox : pas de param qualité → bitrate seul
            quality_args = []
        else:
            quality_args = ["-crf", str(preset.crf)]

        # Pre-input args (hwaccel flags avant -i)
        pre_input = hw_config.pre_input_args if hw_config else []

        cmd = [self.binary]
        cmd += pre_input
        cmd += ["-i", input_path]
        cmd += [
            # Vidéo
            "-c:v", video_codec,
            "-profile:v", preset.h264_profile,
            "-level:v", "4.0",
        ]
        cmd += quality_args
        cmd += [
            "-b:v", f"{vb}k",
            "-maxrate", f"{int(vb * 1.2)}k",
            "-bufsize", f"{vb * 2}k",
            "-vf", vf,
            "-pix_fmt", preset.pixel_format,
            # Audio
            "-c:a", preset.audio_codec,
            "-b:a", f"{ab}k",
            "-ac", "2",
            # MP4 streaming-friendly
            "-movflags", "+faststart",
            # Écraser sans confirmation
            "-y",
        ]

        # Arguments custom du preset
        if preset.custom_ffmpeg_args:
            for k, v in preset.custom_ffmpeg_args.items():
                cmd.extend([k, str(v)])

        cmd.append(output_path)
        return cmd

    def _build_remux_cmd(self, input_path: str, output_path: str) -> list[str]:
        """Remux sans réencodage (preset Origin)."""
        return [
            self.binary,
            "-i", input_path,
            "-c", "copy",
            "-movflags", "+faststart",
            "-y",
            output_path,
        ]

    def _build_thumbnail_cmd(
        self,
        input_path: str,
        output_path: str,
        timestamp: str,
        max_width: int,
    ) -> list[str]:
        return [
            self.binary,
            "-ss", timestamp,
            "-i", input_path,
            "-frames:v", "1",
            "-vf", f"scale='min({max_width},iw)':-2",
            "-q:v", "3",
            "-y",
            output_path,
        ]

    # -------------------------------------------------------------------
    # Exécution
    # -------------------------------------------------------------------

    def _run(
        self,
        cmd: list[str],
        duration: float,
        progress_callback: Callable[[int], None] | None,
    ) -> None:
        """
        Lance ffmpeg avec capture de la progression via stderr.
        Appelle progress_callback(pct) à chaque mise à jour si fourni.
        """
        try:
            proc = subprocess.Popen(
                cmd,
                stderr=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                text=True,
                encoding="utf-8",
                errors="replace",
                **SUBPROCESS_FLAGS,
            )
        except FileNotFoundError:
            raise FFmpegError(f"ffmpeg introuvable : '{self.binary}'")

        stderr_lines: list[str] = []

        for line in proc.stderr:  # type: ignore[union-attr]
            stderr_lines.append(line)
            if progress_callback and duration > 0:
                pct = _parse_progress(line, duration)
                if pct is not None:
                    progress_callback(min(pct, 99))

        proc.wait()

        if proc.returncode != 0:
            last_lines = "".join(stderr_lines[-10:]).strip()
            raise FFmpegError(
                f"ffmpeg a échoué (code {proc.returncode}) :\n{last_lines}"
            )

        if progress_callback:
            progress_callback(100)

    def _run_simple(self, cmd: list[str]) -> None:
        """Lance ffmpeg sans suivi de progression (pour thumbnail)."""
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=60,
                **SUBPROCESS_FLAGS,
            )
        except FileNotFoundError:
            raise FFmpegError(f"ffmpeg introuvable : '{self.binary}'")
        except subprocess.TimeoutExpired:
            raise FFmpegError("ffmpeg timeout lors de la génération de la miniature")

        if result.returncode != 0:
            raise FFmpegError(
                f"ffmpeg a échoué (miniature, code {result.returncode}) :\n"
                f"{result.stderr.strip()[-500:]}"
            )


# ---------------------------------------------------------------------------
# Parsing de la progression ffmpeg
# ---------------------------------------------------------------------------

# ffmpeg écrit dans stderr : "frame=  120 fps= 60 ... time=00:00:04.00 ..."
_RE_TIME = re.compile(r"time=(\d+):(\d+):(\d+\.\d+)")


def _parse_progress(line: str, total_duration: float) -> int | None:
    """Retourne le pourcentage [0..100] depuis une ligne stderr ffmpeg."""
    m = _RE_TIME.search(line)
    if not m:
        return None
    h, mn, s = int(m.group(1)), int(m.group(2)), float(m.group(3))
    elapsed = h * 3600 + mn * 60 + s
    if total_duration <= 0:
        return None
    return int(elapsed * 100 / total_duration)


def _seconds_to_hhmmss(seconds: float) -> str:
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = seconds % 60
    return f"{h:02d}:{m:02d}:{s:06.3f}"


# ---------------------------------------------------------------------------
# Exception
# ---------------------------------------------------------------------------

class FFmpegError(Exception):
    """Erreur lors de l'exécution de ffmpeg."""
    pass
