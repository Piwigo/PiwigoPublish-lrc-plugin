"""
Processor — Orchestration du traitement complet d'une vidéo.

Flux :
  1. Probe       → FFprobe analyse la source (VideoInfo)
  2. Hash        → Hasher calcule l'empreinte partielle de la source
  3. Cache check → StatusManager vérifie si la variante est à jour
  4. Transcode   → FFmpeg encode selon le preset (skip si Origin + cache OK)
  5. Thumbnail   → FFmpeg extrait le poster JPG
  6. Status      → StatusManager met à jour le fichier .vtk/<stem>.json

Utilisé par :
  - video_toolkit.py --mode process   (fichier unique)
  - video_toolkit.py --mode batch     (plusieurs fichiers)
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from .ffmpeg import FFmpeg, FFmpegError
from .ffprobe import FFprobe, ProbeError, VideoInfo
from .hasher import partial_hash
from .metadata import ExifTool
from .presets import PresetManager, VideoPreset
from .status import StatusManager, STATE_PROCESSING, STATE_COMPLETE, STATE_ERROR


# ---------------------------------------------------------------------------
# Résultat de traitement
# ---------------------------------------------------------------------------

@dataclass
class ProcessResult:
    """Résultat retourné après le traitement d'une vidéo."""
    input_path: str
    variant_path: str
    thumbnail_path: str
    preset_key: str
    width: int
    height: int
    duration: float
    size: int                   # octets de la variante
    thumbnail_size: int
    skipped: bool               # True si la variante était déjà à jour
    error: str = ""
    orig: dict | None = None    # métadonnées source (width, height, fps, bitrate, codec, format, filesize)
    conv: dict | None = None    # métadonnées variante (idem)


# ---------------------------------------------------------------------------
# Processeur principal
# ---------------------------------------------------------------------------

