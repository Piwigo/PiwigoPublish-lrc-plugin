"""
Config — Chargement et sauvegarde de la configuration globale du toolkit.

Séparé des presets : gère les chemins d'outils, les préférences globales,
et le fichier de presets à utiliser.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Chemins par défaut
# ---------------------------------------------------------------------------

DEFAULT_CONFIG_DIR = Path.home() / ".piwigoPublish"
DEFAULT_CONFIG_FILE = DEFAULT_CONFIG_DIR / "video-toolkit.json"
DEFAULT_PRESETS_FILE = DEFAULT_CONFIG_DIR / "presets.json"
DEFAULT_STATUS_FILE = DEFAULT_CONFIG_DIR / ".vtk-status.json"


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

class Config:
    """Configuration globale du Video Toolkit (chemins + préférences)."""

    DEFAULTS = {
        "python_path": "",
        "ffmpeg_path": "",
        "ffprobe_path": "",
        "exiftool_path": "",
        "presets_file": "",
        "default_preset": "medium",
        "generate_poster": True,
        "poster_timestamp_pct": 10,
        "thumbnail_width": 1280,
        "thumbnail_height": 720,
        "thumbnail_quality": 85,
        "copy_metadata": True,
        "hardware_accel": "auto",
        "vtk_dir_name": ".vtk",
    }

    def __init__(self, config_path: Path | str | None = None):
        self._path = Path(config_path) if config_path else DEFAULT_CONFIG_FILE
        self._data: dict = dict(self.DEFAULTS)
        self._load()

    # --- Persistence ---

    def _load(self) -> None:
        if self._path.exists():
            try:
                with self._path.open("r", encoding="utf-8") as f:
                    stored = json.load(f)
                self._data.update(stored)
            except (json.JSONDecodeError, OSError):
                pass  # Garder les defaults si le fichier est corrompu

    def save(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        with self._path.open("w", encoding="utf-8") as f:
            json.dump(self._data, f, indent=2, ensure_ascii=False)

    # --- Accès ---

    def get(self, key: str, default=None):
        return self._data.get(key, default)

    def set(self, key: str, value) -> None:
        self._data[key] = value

    def get_presets_file(self) -> Path:
        p = self._data.get("presets_file", "")
        return Path(p) if p else DEFAULT_PRESETS_FILE

    # --- Résolution des outils ---

    def resolve_tool(self, tool: str) -> str | None:
        """
        Résout le chemin d'un outil (ffmpeg, ffprobe, python, exiftool).
        Ordre : config → PATH → emplacements courants (Windows/macOS/Linux).
        Retourne le chemin trouvé ou None.
        """
        configured = self._data.get(f"{tool}_path", "").strip()
        if configured and Path(configured).is_file():
            return configured

        # PATH système
        found = shutil.which(tool)
        if found:
            return found

        # Emplacements courants par plateforme
        if sys.platform == "win32":
            candidates = _windows_candidates(tool)
        elif sys.platform == "darwin":
            candidates = _macos_candidates(tool)
        else:
            candidates = _linux_candidates(tool)

        for candidate in candidates:
            if Path(candidate).is_file():
                return candidate

        return None

    def tool_status(self) -> dict[str, str | None]:
        """Retourne un dict outil → chemin résolu (None = non trouvé)."""
        tools = ["ffmpeg", "ffprobe", "exiftool"]
        return {t: self.resolve_tool(t) for t in tools}


# ---------------------------------------------------------------------------
# Détection Windows
# ---------------------------------------------------------------------------

def _windows_candidates(tool: str) -> list[str]:
    """Emplacements courants sur Windows pour ffmpeg, ffprobe, exiftool."""
    home = str(Path.home())
    program_files = os.environ.get("ProgramFiles", "C:\\Program Files")
    local_app = os.environ.get("LOCALAPPDATA", home + "\\AppData\\Local")

    # LOCALAPPDATA peut être absent si lancé depuis un process isolé (ex: Lightroom)
    # Fallback sur Path.home() / AppData / Local
    if not local_app:
        local_app = str(Path.home() / "AppData" / "Local")
    winget_links = f"{local_app}\\Microsoft\\WinGet\\Links"
    winget_pkgs  = f"{local_app}\\Microsoft\\WinGet\\Packages"
    candidates_map: dict[str, list[str]] = {
        "ffmpeg": [
            f"{winget_links}\\ffmpeg.exe",
            f"{winget_pkgs}\\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\\ffmpeg-7.1-full_build\\bin\\ffmpeg.exe",
            "C:\\ffmpeg\\bin\\ffmpeg.exe",
            f"{program_files}\\ffmpeg\\bin\\ffmpeg.exe",
            f"{local_app}\\ffmpeg\\bin\\ffmpeg.exe",
        ],
        "ffprobe": [
            f"{winget_links}\\ffprobe.exe",
            f"{winget_pkgs}\\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\\ffmpeg-7.1-full_build\\bin\\ffprobe.exe",
            "C:\\ffmpeg\\bin\\ffprobe.exe",
            f"{program_files}\\ffmpeg\\bin\\ffprobe.exe",
            f"{local_app}\\ffmpeg\\bin\\ffprobe.exe",
        ],
        "exiftool": [
            "C:\\exiftool\\exiftool.exe",
            f"{program_files}\\ExifTool\\exiftool.exe",
            f"{home}\\exiftool.exe",
            "C:\\Windows\\exiftool.exe",
        ],
    }
    return candidates_map.get(tool, [])


def _macos_candidates(tool: str) -> list[str]:
    """Emplacements courants sur macOS pour ffmpeg, ffprobe, exiftool."""
    home = str(Path.home())
    candidates_map: dict[str, list[str]] = {
        "ffmpeg": [
            "/opt/homebrew/bin/ffmpeg",          # Apple Silicon Homebrew
            "/usr/local/bin/ffmpeg",             # Intel Homebrew / manual
            f"{home}/.local/bin/ffmpeg",
        ],
        "ffprobe": [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            f"{home}/.local/bin/ffprobe",
        ],
        "exiftool": [
            "/opt/homebrew/bin/exiftool",
            "/usr/local/bin/exiftool",
            f"{home}/.local/bin/exiftool",
        ],
    }
    return candidates_map.get(tool, [])


def _linux_candidates(tool: str) -> list[str]:
    """Emplacements courants sur Linux pour ffmpeg, ffprobe, exiftool."""
    home = str(Path.home())
    candidates_map: dict[str, list[str]] = {
        "ffmpeg": [
            "/usr/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            f"{home}/.local/bin/ffmpeg",
            "/snap/bin/ffmpeg",
        ],
        "ffprobe": [
            "/usr/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            f"{home}/.local/bin/ffprobe",
            "/snap/bin/ffprobe",
        ],
        "exiftool": [
            "/usr/bin/exiftool",
            "/usr/local/bin/exiftool",
            f"{home}/.local/bin/exiftool",
        ],
    }
    return candidates_map.get(tool, [])
