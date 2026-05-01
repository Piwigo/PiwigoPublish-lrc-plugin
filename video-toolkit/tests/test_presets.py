"""
Tests unitaires — presets.py
Couvre : VideoPreset, PresetManager, compute_output_resolution, _align2
"""

import json
import sys
import tempfile
from pathlib import Path

import pytest

# Ajout du répertoire parent pour l'import
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.presets import (
    BUILTIN_PRESETS,
    PRESET_ORDER,
    PresetManager,
    VideoPreset,
    _align2,
)


# ---------------------------------------------------------------------------
# _align2
# ---------------------------------------------------------------------------

class TestAlign2:
    def test_even_unchanged(self):
        assert _align2(100) == 100

    def test_odd_decremented(self):
        assert _align2(101) == 100

    def test_one(self):
        assert _align2(1) == 0

    def test_zero(self):
        assert _align2(0) == 0


# ---------------------------------------------------------------------------
# VideoPreset
# ---------------------------------------------------------------------------

class TestVideoPreset:
    def test_is_origin_true_when_suffix_empty(self):
        p = BUILTIN_PRESETS["origin"]
        assert p.is_origin is True

    def test_is_origin_false_for_medium(self):
        p = BUILTIN_PRESETS["medium"]
        assert p.is_origin is False

    def test_hash_is_16_chars(self):
        p = BUILTIN_PRESETS["medium"]
        h = p.hash()
        assert isinstance(h, str)
        assert len(h) == 16

    def test_hash_stable(self):
        p = BUILTIN_PRESETS["medium"]
        assert p.hash() == p.hash()

    def test_hash_differs_between_presets(self):
        assert BUILTIN_PRESETS["medium"].hash() != BUILTIN_PRESETS["large"].hash()

    def test_to_dict_roundtrip(self):
        p = BUILTIN_PRESETS["medium"]
        d = p.to_dict()
        p2 = VideoPreset.from_dict(p.name, d)
        assert p2.name == p.name
        assert p2.max_width == p.max_width
        assert p2.crf == p.crf

    def test_from_dict_ignores_unknown_keys(self):
        src = BUILTIN_PRESETS["small"]
        d = src.to_dict()
        d["unknown_field"] = "should_be_ignored"
        # Should not raise
        p = VideoPreset.from_dict(src.name, d)
        assert p.name == src.name


# ---------------------------------------------------------------------------
# PresetManager — builtin access
# ---------------------------------------------------------------------------

class TestPresetManagerBuiltin:
    def setup_method(self):
        self.pm = PresetManager()

    def test_get_builtin_preset(self):
        p = self.pm.get_preset("medium")
        assert p.name == "Medium"
        assert p.max_height == 720

    def test_get_preset_case_insensitive(self):
        p = self.pm.get_preset("MEDIUM")
        assert p.name == "Medium"

    def test_get_unknown_preset_raises(self):
        with pytest.raises(KeyError):
            self.pm.get_preset("nonexistent")

    def test_list_presets_order(self):
        presets = self.pm.list_presets()
        keys = [k for k, _ in presets]
        for expected_key in PRESET_ORDER:
            assert expected_key in keys

    def test_all_builtin_presets_present(self):
        listed = {k for k, _ in self.pm.list_presets()}
        for key in BUILTIN_PRESETS:
            assert key in listed


# ---------------------------------------------------------------------------
# PresetManager — user presets (load / save / override)
# ---------------------------------------------------------------------------

class TestPresetManagerUserPresets:
    def test_load_user_preset_overrides_builtin(self):
        data = {
            "version": 1,
            "presets": {
                "medium": {
                    "name": "Medium Custom",
                    "suffix": "_medium",
                    "max_width": 1280,
                    "max_height": 720,
                    "video_bitrate": 9999,
                    "audio_bitrate": 128,
                }
            }
        }
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False, encoding="utf-8") as f:
            json.dump(data, f)
            tmp = Path(f.name)

        try:
            pm = PresetManager(tmp)
            p = pm.get_preset("medium")
            assert p.video_bitrate == 9999
            assert p.name == "Medium Custom"
        finally:
            tmp.unlink()

    def test_load_nonexistent_file_no_error(self):
        pm = PresetManager(Path("/nonexistent/path/presets.json"))
        # Should still have builtin presets
        p = pm.get_preset("small")
        assert p.name == "Small"

    def test_save_and_reload(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir) / "presets.json"
            pm = PresetManager()
            # Add a user preset by direct manipulation
            pm._user["custom"] = VideoPreset(
                name="Custom",
                suffix="_custom",
                max_width=640,
                max_height=360,
                video_bitrate=500,
                audio_bitrate=64,
            )
            pm.save_presets(config_path)

            pm2 = PresetManager(config_path)
            p = pm2.get_preset("custom")
            assert p.max_width == 640
            assert p.max_height == 360


