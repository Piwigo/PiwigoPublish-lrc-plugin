"""
Hasher — Hash partiel SHA-256 pour la détection de changement de fichier source.

Stratégie : premiers 64 KB + derniers 64 KB + taille → rapide même sur gros fichiers.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

CHUNK_SIZE = 65536  # 64 KB


def partial_hash(path: str | Path) -> str:
    """
    Calcule un hash partiel SHA-256 d'un fichier.
    Lit les CHUNK_SIZE premiers octets + les CHUNK_SIZE derniers octets + la taille.
    Suffisant pour détecter un changement de contenu sans lire tout le fichier.
    """
    path = Path(path)
    size = path.stat().st_size

    h = hashlib.sha256()
    h.update(str(size).encode())  # Inclure la taille

    with path.open("rb") as f:
        # Début
        h.update(f.read(CHUNK_SIZE))

        # Fin (si le fichier est assez grand)
        if size > CHUNK_SIZE * 2:
            f.seek(-CHUNK_SIZE, 2)
            h.update(f.read(CHUNK_SIZE))

    return h.hexdigest()[:32]
