"""
Metadata — Wrapper ExifTool pour copier les métadonnées source vers la variante.

Deux opérations :
  - copy()    : copie les tags d'un fichier source vers la variante (exiftool -TagsFromFile)
  - extract() : lit les tags d'un fichier source et les retourne en dict Python

Tags copiés : titre, description, mots-clés, GPS, date de création, artiste, copyright.

ExifTool est optionnel : si absent, copy() retourne ExifToolResult(skipped=True)
sans lever d'exception. L'appelant choisit si c'est bloquant.
"""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from . import SUBPROCESS_FLAGS


# ---------------------------------------------------------------------------
# Tags copiés par défaut
# ---------------------------------------------------------------------------

DEFAULT_TAGS = [
    "Title",
    "Description",
    "Comment",
    "Keywords",
    "Subject",
    "GPSLatitude",
    "GPSLongitude",
    "GPSAltitude",
    "GPSLatitudeRef",
    "GPSLongitudeRef",
    "CreateDate",
    "DateTimeOriginal",
    "Artist",
    "Author",
    "Copyright",
    "Make",
    "Model",
]


# ---------------------------------------------------------------------------
# Dataclasses résultat
# ---------------------------------------------------------------------------

@dataclass
class ExifToolResult:
    source_path: str
    target_path: str
    tags_copied: int = 0
    skipped: bool = False       # True si exiftool absent ou skip demandé
    error: str = ""


@dataclass
class VideoMetadata:
    """Métadonnées extraites d'un fichier vidéo."""
    title: str = ""
    description: str = ""
    keywords: list[str] = field(default_factory=list)
    gps_lat: float | None = None
    gps_lon: float | None = None
    gps_alt: float | None = None
    date_created: str = ""
    artist: str = ""
    copyright: str = ""
    make: str = ""
    model: str = ""
    raw: dict = field(default_factory=dict)    # données brutes exiftool

    def to_dict(self) -> dict:
        return {
            "title": self.title,
            "description": self.description,
            "keywords": self.keywords,
            "gps": {
                "lat": self.gps_lat,
                "lon": self.gps_lon,
                "alt": self.gps_alt,
            } if self.gps_lat is not None else None,
            "date_created": self.date_created,
            "artist": self.artist,
            "copyright": self.copyright,
            "make": self.make,
            "model": self.model,
        }


# ---------------------------------------------------------------------------
# ExifTool wrapper
# ---------------------------------------------------------------------------

