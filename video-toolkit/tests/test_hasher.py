"""
Tests unitaires — hasher.py
Couvre : partial_hash (stabilité, sensibilité aux changements, fichiers petits/grands)
"""

import hashlib
import sys
import tempfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from src.hasher import CHUNK_SIZE, partial_hash


def _write_tmp(content: bytes) -> Path:
    """Écrit content dans un fichier temporaire et retourne le Path."""
    f = tempfile.NamedTemporaryFile(delete=False, suffix=".bin")
    f.write(content)
    f.close()
    return Path(f.name)


class TestPartialHash:
    def test_returns_string(self):
        p = _write_tmp(b"hello world")
        try:
            h = partial_hash(p)
            assert isinstance(h, str)
        finally:
            p.unlink()

    def test_hash_is_32_chars(self):
        p = _write_tmp(b"hello world")
        try:
            assert len(partial_hash(p)) == 32
        finally:
            p.unlink()

    def test_stable_same_content(self):
        content = b"A" * 1000
        p = _write_tmp(content)
        try:
            assert partial_hash(p) == partial_hash(p)
        finally:
            p.unlink()

    def test_different_content_different_hash(self):
        p1 = _write_tmp(b"content A" * 100)
        p2 = _write_tmp(b"content B" * 100)
        try:
            assert partial_hash(p1) != partial_hash(p2)
        finally:
            p1.unlink()
            p2.unlink()

    def test_size_change_detected(self):
        """Un octet supplémentaire doit changer le hash (taille incluse)."""
        p1 = _write_tmp(b"A" * 500)
        p2 = _write_tmp(b"A" * 501)
        try:
            assert partial_hash(p1) != partial_hash(p2)
        finally:
            p1.unlink()
            p2.unlink()

    def test_small_file_below_two_chunks(self):
        """Fichier < 2*CHUNK_SIZE : seul le début est lu."""
        content = b"X" * (CHUNK_SIZE - 1)
        p = _write_tmp(content)
        try:
            h = partial_hash(p)
            assert isinstance(h, str) and len(h) == 32
        finally:
            p.unlink()

    def test_large_file_reads_head_and_tail(self):
        """Fichier > 2*CHUNK_SIZE : début ET fin sont lus.
        Un changement au milieu peut ne pas être détecté (par conception),
        mais un changement en fin de fichier DOIT l'être.
        """
        base = b"A" * (CHUNK_SIZE * 3)
        modified = base[:-10] + b"Z" * 10  # Modification en fin de fichier

        p1 = _write_tmp(base)
        p2 = _write_tmp(modified)
        try:
            assert partial_hash(p1) != partial_hash(p2)
        finally:
            p1.unlink()
            p2.unlink()

    def test_empty_file(self):
        """Fichier vide ne doit pas lever d'exception."""
        p = _write_tmp(b"")
        try:
            h = partial_hash(p)
            assert isinstance(h, str)
        finally:
            p.unlink()

    def test_nonexistent_file_raises(self, tmp_path):
        with pytest.raises((FileNotFoundError, OSError)):
            partial_hash(tmp_path / "__nonexistent__.mp4")
