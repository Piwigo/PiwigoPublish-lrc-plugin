"""
FFprobe — Analyse de la source vidéo (résolution, durée, codecs, bitrate, fps).

Retourne un dict structuré compatible avec le fichier statut .vtk/
et utilisable par processor.py pour calculer la résolution de sortie.
"""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from pathlib import Path

from . import SUBPROCESS_FLAGS


# ---------------------------------------------------------------------------
# Dataclass VideoInfo
# ---------------------------------------------------------------------------

@dataclass
class VideoInfo:
    path: str
    width: int
    height: int
    duration: float             # secondes
    video_codec: str
    audio_codec: str
    video_bitrate: int          # kbps (0 si inconnu)
    audio_bitrate: int          # kbps (0 si inconnu)
    fps: float
    size: int                   # octets
    container: str              # mp4, mov, mkv...
    color_transfer: str = ""    # e.g. "smpte2084" (PQ), "arib-std-b67" (HLG)
    color_primaries: str = ""   # e.g. "bt2020"
    color_space: str = ""       # e.g. "bt2020nc"

    @property
    def is_hdr(self) -> bool:
        """True if the source uses HDR transfer (PQ or HLG)."""
        hdr_transfers = {"smpte2084", "arib-std-b67"}
        return self.color_transfer.lower() in hdr_transfers

    @property
    def resolution(self) -> str:
        return f"{self.width}x{self.height}"

    @property
    def duration_str(self) -> str:
        h = int(self.duration // 3600)
        m = int((self.duration % 3600) // 60)
        s = self.duration % 60
        if h:
            return f"{h:02d}:{m:02d}:{s:05.2f}"
        return f"{m:02d}:{s:05.2f}"

    def to_dict(self) -> dict:
        return {
            "path": self.path,
            "width": self.width,
            "height": self.height,
            "resolution": self.resolution,
            "duration": self.duration,
            "video_codec": self.video_codec,
            "audio_codec": self.audio_codec,
            "video_bitrate": self.video_bitrate,
            "audio_bitrate": self.audio_bitrate,
            "fps": self.fps,
            "size": self.size,
            "container": self.container,
            "color_transfer": self.color_transfer,
            "color_primaries": self.color_primaries,
            "color_space": self.color_space,
            "is_hdr": self.is_hdr,
        }


# ---------------------------------------------------------------------------
# Probe
# ---------------------------------------------------------------------------

class FFprobe:
    """Wrapper autour de ffprobe pour analyser un fichier vidéo."""

    def __init__(self, ffprobe_path: str = "ffprobe"):
        self.binary = ffprobe_path

    def probe(self, input_path: str | Path) -> VideoInfo:
        """
        Analyse un fichier vidéo. Lève ProbeError si ffprobe échoue
        ou si le fichier n'est pas une vidéo valide.
        """
        input_path = str(input_path)

        cmd = [
            self.binary,
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            input_path,
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
                **SUBPROCESS_FLAGS,
            )
        except FileNotFoundError:
            raise ProbeError(f"ffprobe introuvable : '{self.binary}'")
        except subprocess.TimeoutExpired:
            raise ProbeError(f"ffprobe timeout sur '{input_path}'")

        if result.returncode != 0:
            raise ProbeError(
                f"ffprobe a échoué (code {result.returncode}) : {result.stderr.strip()}"
            )

        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError as e:
            raise ProbeError(f"Sortie ffprobe invalide : {e}")

        return _parse_probe_data(input_path, data)

    def check_available(self) -> bool:
        """Vérifie que ffprobe est disponible."""
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
        """Retourne la version de ffprobe ou None."""
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
                # "ffprobe version 7.1 ..."
                parts = first_line.split()
                if len(parts) >= 3:
                    return parts[2]
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
        return None


# ---------------------------------------------------------------------------
# Parsing interne
# ---------------------------------------------------------------------------

def _parse_probe_data(path: str, data: dict) -> VideoInfo:
    """Parse la sortie JSON de ffprobe en VideoInfo."""
    fmt = data.get("format", {})
    streams = data.get("streams", [])

    video_stream = next((s for s in streams if s.get("codec_type") == "video"), None)
    audio_stream = next((s for s in streams if s.get("codec_type") == "audio"), None)

    if not video_stream:
        raise ProbeError(f"Aucun flux vidéo trouvé dans '{path}'")

    # Dimensions
    width = int(video_stream.get("width", 0))
    height = int(video_stream.get("height", 0))
    if width == 0 or height == 0:
        raise ProbeError(f"Résolution invalide (0x0) pour '{path}'")

    # Durée : préférer format > stream
    duration = float(fmt.get("duration") or video_stream.get("duration") or 0)

    # Codecs
    video_codec = video_stream.get("codec_name", "unknown")
    audio_codec = audio_stream.get("codec_name", "unknown") if audio_stream else "none"

    # Bitrates
    fmt_bitrate = int(fmt.get("bit_rate", 0))
    vid_bitrate = int(video_stream.get("bit_rate", 0))
    aud_bitrate = int(audio_stream.get("bit_rate", 0)) if audio_stream else 0

    video_kbps = (vid_bitrate or fmt_bitrate) // 1000
    audio_kbps = aud_bitrate // 1000

    # FPS
    fps = _parse_fps(video_stream.get("r_frame_rate", "0/1"))

    # Taille
    size = int(fmt.get("size", 0))
    if not size:
        try:
            size = Path(path).stat().st_size
        except OSError:
            size = 0

    # Container (format_name peut être "mov,mp4,m4a,3gp,3g2,mj2")
    fmt_name = fmt.get("format_name", "")
    container = _normalize_container(fmt_name, path)

    # Colorimetry (HDR detection)
    color_transfer = video_stream.get("color_transfer", "")
    color_primaries = video_stream.get("color_primaries", "")
    color_space = video_stream.get("color_space", "")

    return VideoInfo(
        path=path,
        width=width,
        height=height,
        duration=duration,
        video_codec=video_codec,
        audio_codec=audio_codec,
        video_bitrate=video_kbps,
        audio_bitrate=audio_kbps,
        fps=fps,
        size=size,
        container=container,
        color_transfer=color_transfer,
        color_primaries=color_primaries,
        color_space=color_space,
    )


def _parse_fps(fps_str: str) -> float:
    """Parse '30000/1001' → 29.97, '25/1' → 25.0, etc."""
    try:
        if "/" in fps_str:
            num, den = fps_str.split("/")
            den = int(den)
            if den == 0:
                return 0.0
            return round(int(num) / den, 3)
        return float(fps_str)
    except (ValueError, ZeroDivisionError):
        return 0.0


def _normalize_container(fmt_name: str, path: str) -> str:
    """Normalise le nom de container FFprobe vers mp4/mov/mkv/etc."""
    ext = Path(path).suffix.lower().lstrip(".")
    if "mp4" in fmt_name or ext in ("mp4", "m4v"):
        return "mp4"
    if "mov" in fmt_name or ext == "mov":
        return "mov"
    if "matroska" in fmt_name or ext == "mkv":
        return "mkv"
    if "avi" in fmt_name or ext == "avi":
        return "avi"
    if ext:
        return ext
    return fmt_name.split(",")[0]


# ---------------------------------------------------------------------------
# Exception
# ---------------------------------------------------------------------------

class ProbeError(Exception):
    """Erreur lors de l'analyse ffprobe."""
    pass
