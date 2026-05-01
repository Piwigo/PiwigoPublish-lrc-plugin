"""
Tests unitaires — status.py
Couvre : StatusManager, GlobalStatusFile
"""

import json
import sys
import tempfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from src.status import (
    STATE_COMPLETE,
    STATE_ERROR,
    STATE_PROCESSING,
    GlobalStatusFile,
    StatusManager,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def tmp_video(tmp_path):
    """Crée un fichier vidéo fictif pour StatusManager."""
    p = tmp_path / "test_video.mp4"
    p.write_bytes(b"fake video content")
    return p


@pytest.fixture
def sm(tmp_video):
    return StatusManager(tmp_video)


# ---------------------------------------------------------------------------
# StatusManager — persistence
# ---------------------------------------------------------------------------

class TestStatusManagerPersistence:
    def test_status_file_path(self, tmp_video):
        sm = StatusManager(tmp_video)
        assert sm.path.parent.name == ".vtk"
        assert sm.path.name == "test_video.json"

    def test_save_creates_vtk_dir(self, sm, tmp_video):
        sm.save()
        vtk_dir = tmp_video.parent / ".vtk"
        assert vtk_dir.is_dir()
        assert sm.path.exists()

    def test_save_and_reload(self, tmp_video):
        sm1 = StatusManager(tmp_video)
        sm1.set_source(
            hash_val="abc123",
            size=1000,
            width=1920, height=1080,
            duration=60.0,
            video_codec="h264",
            audio_codec="aac",
            fps=25.0,
        )
        sm1.save()

        sm2 = StatusManager(tmp_video)
        src = sm2.get_source()
        assert src["hash"] == "abc123"
        assert src["width"] == 1920

    def test_delete_removes_file(self, sm):
        sm.save()
        assert sm.path.exists()
        sm.delete()
        assert not sm.path.exists()

    def test_corrupted_json_loads_empty(self, tmp_video):
        vtk_dir = tmp_video.parent / ".vtk"
        vtk_dir.mkdir()
        status_file = vtk_dir / "test_video.json"
        status_file.write_text("{invalid json", encoding="utf-8")

        sm = StatusManager(tmp_video)
        assert sm.get_source() == {}


# ---------------------------------------------------------------------------
# StatusManager — source info
# ---------------------------------------------------------------------------

class TestStatusManagerSource:
    def test_set_get_source(self, sm):
        sm.set_source(
            hash_val="deadbeef",
            size=2048,
            width=640, height=360,
            duration=30.5,
            video_codec="h264",
            audio_codec="aac",
            fps=24.0,
        )
        src = sm.get_source()
        assert src["hash"] == "deadbeef"
        assert src["size"] == 2048
        assert src["resolution"] == "640x360"
        assert src["duration"] == 30.5
        assert src["fps"] == 24.0

    def test_get_source_hash_empty_when_unset(self, sm):
        assert sm.get_source_hash() == ""

    def test_get_source_hash_returns_value(self, sm):
        sm.set_source("myhash", 100, 1280, 720, 10.0, "h264", "aac", 30.0)
        assert sm.get_source_hash() == "myhash"


# ---------------------------------------------------------------------------
# StatusManager — variants
# ---------------------------------------------------------------------------

class TestStatusManagerVariants:
    def test_set_get_variant(self, sm, tmp_video):
        variant_path = tmp_video.parent / "test_video_medium.mp4"
        variant_path.write_bytes(b"variant content")

        sm.set_variant("medium", "presethash", variant_path, 512, 1280, 720, 10.0)
        v = sm.get_variant("medium")
        assert v["size"] == 512
        assert v["preset_hash"] == "presethash"
        assert v["resolution"] == "1280x720"

    def test_get_variant_unknown_returns_empty(self, sm):
        assert sm.get_variant("nonexistent") == {}

    def test_has_valid_variant_true(self, sm, tmp_video):
        variant_path = tmp_video.parent / "test_video_medium.mp4"
        variant_path.write_bytes(b"variant")

        sm.set_source("srchash", 1000, 1920, 1080, 60.0, "h264", "aac", 25.0)
        sm.set_variant("medium", "phash", variant_path, 512, 1280, 720, 60.0)

        assert sm.has_valid_variant("medium", "srchash", "phash") is True

    def test_has_valid_variant_false_wrong_source_hash(self, sm, tmp_video):
        variant_path = tmp_video.parent / "test_video_medium.mp4"
        variant_path.write_bytes(b"variant")

        sm.set_source("srchash", 1000, 1920, 1080, 60.0, "h264", "aac", 25.0)
        sm.set_variant("medium", "phash", variant_path, 512, 1280, 720, 60.0)

        assert sm.has_valid_variant("medium", "DIFFERENT_HASH", "phash") is False

    def test_has_valid_variant_false_wrong_preset_hash(self, sm, tmp_video):
        variant_path = tmp_video.parent / "test_video_medium.mp4"
        variant_path.write_bytes(b"variant")

        sm.set_source("srchash", 1000, 1920, 1080, 60.0, "h264", "aac", 25.0)
        sm.set_variant("medium", "phash", variant_path, 512, 1280, 720, 60.0)

        assert sm.has_valid_variant("medium", "srchash", "DIFFERENT_PRESET_HASH") is False

    def test_has_valid_variant_false_file_deleted(self, sm, tmp_video):
        variant_path = tmp_video.parent / "test_video_medium.mp4"
        variant_path.write_bytes(b"variant")

        sm.set_source("srchash", 1000, 1920, 1080, 60.0, "h264", "aac", 25.0)
        sm.set_variant("medium", "phash", variant_path, 512, 1280, 720, 60.0)

        variant_path.unlink()  # Supprimer le fichier

        assert sm.has_valid_variant("medium", "srchash", "phash") is False


# ---------------------------------------------------------------------------
# StatusManager — thumbnail
# ---------------------------------------------------------------------------

class TestStatusManagerThumbnail:
    def test_set_get_thumbnail(self, sm, tmp_video):
        thumb = tmp_video.parent / "test_video.jpg"
        thumb.write_bytes(b"jpg data")

        sm.set_thumbnail(thumb, 10240, "00:00:01")
        t = sm.get_thumbnail()
        assert t["size"] == 10240
        assert t["timestamp"] == "00:00:01"

    def test_has_thumbnail_true(self, sm, tmp_video):
        thumb = tmp_video.parent / "test_video.jpg"
        thumb.write_bytes(b"jpg")
        sm.set_thumbnail(thumb, 100, "00:00:01")
        assert sm.has_thumbnail() is True

    def test_has_thumbnail_false_when_unset(self, sm):
        assert sm.has_thumbnail() is False

    def test_has_thumbnail_false_when_file_missing(self, sm, tmp_video):
        thumb = tmp_video.parent / "missing.jpg"
        sm.set_thumbnail(thumb, 100, "00:00:01")
        assert sm.has_thumbnail() is False


# ---------------------------------------------------------------------------
# StatusManager — state
# ---------------------------------------------------------------------------

class TestStatusManagerState:
    def test_set_state_saves_immediately(self, sm):
        sm.set_state(STATE_PROCESSING, progress=50, current_file="test.mp4")
        assert sm.path.exists()

    def test_get_state(self, sm):
        sm.set_state(STATE_PROCESSING, progress=30)
        s = sm.get_state()
        assert s["status"] == STATE_PROCESSING
        assert s["progress"] == 30

    def test_is_complete(self, sm):
        sm.set_state(STATE_COMPLETE)
        assert sm.is_complete() is True
        assert sm.is_error() is False

    def test_is_error(self, sm):
        sm.set_state(STATE_ERROR, error="ffmpeg failed")
        assert sm.is_error() is True
        assert sm.is_complete() is False

    def test_state_not_complete_by_default(self, sm):
        assert sm.is_complete() is False


# ---------------------------------------------------------------------------
# GlobalStatusFile
# ---------------------------------------------------------------------------

class TestGlobalStatusFile:
    def test_update_creates_file(self, tmp_path):
        gsf = GlobalStatusFile(tmp_path / "status.json")
        gsf.update(STATE_PROCESSING, progress=10, total=5, done=1)
        assert (tmp_path / "status.json").exists()

    def test_update_content(self, tmp_path):
        p = tmp_path / "status.json"
        gsf = GlobalStatusFile(p)
        gsf.update(STATE_PROCESSING, progress=50, current_file="vid.mp4", total=3, done=1)

        data = json.loads(p.read_text())
        assert data["state"] == STATE_PROCESSING
        assert data["progress"] == 50
        assert data["current_file"] == "vid.mp4"
        assert data["total"] == 3

    def test_mark_complete(self, tmp_path):
        p = tmp_path / "status.json"
        gsf = GlobalStatusFile(p)
        gsf.mark_complete(files=["a.mp4", "b.mp4"])

        data = json.loads(p.read_text())
        assert data["state"] == STATE_COMPLETE
        assert data["progress"] == 100
        assert "a.mp4" in data["files"]

    def test_mark_error(self, tmp_path):
        p = tmp_path / "status.json"
        gsf = GlobalStatusFile(p)
        gsf.mark_error("Something went wrong")

        data = json.loads(p.read_text())
        assert data["state"] == STATE_ERROR
        assert data["error"] == "Something went wrong"

    def test_creates_parent_dir(self, tmp_path):
        p = tmp_path / "subdir" / "deep" / "status.json"
        gsf = GlobalStatusFile(p)
        gsf.update(STATE_PROCESSING)
        assert p.exists()
