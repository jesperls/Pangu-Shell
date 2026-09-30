import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


class CaptureToolsTest(unittest.TestCase):
    def run_tool(self, name, **settings):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "bin"
            binary.mkdir()
            temporary = root / "tmp"
            temporary.mkdir()
            stub = binary / "stub"
            stub.write_text("#!" + sys.executable + "\n" + """import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
root = pathlib.Path(os.environ["TEST_ROOT"])
with (root / "calls").open("a") as stream:
    stream.write(json.dumps([name] + sys.argv[1:]) + "\\n")
if name == "slurp":
    print("0,0 20x20")
elif name in ("tesseract", "zbarimg"):
    sys.stdout.write(os.environ.get("TEXT", "recognized"))
elif name == "magick" and "info:-" in sys.argv:
    print("32 64 128")
elif name == "wl-copy":
    (root / "clipboard").write_bytes(sys.stdin.buffer.read())
sys.exit(int(os.environ.get(name.upper().replace("-", "_") + "_STATUS", "0")))
""")
            stub.chmod(0o755)
            for command in ("slurp", "grim", "tesseract", "zbarimg", "wl-copy", "notify-send", "magick"):
                (binary / command).symlink_to(stub)
            env = dict(os.environ, PATH=str(binary) + ":" + os.environ["PATH"],
                       TEST_ROOT=str(root), TMPDIR=str(temporary))
            env.update({key: str(value) for key, value in settings.items()})
            command = [sys.executable, str(SCRIPTS / "colorpicker.py")] if name == "colorpicker" else ["bash", str(SCRIPTS / (name + ".sh"))]
            result = subprocess.run(command, env=env,
                                    capture_output=True, text=True, timeout=10)
            calls = [json.loads(line) for line in (root / "calls").read_text().splitlines()]
            clipboard = (root / "clipboard").read_bytes() if (root / "clipboard").exists() else None
            self.assertEqual(list(temporary.iterdir()), [], "Capture temporary file leaked")
            return result.returncode, calls, clipboard

    def test_cancel_does_not_capture(self):
        for tool in ("ocr", "qr_scan", "colorpicker"):
            with self.subTest(tool=tool):
                code, calls, clipboard = self.run_tool(tool, SLURP_STATUS=1)
                self.assertEqual(code, 0)
                self.assertEqual([call[0] for call in calls], ["slurp"])
                self.assertIsNone(clipboard)

    def test_capture_failure_stops_recognition(self):
        for tool in ("ocr", "qr_scan", "colorpicker"):
            with self.subTest(tool=tool):
                code, calls, clipboard = self.run_tool(tool, GRIM_STATUS=1)
                self.assertEqual(code, 1)
                self.assertFalse(any(call[0] in ("tesseract", "zbarimg") for call in calls))
                self.assertIsNone(clipboard)

    def test_recognition_failure_is_not_empty_result(self):
        for tool, setting in (("ocr", "TESSERACT_STATUS"), ("qr_scan", "ZBARIMG_STATUS")):
            with self.subTest(tool=tool):
                code, calls, clipboard = self.run_tool(tool, **{setting: 1})
                self.assertEqual(code, 1)
                self.assertIn("recognition failed", calls[-1][2])
                self.assertIsNone(clipboard)

    def test_no_barcode_is_not_error(self):
        code, calls, clipboard = self.run_tool("qr_scan", ZBARIMG_STATUS=4, TEXT="")
        self.assertEqual(code, 0)
        self.assertEqual(calls[-1][2], "No code detected")
        self.assertIsNone(clipboard)

    def test_clipboard_failure_is_reported(self):
        for tool in ("ocr", "qr_scan", "colorpicker"):
            with self.subTest(tool=tool):
                code, calls, _ = self.run_tool(tool, WL_COPY_STATUS=1)
                self.assertEqual(code, 1)
                self.assertIn("Could not", calls[-1][2])

    def test_literal_content_is_preserved(self):
        for tool in ("ocr", "qr_scan"):
            for content in ("-n", r"-e hello\nworld", "two\nlines"):
                with self.subTest(tool=tool, content=content):
                    code, _, clipboard = self.run_tool(tool, TEXT=content)
                    self.assertEqual(code, 0)
                    self.assertEqual(clipboard, content.encode())


    def test_color_capture_and_conversion_failure(self):
        code, calls, clipboard = self.run_tool("colorpicker")
        self.assertEqual(code, 0)
        self.assertEqual(clipboard, b"#204080")
        code, calls, clipboard = self.run_tool("colorpicker", MAGICK_STATUS=1)
        self.assertEqual(code, 1)
        self.assertIsNone(clipboard)
        self.assertIn("Could not", calls[-1][2])