class VideoProcessor:
    """
    Orchestre le traitement complet d'une vidéo :
    probe → hash → cache → transcode → thumbnail → status.
    """

    def __init__(
        self,
        ffmpeg_path: str = "ffmpeg",
        ffprobe_path: str = "ffprobe",
        exiftool_path: str = "exiftool",
        preset_manager: PresetManager | None = None,
        thumbnail_timestamp_pct: int = 10,
        thumbnail_max_width: int = 1280,
        copy_metadata: bool = True,
        hwaccel_mode: str = "auto",
    ):
        self._ffmpeg = FFmpeg(ffmpeg_path, hwaccel_mode=hwaccel_mode)
        self._ffprobe = FFprobe(ffprobe_path)
        self._exiftool = ExifTool(exiftool_path)

        self._presets = preset_manager or PresetManager()
        self._thumb_pct = thumbnail_timestamp_pct
        self._thumb_max_w = thumbnail_max_width
        self._copy_metadata = copy_metadata

    # -------------------------------------------------------------------
    # Public API
    # -------------------------------------------------------------------

    def process(
        self,
        input_path: str | Path,
        preset_key: str,
        output_dir: str | Path | None = None,
        force: bool = False,
        thumbnail_only: bool = False,
        dry_run: bool = False,
        progress_callback: Callable[[int], None] | None = None,
    ) -> ProcessResult:
        """
        Traite une vidéo selon le preset donné.

        input_path      : chemin du fichier source
        preset_key      : nom du preset ("small", "medium", etc.)
        output_dir      : dossier de sortie (défaut : même dossier que la source)
        force           : ignore le cache, retraite même si à jour
        thumbnail_only  : ne fait que la miniature, pas de transcode
        dry_run         : simule le traitement sans rien écrire
        progress_callback(pct) : appelé pendant le transcode (0..100)
        """
        input_path = Path(input_path)
        out_dir = Path(output_dir) if output_dir else input_path.parent

        # --- 1. Preset ---
        preset = self._presets.get_preset(preset_key)
        preset_hash = preset.hash()

        # --- 2. Probe ---
        try:
            info: VideoInfo = self._ffprobe.probe(input_path)
        except ProbeError as e:
            return self._error_result(str(input_path), preset_key, str(e))

        # --- 2b. Auto-downgrade preset pour SDR : origin = remux sans réencodage ---
        # Si la source n'est pas HDR et que le preset n'est pas déjà "origin",
        # on bascule sur "origin" (copie directe, sans transcode inutile).
        # Le suffix du preset demandé est conservé pour nommer la variante
        # (ex: preset "medium" SDR → remux → fichier nommé "..._medium.mp4").
        # Le preset_key d'origine est conservé dans le résultat pour Lightroom.
        output_suffix = preset.suffix  # suffix du preset demandé, avant downgrade éventuel
        if not info.is_hdr and not preset.is_origin:
            preset = self._presets.get_preset("origin")
            preset_hash = preset.hash()

        # --- 3. Hash source ---
        src_hash = partial_hash(input_path)

        # --- 4. StatusManager ---
        status = StatusManager(input_path)
        status.set_source(
            hash_val=src_hash,
            size=info.size,
            width=info.width,
            height=info.height,
            duration=info.duration,
            video_codec=info.video_codec,
            audio_codec=info.audio_codec,
            fps=info.fps,
            is_hdr=info.is_hdr,
            color_transfer=info.color_transfer,
        )

        # --- 5. Chemins de sortie ---
        stem = input_path.stem
        # output_suffix : suffix du preset demandé (conservé même si downgrade SDR→origin)
        # preset "origin" explicitement demandé → suffix "" (pas de suffixe, nom source)
        variant_name = f"{stem}{output_suffix}.mp4" if output_suffix else f"{stem}.mp4"
        variant_path = out_dir / variant_name
        thumbnail_path = out_dir / f"{stem}_poster.jpg"

        # --- 6. Cache check variante ---
        if not force and not thumbnail_only:
            if status.has_valid_variant(preset_key, src_hash, preset_hash):
                # Variante à jour → vérifier quand même la miniature
                thumb_skipped = status.has_thumbnail()
                if thumb_skipped and not dry_run:
                    t_info = status.get_thumbnail()
                    t_size = t_info.get("size", 0)
                else:
                    t_size = 0

                # Métadonnées étendues orig/conv (même en cache hit)
                orig_meta = self._video_meta(info)
                conv_meta = None
                if variant_path.exists():
                    try:
                        conv_info = self._ffprobe.probe(variant_path)
                        conv_meta = self._video_meta(conv_info)
                    except ProbeError:
                        pass

                return ProcessResult(
                    input_path=str(input_path),
                    variant_path=str(variant_path),
                    thumbnail_path=str(thumbnail_path),
                    preset_key=preset_key,
                    width=info.width,
                    height=info.height,
                    duration=info.duration,
                    size=Path(variant_path).stat().st_size if variant_path.exists() else 0,
                    thumbnail_size=t_size,
                    skipped=True,
                    orig=orig_meta,
                    conv=conv_meta,
                )

        # --- 7. Transcode ---
        if not thumbnail_only:
            status.set_state(
                STATE_PROCESSING, progress=5,
                current_file=str(input_path),
                pid=os.getpid(),
            )

            # Wrapper progress : transcode = 10%→85% du total
            def _transcode_progress(pct: int) -> None:
                global_pct = 10 + int(pct * 75 / 100)
                status.set_state(
                    STATE_PROCESSING, progress=global_pct,
                    current_file=str(input_path),
                    pid=os.getpid(),
                )
                if progress_callback:
                    progress_callback(global_pct)

            try:
                t_result = self._ffmpeg.transcode(
                    input_path=input_path,
                    output_path=variant_path,
                    preset=preset,
                    preset_manager=self._presets,
                    src_width=info.width,
                    src_height=info.height,
                    src_duration=info.duration,
                    progress_callback=_transcode_progress,
                    dry_run=dry_run,
                    video_info=info,
                )
            except FFmpegError as e:
                status.set_state(STATE_ERROR, error=str(e))
                return self._error_result(str(input_path), preset_key, str(e))

            # Enregistrer la variante dans le statut
            if not dry_run:
                status.set_variant(
                    preset_key=preset_key,
                    preset_hash=preset_hash,
                    variant_path=variant_path,
                    size=t_result.size,
                    width=t_result.width,
                    height=t_result.height,
                    duration=t_result.duration,
                )
        else:
            # thumbnail_only : utiliser les infos source
            t_result = None

        # --- 8. Miniature ---
        status.set_state(
            STATE_PROCESSING, progress=88,
            current_file=str(input_path),
            pid=os.getpid(),
        )

        thumb_size = 0
        if not status.has_thumbnail() or force:
            try:
                # Extract thumbnail from the transcoded variant (SDR colors) when available,
                # not from the HDR source which would produce washed-out colors.
                thumb_source = (
                    variant_path
                    if t_result and not preset.is_origin and variant_path.exists()
                    else input_path
                )
                thumb_duration = t_result.duration if t_result else info.duration
                th_result = self._ffmpeg.thumbnail(
                    input_path=thumb_source,
                    output_path=thumbnail_path,
                    duration=thumb_duration,
                    timestamp_pct=self._thumb_pct,
                    max_width=self._thumb_max_w,
                    dry_run=dry_run,
                )
                thumb_size = th_result.size
                if not dry_run:
                    status.set_thumbnail(
                        path=thumbnail_path,
                        size=thumb_size,
                        timestamp=th_result.timestamp,
                    )
            except FFmpegError as e:
                # Miniature non critique : on log mais on ne bloque pas
                thumb_size = 0
        else:
            t_info = status.get_thumbnail()
            thumb_size = t_info.get("size", 0)

        # --- 9. Copie des métadonnées source → variante ---
        if self._copy_metadata and not thumbnail_only and not dry_run and not preset.is_origin:
            # origin = copie directe, métadonnées déjà présentes
            meta_copy = self._exiftool.copy(
                source_path=input_path,
                target_path=variant_path,
            )
            # Extraction pour le fichier statut (optionnelle, ne bloque pas)
            if not meta_copy.skipped and not meta_copy.error:
                meta_obj = self._exiftool.extract(input_path)
                if meta_obj:
                    status.set_metadata(meta_obj.to_dict())

        # --- 10. Finalisation ---
        status.set_state(STATE_COMPLETE, progress=100)
        if not dry_run:
            status.save()

        if progress_callback:
            progress_callback(100)

        variant_size = (
            t_result.size if t_result and not dry_run
            else (variant_path.stat().st_size if variant_path.exists() else 0)
        )

        # --- 11. Métadonnées étendues orig/conv ---
        orig_meta = self._video_meta(info)
        conv_meta = None
        if not dry_run and not thumbnail_only and variant_path.exists():
            try:
                conv_info = self._ffprobe.probe(variant_path)
                conv_meta = self._video_meta(conv_info)
            except ProbeError:
                pass  # non critique

        return ProcessResult(
            input_path=str(input_path),
            variant_path=str(variant_path),
            thumbnail_path=str(thumbnail_path),
            preset_key=preset_key,
            width=info.width if thumbnail_only or not t_result else t_result.width,
            height=info.height if thumbnail_only or not t_result else t_result.height,
            duration=info.duration,
            size=variant_size,
            thumbnail_size=thumb_size,
            skipped=False,
            orig=orig_meta,
            conv=conv_meta,
        )

    # -------------------------------------------------------------------
    # Batch
    # -------------------------------------------------------------------

    def process_batch(
        self,
        jobs: list[dict],
        global_status_callback: Callable[[int, int, str], None] | None = None,
    ) -> list[ProcessResult]:
        """
        Traite plusieurs vidéos.

        jobs : liste de dicts avec les clés :
            - input  (str)
            - preset (str)
            - output_dir (str, optionnel)
            - force (bool, optionnel)

        global_status_callback(done, total, current_file) est appelé entre les fichiers.
        """
        results: list[ProcessResult] = []
        total = len(jobs)

        for idx, job in enumerate(jobs):
            current = job.get("input", "")
            if global_status_callback:
                global_status_callback(idx, total, current)

            result = self.process(
                input_path=job["input"],
                preset_key=job.get("preset", "medium"),
                output_dir=job.get("output_dir"),
                force=job.get("force", False),
                thumbnail_only=job.get("thumbnail_only", False),
                dry_run=job.get("dry_run", False),
            )
            results.append(result)

        if global_status_callback:
            global_status_callback(total, total, "")

        return results

    # -------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------

    @staticmethod
    def _video_meta(info: VideoInfo) -> dict:
        """Extrait les métadonnées vidéo étendues pour orig/conv."""
        return {
            "width": info.width,
            "height": info.height,
            "fps": info.fps,
            "bitrate": info.video_bitrate,      # kbps
            "codec": info.video_codec,
            "format": info.container,
            "filesize": info.size,
        }

    @staticmethod
    def _error_result(input_path: str, preset_key: str, error: str) -> ProcessResult:
        return ProcessResult(
            input_path=input_path,
            variant_path="",
            thumbnail_path="",
            preset_key=preset_key,
            width=0,
            height=0,
            duration=0.0,
            size=0,
            thumbnail_size=0,
            skipped=False,
            error=error,
        )
