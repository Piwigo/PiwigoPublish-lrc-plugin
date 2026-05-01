"""
HWAccel — Détection et configuration de l'accélération matérielle GPU.

Encodeurs supportés :
  - NVIDIA NVENC  (h264_nvenc)
  - AMD AMF       (h264_amf)
  - Intel QSV     (h264_qsv)
  - Apple VT      (h264_videotoolbox)
  - Linux VA-API  (h264_vaapi)

Usage :
    detector = HWAccelDetector(ffmpeg_binary)
    config = detector.resolve("auto", crf=23, profile="high", is_hdr=False)
    # config is None → CPU, else → GPU encoder ready
"""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass, field
from typing import List, Optional

from . import SUBPROCESS_FLAGS


# ---------------------------------------------------------------------------
# HWEncoder — description d'un encodeur matériel
# ---------------------------------------------------------------------------

@dataclass
class HWEncoder:
    name: str                           # label humain ("NVIDIA NVENC")
    codec: str                          # codec ffmpeg ("h264_nvenc")
    hwaccel: str                        # valeur -hwaccel ("cuda", "qsv", "")
    quality_param: str                  # param qualité ("-cq", "-qp", "-global_quality", "")
    supported_profiles: List[str]       # profils H264 supportés
    needs_vaapi_device: bool = False
    vaapi_device: str = "/dev/dri/renderD128"

    def supports_profile(self, profile: str) -> bool:
        return not self.supported_profiles or profile in self.supported_profiles


# ---------------------------------------------------------------------------
# HWAccelConfig — décision résolue pour la commande ffmpeg
# ---------------------------------------------------------------------------

@dataclass
class HWAccelConfig:
    encoder: HWEncoder
    effective_codec: str                # = encoder.codec
    pre_input_args: List[str]           # args avant -i (["-hwaccel", "cuda"])
    quality_override: List[str]         # remplace [-crf N] (["-cq", "23"])
    extra_vf_prefix: str                # préfixe -vf ("hwupload," pour vaapi, "" sinon)


# ---------------------------------------------------------------------------
# Registre des encodeurs par plateforme (ordre = priorité)
# ---------------------------------------------------------------------------

_PROFILES_STANDARD = ["baseline", "main", "high"]

_ENCODER_REGISTRY: dict = {
    "win32": [
        HWEncoder("NVIDIA NVENC", "h264_nvenc", "cuda",  "-cq",             _PROFILES_STANDARD),
        HWEncoder("AMD AMF",      "h264_amf",   "",      "-qp",             _PROFILES_STANDARD),
        HWEncoder("Intel QSV",    "h264_qsv",   "qsv",  "-global_quality",  _PROFILES_STANDARD),
    ],
    "darwin": [
        HWEncoder("Apple VideoToolbox", "h264_videotoolbox", "videotoolbox", "", _PROFILES_STANDARD),
    ],
    "linux": [
        HWEncoder("NVIDIA NVENC", "h264_nvenc", "cuda",  "-cq",             _PROFILES_STANDARD),
        HWEncoder("Intel QSV",    "h264_qsv",   "qsv",  "-global_quality",  _PROFILES_STANDARD),
        HWEncoder("VA-API",       "h264_vaapi",  "vaapi", "-qp",
                  ["constrained_baseline", "main", "high"],
                  needs_vaapi_device=True),
    ],
}


# ---------------------------------------------------------------------------
# HWAccelDetector
# ---------------------------------------------------------------------------

class HWAccelDetector:
    """Détecte les encodeurs GPU disponibles via `ffmpeg -encoders`."""

    def __init__(self, ffmpeg_binary: str = "ffmpeg"):
        self._binary = ffmpeg_binary
        self._available: Optional[set] = None  # cache

    def _query_encoders(self) -> set:
        """Parse `ffmpeg -encoders` et retourne les noms d'encodeurs vidéo."""
        if self._available is not None:
            return self._available
        try:
            r = subprocess.run(
                [self._binary, "-encoders"],
                capture_output=True, text=True, timeout=10,
                **SUBPROCESS_FLAGS,
            )
            names: set = set()
            for line in r.stdout.splitlines():
                parts = line.split()
                if len(parts) >= 2 and parts[0].startswith("V"):
                    names.add(parts[1])
            self._available = names
        except Exception:
            self._available = set()
        return self._available

    def list_available(self) -> List[HWEncoder]:
        """Retourne les encodeurs GPU disponibles sur ce système."""
        os_key = sys.platform if sys.platform in ("win32", "darwin") else "linux"
        candidates = _ENCODER_REGISTRY.get(os_key, [])
        available = self._query_encoders()
        return [enc for enc in candidates if enc.codec in available]

    def pick_best(self) -> Optional[HWEncoder]:
        """Premier encodeur disponible selon la priorité plateforme."""
        avail = self.list_available()
        return avail[0] if avail else None

    def resolve(
        self,
        mode: str,
        preset_crf: int,
        preset_profile: str,
        is_hdr: bool,
    ) -> Optional[HWAccelConfig]:
        """
        Résout la configuration hwaccel.

        Retourne None → utiliser libx264 (CPU).
        Retourne HWAccelConfig → utiliser le GPU.

        is_hdr=True → toujours None (tonemap software-only).
        """
        if mode == "cpu":
            return None
        if is_hdr:
            return None

        if mode in ("auto", "gpu"):
            encoder = self.pick_best()
        else:
            # mode = nom d'encodeur explicite (ex: "h264_nvenc")
            available = self.list_available()
            encoder = next((e for e in available if e.codec == mode), None)

        if encoder is None:
            if mode == "gpu":
                return None  # pas d'encodeur GPU trouvé
            return None

        # Vérifier compatibilité profil H264
        if not encoder.supports_profile(preset_profile):
            if encoder.supports_profile("high"):
                pass  # on laisse ffmpeg gérer
            else:
                return None

        return _build_config(encoder, preset_crf)


def _build_config(encoder: HWEncoder, crf: int) -> HWAccelConfig:
    """Construit HWAccelConfig depuis un HWEncoder sélectionné."""
    pre_input: List[str] = []
    if encoder.hwaccel:
        pre_input = ["-hwaccel", encoder.hwaccel]
        if encoder.needs_vaapi_device:
            pre_input += ["-vaapi_device", encoder.vaapi_device]

    # Paramètre qualité
    if encoder.quality_param:
        quality_override = [encoder.quality_param, str(crf)]
    else:
        # VideoToolbox : pas de param qualité, bitrate seul
        quality_override = []

    # VA-API nécessite hwupload dans -vf
    extra_vf = "hwupload," if encoder.codec == "h264_vaapi" else ""

    return HWAccelConfig(
        encoder=encoder,
        effective_codec=encoder.codec,
        pre_input_args=pre_input,
        quality_override=quality_override,
        extra_vf_prefix=extra_vf,
    )
