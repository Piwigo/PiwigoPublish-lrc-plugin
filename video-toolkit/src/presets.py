"""
Presets vidéo — Définition et gestion des presets de transcodage.

Presets prédéfinis : Small (480p) → Medium (720p) → Large (1080p)
                     → XLarge (1440p) → XXL (2160p) → Origin (pas de transcodage)
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field, asdict
from pathlib import Path


# ---------------------------------------------------------------------------
# Dataclass VideoPreset
# ---------------------------------------------------------------------------

@dataclass
class VideoPreset:
    name: str
    suffix: str
    max_width: int
    max_height: int
    video_bitrate: int          # kbps
    audio_bitrate: int          # kbps
    video_codec: str = "libx264"
    audio_codec: str = "aac"
    h264_profile: str = "main"
    pixel_format: str = "yuv420p"
    crf: int = 23
    two_pass: bool = False
    container: str = "mp4"
    custom_ffmpeg_args: dict = field(default_factory=dict)

    @property
    def is_origin(self) -> bool:
        return self.suffix == ""

    def hash(self) -> str:
        """Hash stable pour détection de changement de preset."""
        data = json.dumps(asdict(self), sort_keys=True)
        return hashlib.sha256(data.encode()).hexdigest()[:16]

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, name: str, d: dict) -> "VideoPreset":
        d = {k: v for k, v in d.items() if k in cls.__dataclass_fields__ and k != "name"}
        return cls(name=name, **d)


# ---------------------------------------------------------------------------
# Presets prédéfinis (builtin)
# ---------------------------------------------------------------------------

BUILTIN_PRESETS: dict[str, VideoPreset] = {
    "small": VideoPreset(
        name="Small",
        suffix="_small",
        max_width=854,
        max_height=480,
        video_bitrate=800,
        audio_bitrate=96,
        h264_profile="baseline",
        crf=28,
    ),
    "medium": VideoPreset(
        name="Medium",
        suffix="_medium",
        max_width=1280,
        max_height=720,
        video_bitrate=2500,
        audio_bitrate=128,
        h264_profile="main",
        crf=23,
    ),
    "large": VideoPreset(
        name="Large",
        suffix="_large",
        max_width=1920,
        max_height=1080,
        video_bitrate=5000,
        audio_bitrate=192,
        h264_profile="high",
        crf=21,
    ),
    "xlarge": VideoPreset(
        name="XLarge",
        suffix="_xlarge",
        max_width=2560,
        max_height=1440,
        video_bitrate=10000,
        audio_bitrate=256,
        h264_profile="high",
        crf=20,
    ),
    "xxl": VideoPreset(
        name="XXL",
        suffix="_xxl",
        max_width=3840,
        max_height=2160,
        video_bitrate=20000,
        audio_bitrate=320,
        h264_profile="high",
        crf=18,
    ),
    "origin": VideoPreset(
        name="Origin",
        suffix="",
        max_width=99999,
        max_height=99999,
        video_bitrate=0,
        audio_bitrate=0,
        video_codec="copy",
        audio_codec="copy",
    ),
}

PRESET_ORDER = ["small", "medium", "large", "xlarge", "xxl", "origin"]


# ---------------------------------------------------------------------------
# PresetManager
# ---------------------------------------------------------------------------

class PresetManager:
    """Gestion des presets builtin + presets utilisateur (JSON)."""

    def __init__(self, config_path: Path | str | None = None):
        self._builtin: dict[str, VideoPreset] = dict(BUILTIN_PRESETS)
        self._user: dict[str, VideoPreset] = {}
        self._config_path: Path | None = None

        if config_path:
            self.load_presets(config_path)

    # --- Chargement / sauvegarde ---

    def load_presets(self, path: Path | str) -> None:
        """Charge les presets utilisateur depuis un fichier JSON."""
        path = Path(path)
        self._config_path = path

        if not path.exists():
            return

        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)

        for key, d in data.get("presets", {}).items():
            key_lower = key.lower()
            self._user[key_lower] = VideoPreset.from_dict(
                name=d.get("name", key),
                d=d,
            )

    def save_presets(self, path: Path | str | None = None) -> None:
        """Sauvegarde les presets utilisateur dans un fichier JSON."""
        resolved = path or self._config_path
        if resolved is None:
            raise ValueError("Aucun chemin de configuration défini")
        path = Path(resolved)

        path.parent.mkdir(parents=True, exist_ok=True)
        data = {
            "version": 1,
            "presets": {
                key: preset.to_dict()
                for key, preset in self._user.items()
            }
        }
        with path.open("w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

    # --- Accès aux presets ---

    def get_preset(self, name: str) -> VideoPreset:
        """Retourne un preset (user > builtin). Lève KeyError si introuvable."""
        key = name.lower()
        if key in self._user:
            return self._user[key]
        if key in self._builtin:
            return self._builtin[key]
        raise KeyError(f"Preset inconnu : '{name}'")

    def list_presets(self) -> list[tuple[str, VideoPreset]]:
        """Liste tous les presets dans l'ordre logique (builtin + user)."""
        result = []
        seen = set()
        for key in PRESET_ORDER:
            if key in self._user:
                result.append((key, self._user[key]))
                seen.add(key)
            elif key in self._builtin:
                result.append((key, self._builtin[key]))
                seen.add(key)
        # Presets user hors ordre prédéfini
        for key, preset in self._user.items():
            if key not in seen:
                result.append((key, preset))
        return result

    def validate_preset(self, preset: VideoPreset) -> list[str]:
        """Valide un preset. Retourne liste d'erreurs (vide = OK)."""
        errors = []
        if preset.max_width <= 0 or preset.max_height <= 0:
            errors.append("Résolution invalide (max_width/max_height doivent être > 0)")
        if not preset.is_origin:
            if preset.video_bitrate <= 0:
                errors.append("video_bitrate doit être > 0")
            if preset.audio_bitrate <= 0:
                errors.append("audio_bitrate doit être > 0")
            if preset.crf not in range(0, 52):
                errors.append("crf doit être entre 0 et 51")
        if preset.container not in ("mp4", "mkv", "mov"):
            errors.append(f"Container '{preset.container}' non supporté (mp4/mkv/mov)")
        return errors

    def compute_output_resolution(
        self,
        src_width: int,
        src_height: int,
        preset: VideoPreset,
    ) -> tuple[int, int]:
        """
        Calcule la résolution de sortie sans upscale.
        Respecte le ratio d'aspect source, ne dépasse pas le max du preset.
        """
        if preset.is_origin:
            return src_width, src_height

        # Pas d'upscale : si la source est plus petite, on garde la résolution source
        if src_width <= preset.max_width and src_height <= preset.max_height:
            # Aligner sur 2 (requis par yuv420p)
            return _align2(src_width), _align2(src_height)

        # Downscale : conserver le ratio
        scale_w = preset.max_width / src_width
        scale_h = preset.max_height / src_height
        scale = min(scale_w, scale_h)

        out_w = _align2(int(src_width * scale))
        out_h = _align2(int(src_height * scale))
        return out_w, out_h

    def build_ffmpeg_scale_filter(
        self,
        src_width: int,
        src_height: int,
        preset: VideoPreset,
    ) -> str:
        """
        Retourne le filtre FFmpeg scale correspondant à la résolution cible.
        Utilise force_original_aspect_ratio=decrease pour éviter l'upscale.
        """
        mw = preset.max_width
        mh = preset.max_height
        return (
            f"scale='min({mw},iw)':'min({mh},ih)'"
            f":force_original_aspect_ratio=decrease,"
            f"pad=ceil(iw/2)*2:ceil(ih/2)*2"
        )


# ---------------------------------------------------------------------------
# Helpers internes
# ---------------------------------------------------------------------------

def _align2(value: int) -> int:
    """Aligne sur le multiple de 2 inférieur le plus proche."""
    return value if value % 2 == 0 else value - 1
