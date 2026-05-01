"""
Status — Gestion du fichier statut .vtk/<filename>.json

Le statut stocke :
  - info source (hash, taille, résolution, codecs, durée, fps)
  - variantes générées par preset
  - miniature
  - métadonnées extraites
  - état en cours (processing/complete/error) pour le polling Lightroom
"""

from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path


# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

VTK_DIR = ".vtk"

STATE_PROCESSING = "processing"
STATE_COMPLETE   = "complete"
STATE_ERROR      = "error"
STATE_IDLE       = "idle"


# ---------------------------------------------------------------------------
# StatusManager
# ---------------------------------------------------------------------------

class StatusManager:
    """
    Gère le fichier statut d'une vidéo dans le sous-dossier .vtk/.

    Chemin : <video_dir>/.vtk/<video_stem>.json
    """

    def __init__(self, video_path: str | Path, vtk_dir_name: str = VTK_DIR):
        self._video = Path(video_path)
        self._vtk_dir = self._video.parent / vtk_dir_name
        self._status_file = self._vtk_dir / (self._video.stem + ".json")
        self._data: dict = {}
        self._load()

    # --- Persistence ---

    def _load(self) -> None:
        if self._status_file.exists():
            try:
                with self._status_file.open("r", encoding="utf-8") as f:
                    self._data = json.load(f)
            except (json.JSONDecodeError, OSError):
                self._data = {}

    def save(self) -> None:
        self._vtk_dir.mkdir(parents=True, exist_ok=True)
        with self._status_file.open("w", encoding="utf-8") as f:
            json.dump(self._data, f, indent=2, ensure_ascii=False)

    def delete(self) -> None:
        if self._status_file.exists():
            self._status_file.unlink()

    # --- Infos source ---

    def set_source(
        self,
        hash_val: str,
        size: int,
        width: int,
        height: int,
        duration: float,
        video_codec: str,
        audio_codec: str,
        fps: float,
        is_hdr: bool = False,
        color_transfer: str = "",
    ) -> None:
        self._data["source"] = {
            "path": str(self._video),
            "hash": hash_val,
            "size": size,
            "resolution": f"{width}x{height}",
            "width": width,
            "height": height,
            "duration": duration,
            "video_codec": video_codec,
            "audio_codec": audio_codec,
            "fps": fps,
            "is_hdr": is_hdr,
            "color_transfer": color_transfer,
        }

    def get_source(self) -> dict:
        return self._data.get("source", {})

    def get_source_hash(self) -> str:
        return self.get_source().get("hash", "")

    # --- Variantes ---

    def set_variant(
        self,
        preset_key: str,
        preset_hash: str,
        variant_path: str | Path,
        size: int,
        width: int,
        height: int,
        duration: float,
    ) -> None:
        if "variants" not in self._data:
            self._data["variants"] = {}
        self._data["variants"][preset_key] = {
            "path": str(variant_path),
            "size": size,
            "resolution": f"{width}x{height}",
            "duration": duration,
            "preset_hash": preset_hash,
            "created": _now_iso(),
        }

    def get_variant(self, preset_key: str) -> dict:
        return self._data.get("variants", {}).get(preset_key, {})

    def has_valid_variant(self, preset_key: str, source_hash: str, preset_hash: str) -> bool:
        """
        Vérifie si une variante est à jour :
        - Fichier variante existe
        - Hash source identique (source n'a pas changé)
        - Hash preset identique (preset n'a pas changé)
        """
        variant = self.get_variant(preset_key)
        if not variant:
            return False
        if variant.get("preset_hash") != preset_hash:
            return False
        if self.get_source_hash() != source_hash:
            return False
        # Vérifier que le fichier existe toujours
        variant_path = variant.get("path", "")
        return bool(variant_path) and Path(variant_path).exists()

    # --- Miniature ---

    def set_thumbnail(self, path: str | Path, size: int, timestamp: str) -> None:
        self._data["thumbnail"] = {
            "path": str(path),
            "size": size,
            "timestamp": timestamp,
        }

    def get_thumbnail(self) -> dict:
        return self._data.get("thumbnail", {})

    def has_thumbnail(self) -> bool:
        t = self.get_thumbnail()
        if not t:
            return False
        return Path(t.get("path", "")).exists()

    # --- Métadonnées ---

    def set_metadata(self, meta: dict) -> None:
        self._data["metadata"] = meta

    def get_metadata(self) -> dict:
        return self._data.get("metadata", {})

    # --- État (polling Lightroom) ---

    def set_state(
        self,
        state: str,
        progress: int = 0,
        current_file: str = "",
        error: str = "",
        pid: int = 0,
    ) -> None:
        self._data["state"] = {
            "status": state,
            "progress": progress,
            "current_file": current_file,
            "error": error,
            "pid": pid,
            "updated": _now_iso(),
        }
        self.save()  # Sauvegarde immédiate pour le polling

    def get_state(self) -> dict:
        return self._data.get("state", {})

    def is_complete(self) -> bool:
        return self.get_state().get("status") == STATE_COMPLETE

    def is_error(self) -> bool:
        return self.get_state().get("status") == STATE_ERROR

    # --- Chemin du fichier statut ---

    @property
    def path(self) -> Path:
        return self._status_file


# ---------------------------------------------------------------------------
# Fichier statut global (pour le batch / polling Lightroom)
# ---------------------------------------------------------------------------

class GlobalStatusFile:
    """
    Fichier statut global utilisé lors des traitements batch.
    Lightroom lit ce fichier pour mettre à jour la barre de progression.
    """

    def __init__(self, path: str | Path):
        self._path = Path(path)
        self._data: dict = {}

    def update(
        self,
        state: str,
        progress: int = 0,
        current_file: str = "",
        total: int = 0,
        done: int = 0,
        error: str = "",
        pid: int = 0,
    ) -> None:
        self._data = {
            "state": state,
            "progress": progress,
            "current_file": current_file,
            "total": total,
            "done": done,
            "error": error,
            "pid": pid or os.getpid(),
            "updated": _now_iso(),
        }
        self._path.parent.mkdir(parents=True, exist_ok=True)
        with self._path.open("w", encoding="utf-8") as f:
            json.dump(self._data, f, indent=2)

    def mark_complete(self, files: list[str] | None = None) -> None:
        self.update(state=STATE_COMPLETE, progress=100)
        if files is not None:
            self._data["files"] = files
            with self._path.open("w", encoding="utf-8") as f:
                json.dump(self._data, f, indent=2)

    def mark_error(self, error: str) -> None:
        self.update(state=STATE_ERROR, error=error)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")