class ExifTool:
    """Wrapper autour de l'exécutable exiftool."""

    def __init__(self, exiftool_path: str = "exiftool"):
        self.binary = exiftool_path

    # -------------------------------------------------------------------
    # Public API
    # -------------------------------------------------------------------

    def copy(
        self,
        source_path: str | Path,
        target_path: str | Path,
        tags: list[str] | None = None,
        overwrite: bool = True,
    ) -> ExifToolResult:
        """
        Copie les métadonnées de source_path vers target_path.

        Si exiftool n'est pas disponible, retourne un résultat avec skipped=True
        sans lever d'exception.
        """
        source_path = str(source_path)
        target_path = str(target_path)

        if not self.check_available():
            return ExifToolResult(
                source_path=source_path,
                target_path=target_path,
                skipped=True,
                error="exiftool introuvable",
            )

        tags_to_copy = tags or DEFAULT_TAGS
        cmd = self._build_copy_cmd(source_path, target_path, tags_to_copy, overwrite)

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
            return ExifToolResult(
                source_path=source_path,
                target_path=target_path,
                skipped=True,
                error=f"exiftool introuvable : '{self.binary}'",
            )
        except subprocess.TimeoutExpired:
            return ExifToolResult(
                source_path=source_path,
                target_path=target_path,
                skipped=False,
                error="exiftool timeout lors de la copie des métadonnées",
            )

        if result.returncode != 0:
            return ExifToolResult(
                source_path=source_path,
                target_path=target_path,
                skipped=False,
                error=f"exiftool a échoué (code {result.returncode}) : {result.stderr.strip()[-300:]}",
            )

        # Compter les tags copiés depuis stdout : "1 image files updated"
        tags_copied = _parse_updated_count(result.stdout)

        return ExifToolResult(
            source_path=source_path,
            target_path=target_path,
            tags_copied=tags_copied,
            skipped=False,
        )

    def extract(self, source_path: str | Path) -> VideoMetadata | None:
        """
        Extrait les métadonnées d'une vidéo en JSON via exiftool.
        Retourne None si exiftool est absent ou si le fichier n'est pas lisible.
        """
        source_path = str(source_path)

        if not self.check_available():
            return None

        cmd = [
            self.binary,
            "-json",
            "-charset", "utf8",
            source_path,
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=30,
                **SUBPROCESS_FLAGS,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return None

        if result.returncode != 0:
            return None

        try:
            data_list = json.loads(result.stdout)
            if not data_list:
                return None
            raw = data_list[0]
        except (json.JSONDecodeError, IndexError):
            return None

        return _parse_exiftool_json(raw)

    def check_available(self) -> bool:
        """Vérifie que exiftool est disponible."""
        try:
            r = subprocess.run(
                [self.binary, "-ver"],
                capture_output=True,
                timeout=5,
                **SUBPROCESS_FLAGS,
            )
            return r.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return False

    def get_version(self) -> str | None:
        """Retourne la version de exiftool ou None."""
        try:
            r = subprocess.run(
                [self.binary, "-ver"],
                capture_output=True,
                text=True,
                timeout=5,
                **SUBPROCESS_FLAGS,
            )
            if r.returncode == 0:
                return r.stdout.strip()
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
        return None

    # -------------------------------------------------------------------
    # Construction de la commande copy
    # -------------------------------------------------------------------

    def _build_copy_cmd(
        self,
        source: str,
        target: str,
        tags: list[str],
        overwrite: bool,
    ) -> list[str]:
        cmd = [self.binary]

        # -TagsFromFile source -Tag1 -Tag2 ...
        cmd += ["-TagsFromFile", source]
        for tag in tags:
            cmd.append(f"-{tag}")

        cmd += ["-charset", "utf8"]

        if overwrite:
            cmd.append("-overwrite_original")

        cmd.append(target)
        return cmd


# ---------------------------------------------------------------------------
# Parsing interne
# ---------------------------------------------------------------------------

def _parse_updated_count(stdout: str) -> int:
    """Parse '1 image files updated' → 1."""
    import re
    m = re.search(r"(\d+)\s+image files? updated", stdout)
    if m:
        return int(m.group(1))
    return 0


def _parse_exiftool_json(raw: dict) -> VideoMetadata:
    """Construit un VideoMetadata depuis la sortie JSON d'exiftool."""

    def _str(key: str) -> str:
        v = raw.get(key, "")
        return str(v).strip() if v else ""

    def _float_gps(key: str, ref_key: str | None = None) -> float | None:
        v = raw.get(key)
        if v is None:
            return None
        # exiftool peut retourner "48 deg 51' 23.40\" N" ou un float
        val = _parse_gps_value(v)
        if val is None:
            return None
        # Appliquer la référence (S/W → négatif)
        if ref_key:
            ref = str(raw.get(ref_key, "")).strip().upper()
            if ref in ("S", "W"):
                val = -abs(val)
        return val

    # Mots-clés : peut être str ou liste
    kw_raw = raw.get("Keywords") or raw.get("Subject") or []
    if isinstance(kw_raw, str):
        keywords = [k.strip() for k in kw_raw.split(",") if k.strip()]
    elif isinstance(kw_raw, list):
        keywords = [str(k).strip() for k in kw_raw if k]
    else:
        keywords = []

    # Titre : Title > Description
    title = (
        _str("Title")
        or _str("DisplayName")
    )
    description = (
        _str("Description")
        or _str("Comment")
        or _str("UserComment")
    )

    # Date : DateTimeOriginal > CreateDate > MediaCreateDate
    date_created = (
        _str("DateTimeOriginal")
        or _str("CreateDate")
        or _str("MediaCreateDate")
    )

    return VideoMetadata(
        title=title,
        description=description,
        keywords=keywords,
        gps_lat=_float_gps("GPSLatitude", "GPSLatitudeRef"),
        gps_lon=_float_gps("GPSLongitude", "GPSLongitudeRef"),
        gps_alt=_float_gps("GPSAltitude"),
        date_created=date_created,
        artist=_str("Artist") or _str("Author"),
        copyright=_str("Copyright"),
        make=_str("Make"),
        model=_str("Model"),
        raw=raw,
    )


def _parse_gps_value(value) -> float | None:
    """
    Parse une valeur GPS exiftool :
      - float brut : retourné tel quel
      - str "48 deg 51' 23.40\" N" : converti en degrés décimaux
      - str "48.8567" : converti en float
    """
    if isinstance(value, (int, float)):
        return float(value)

    s = str(value).strip()
    # Essai direct
    try:
        return float(s)
    except ValueError:
        pass

    # Format DMS : "48 deg 51' 23.40\" N" (on ignore la direction ici)
    import re
    m = re.match(
        r"(\d+)\s*deg\s*(\d+)['′]\s*([\d.]+)[\"″]",
        s,
        re.IGNORECASE,
    )
    if m:
        degrees = int(m.group(1))
        minutes = int(m.group(2))
        seconds = float(m.group(3))
        return degrees + minutes / 60.0 + seconds / 3600.0

    return None


# ---------------------------------------------------------------------------
# Exception
# ---------------------------------------------------------------------------

class MetadataError(Exception):
    """Erreur lors du traitement des métadonnées."""
    pass