# ---------------------------------------------------------------------------
# PresetManager — validate_preset
# ---------------------------------------------------------------------------

class TestValidatePreset:
    def setup_method(self):
        self.pm = PresetManager()

    def test_valid_medium_no_errors(self):
        p = BUILTIN_PRESETS["medium"]
        errors = self.pm.validate_preset(p)
        assert errors == []

    def test_invalid_resolution(self):
        p = VideoPreset(
            name="Bad", suffix="_bad",
            max_width=0, max_height=720,
            video_bitrate=1000, audio_bitrate=128,
        )
        errors = self.pm.validate_preset(p)
        assert any("Résolution" in e for e in errors)

    def test_invalid_bitrate_non_origin(self):
        p = VideoPreset(
            name="Bad", suffix="_bad",
            max_width=1280, max_height=720,
            video_bitrate=0, audio_bitrate=128,
        )
        errors = self.pm.validate_preset(p)
        assert any("video_bitrate" in e for e in errors)

    def test_invalid_crf(self):
        p = VideoPreset(
            name="Bad", suffix="_bad",
            max_width=1280, max_height=720,
            video_bitrate=1000, audio_bitrate=128,
            crf=99,
        )
        errors = self.pm.validate_preset(p)
        assert any("crf" in e for e in errors)

    def test_invalid_container(self):
        p = VideoPreset(
            name="Bad", suffix="_bad",
            max_width=1280, max_height=720,
            video_bitrate=1000, audio_bitrate=128,
            container="avi",
        )
        errors = self.pm.validate_preset(p)
        assert any("Container" in e for e in errors)

    def test_origin_skips_bitrate_check(self):
        p = BUILTIN_PRESETS["origin"]  # video_bitrate=0, audio_bitrate=0
        errors = self.pm.validate_preset(p)
        assert errors == []


# ---------------------------------------------------------------------------
# PresetManager — compute_output_resolution
# ---------------------------------------------------------------------------

class TestComputeOutputResolution:
    def setup_method(self):
        self.pm = PresetManager()

    def _preset(self, key):
        return BUILTIN_PRESETS[key]

    # --- Cas : source plus grande que le preset → downscale ---

    def test_landscape_1080p_to_720p(self):
        w, h = self.pm.compute_output_resolution(1920, 1080, self._preset("medium"))
        assert w == 1280
        assert h == 720

    def test_landscape_2160p_to_1080p(self):
        w, h = self.pm.compute_output_resolution(3840, 2160, self._preset("large"))
        assert w == 1920
        assert h == 1080

    def test_portrait_1080_to_720(self):
        # Source 1080x1920 (portrait) → preset medium 1280x720
        # Contrainte hauteur : 720/1920 = 0.375 → 1080*0.375=405, 1920*0.375=720
        w, h = self.pm.compute_output_resolution(1080, 1920, self._preset("medium"))
        assert h == 720
        assert w == 404  # 405 → align2 → 404

    # --- Cas : source plus petite que le preset → pas d'upscale ---

    def test_no_upscale_small_source(self):
        # Source 640x360 → preset medium 1280x720 : pas d'upscale
        w, h = self.pm.compute_output_resolution(640, 360, self._preset("medium"))
        assert w == 640
        assert h == 360

    def test_no_upscale_odd_dimensions_aligned(self):
        # Source 641x361 → align2 → 640x360
        w, h = self.pm.compute_output_resolution(641, 361, self._preset("medium"))
        assert w == 640
        assert h == 360

    # --- Cas : origin → résolution source inchangée ---

    def test_origin_passthrough(self):
        w, h = self.pm.compute_output_resolution(3840, 2160, self._preset("origin"))
        assert w == 3840
        assert h == 2160

    # --- Résolution toujours multiple de 2 ---

    def test_output_always_even_width(self):
        w, _ = self.pm.compute_output_resolution(1921, 1081, self._preset("medium"))
        assert w % 2 == 0

    def test_output_always_even_height(self):
        _, h = self.pm.compute_output_resolution(1921, 1081, self._preset("medium"))
        assert h % 2 == 0

    # --- Ratio d'aspect conservé ---

    def test_aspect_ratio_preserved_landscape(self):
        w, h = self.pm.compute_output_resolution(1920, 1080, self._preset("medium"))
        # Ratio source : 16/9 → ratio sortie doit être ≈ 16/9
        assert abs(w / h - 16 / 9) < 0.02
