import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/wallpaper_properties.py"
spec = importlib.util.spec_from_file_location("wallpaper_properties", SCRIPT)
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class WallpaperPropertiesTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="pangu-properties-' ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.wall = self.root / "wallpaper"
        self.wall.mkdir()
        env = patch.dict(os.environ, {"XDG_CONFIG_HOME": str(self.root / "config")})
        env.start()
        self.addCleanup(env.stop)
        self.definitions = {
            "bloom": {"type": "bool", "text": "<hr>Bloom<hr>", "value": True, "order": 2},
            "speed": {"type": "slider", "min": -1, "max": 3, "step": 0.1, "value": 0},
            "mode": {"type": "combo", "value": 0, "options": [{"label": "Off", "value": 0}, {"text": "On", "value": 1}]},
            "tint": {"type": "color", "value": "0.1 0.2 0.3"},
            "heading": {"type": "text", "text": "<big>Appearance</big>"},
            "file": {"type": "usershortcut", "value": "texture.jpg"},
        }
        self.write_project()

    def write_project(self, **extra):
        self.project = {"general": {"properties": self.definitions}, **extra}
        (self.wall / "project.json").write_text(json.dumps(self.project))

    def write_config(self, name, data):
        path = self.root / "config" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))
        return path

    def test_metadata_preserves_order_defaults_zero_and_choice_labels(self):
        loaded = backend.load(str(self.wall))
        props = {prop["name"]: prop for prop in loaded["properties"]}
        self.assertEqual(loaded["properties"][-1]["name"], "bloom")
        self.assertEqual(props["bloom"]["label"], "Bloom")
        self.assertEqual(props["heading"]["label"], "Appearance")
        self.assertFalse(props["file"]["supported"])
        self.assertEqual(props["mode"]["options"], [{"label": "Off", "value": "0"}, {"label": "On", "value": "1"}])
        self.assertEqual(loaded["values"], {"bloom": "1", "speed": "0", "mode": "0", "tint": "0.1 0.2 0.3"})

    def test_top_level_properties_scheme_color_and_object_choices(self):
        (self.wall / "project.json").write_text(json.dumps({"properties": {
            "mode": {"type": "combolist", "value": "a", "options": {"First": "a", "Second": "b"}}
        }, "schemecolor": "1 0 0"}))
        loaded = backend.load(str(self.wall))
        self.assertEqual(loaded["values"], {"schemecolor": "1 0 0", "mode": "a"})
        self.assertEqual(loaded["properties"][0]["label"], "Theme color")

    def test_text_and_file_values_preserve_empty_strings_and_literal_content(self):
        self.definitions.update({
            "seed": {"type": "textinput", "value": ""},
            "image": {"type": "file", "value": "texture.jpg"},
            "folder": {"type": "directory", "value": ""},
        })
        self.write_project()
        self.assertEqual(backend.load(str(self.wall))["values"]["seed"], "")
        backend.save(str(self.wall), {"seed": "hello\nworld=1", "image": "/Pictures/Quote's image.png", "folder": ""})
        self.assertEqual(backend.load(str(self.wall))["values"]["seed"], "hello\nworld=1")
        self.assertEqual(backend.load(str(self.wall))["values"]["image"], "/Pictures/Quote's image.png")
        with self.assertRaises(ValueError):
            backend.save(str(self.wall), {"seed": "null\0character"})

    def test_save_overrides_inherited_values_and_keeps_other_wallpapers(self):
        directory = str(self.wall)
        legacy = self.write_config("Linux Wallpaper Engine/wallpaper-overrides.json", {"overrides": {
            directory: {"customProperties": {"bloom": True, "speed": 2, "caption": "literal $value;\nsecond=line"}}
        }})
        legacy_before = legacy.read_bytes()
        original = (self.wall / "project.json").read_bytes()
        self.write_config("pangu/wallpaper-engine.json", {"other": {"bloom": "1"}})
        self.assertEqual(backend.load(directory)["values"]["speed"], "2")
        backend.save(directory, {"bloom": False, "speed": 0, "mode": "1", "tint": "1 0.25 0"})
        values = backend.load(directory)["values"]
        self.assertEqual(values["bloom"], "0")
        self.assertEqual(values["speed"], "0")
        saved = json.loads((self.root / "config/pangu/wallpaper-engine.json").read_text())
        self.assertEqual(saved["other"], {"bloom": "1"})
        self.assertEqual(legacy.read_bytes(), legacy_before)
        self.assertEqual((self.wall / "project.json").read_bytes(), original)
        args = subprocess.run(["python3", str(SCRIPT), "arguments", directory], capture_output=True, check=True).stdout.split(b"\0")
        self.assertIn(b"bloom=0", args)
        self.assertIn(b"speed=0", args)
        self.assertIn(b"caption=literal $value;\nsecond=line", args)
        backend.save(directory, {prop["name"]: prop["default"] for prop in backend.properties(directory) if prop["supported"]})
        self.assertEqual(backend.load(directory)["values"]["speed"], "0")

    def test_invalid_edits_do_not_change_saved_file(self):
        path = self.write_config("pangu/wallpaper-engine.json", {str(self.wall): {"speed": "1"}})
        before = path.read_bytes()
        for edit in ({"speed": 4}, {"speed": "nan"}, {"tint": "1 0"}, {"tint": "2 0 0"}, {"mode": "9"}, {"bloom": "yes"}, {"file": "anything"}):
            with self.subTest(edit=edit), self.assertRaises(ValueError):
                backend.save(str(self.wall), edit)
            self.assertEqual(path.read_bytes(), before)

    def test_corrupt_storage_is_reported_without_overwriting(self):
        path = self.write_config("pangu/wallpaper-engine.json", {})
        path.write_text("broken JSON")
        result = subprocess.run(["python3", str(SCRIPT), "save", str(self.wall), '{"speed": 1}'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Could not read or save", result.stderr)
        self.assertEqual(path.read_text(), "broken JSON")

    def test_empty_and_malformed_properties(self):
        (self.wall / "project.json").write_text("{}")
        self.assertEqual(backend.load(str(self.wall)), {"properties": [], "values": {}})
        self.definitions["speed"]["max"] = -1
        self.definitions["mode"]["options"] = None
        self.write_project()
        props = {prop["name"]: prop for prop in backend.properties(str(self.wall))}
        self.assertFalse(props["mode"]["supported"])
        self.assertFalse(props["speed"]["supported"])
