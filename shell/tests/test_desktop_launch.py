import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


@unittest.skipUnless(shutil.which("gtk-launch") and shutil.which("xvfb-run"), "GTK and Xvfb are required")
class DesktopLaunchTest(unittest.TestCase):
    def test_desktop_fields_and_terminal(self):
        with tempfile.TemporaryDirectory(prefix="pangu-launch-") as directory:
            root = Path(directory)
            for name in ("data/applications", "config", "bin", "Working Directory", "runtime"):
                (root / name).mkdir(parents=True)
            (root / "runtime").chmod(0o700)
            output = root / "launched.json"
            terminal = root / "terminal.json"
            capture = root / "bin/capture"
            capture.write_text(f'''#!{sys.executable}
import json, os, sys
from pathlib import Path
Path({str(output)!r}).write_text(json.dumps({{"args": sys.argv[1:], "cwd": os.getcwd()}}))
''')
            capture.chmod(0o755)
            terminal_command = root / "bin/xdg-terminal-exec"
            terminal_command.write_text(f'''#!{sys.executable}
import json, os, sys
from pathlib import Path
Path({str(terminal)!r}).write_text(json.dumps(sys.argv[1:]))
os.execv(sys.argv[1], sys.argv[1:])
''')
            terminal_command.chmod(0o755)
            entry = root / "data/applications/pangu-launch-test.desktop"
            env = dict(os.environ, XDG_DATA_HOME=str(root / "data"), XDG_DATA_DIRS=str(root / "data"),
                       XDG_CONFIG_HOME=str(root / "config"), XDG_RUNTIME_DIR=str(root / "runtime"),
                       DBUS_SESSION_BUS_ADDRESS="unix:path=" + str(root / "absent-bus"),
                       GDK_BACKEND="x11", PATH=str(root / "bin") + ":" + os.environ["PATH"])
            env.pop("WAYLAND_DISPLAY", None)
            for in_terminal in (False, True):
                with self.subTest(terminal=in_terminal):
                    output.unlink(missing_ok=True)
                    entry.write_text(f'''[Desktop Entry]
Type=Application
Name=Quoted App's Name
Exec={capture} %c %k %i %% %f
Icon=test-icon
Path={root / 'Working Directory'}
Terminal={str(in_terminal).lower()}
''')
                    result = subprocess.run(["xvfb-run", "-a", "gtk-launch", "--", entry.stem],
                                            env=env, capture_output=True, text=True, timeout=20)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    deadline = time.monotonic() + 5
                    while not output.exists() and time.monotonic() < deadline:
                        time.sleep(0.02)
                    self.assertTrue(output.exists(), result.stderr)
                    data = json.loads(output.read_text())
                    self.assertEqual(data["cwd"], str(root / "Working Directory"))
                    self.assertEqual(data["args"], ["Quoted App's Name", str(entry), "--icon", "test-icon", "%"])
                    self.assertEqual(terminal.exists(), in_terminal)


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class UsagePersistenceTest(unittest.TestCase):
    def test_native_usage_load_and_save(self):
        with tempfile.TemporaryDirectory(prefix="pangu-usage-") as directory:
            root = Path(directory)
            for name in ("config", "services", "cache", "runtime"):
                (root / name).mkdir()
            (root / "runtime").chmod(0o700)
            shell = Path(__file__).resolve().parents[1]
            shutil.copy(shell / "modules/services/UsageTracker.qml", root / "services/UsageTracker.qml")
            (root / "services/qmldir").write_text("singleton UsageTracker 1.0 UsageTracker.qml\n")
            (root / "modules/components").mkdir(parents=True)
            shutil.copy(shell / "modules/components/JsonStore.qml", root / "modules/components/JsonStore.qml")
            (root / "modules/components/qmldir").write_text("JsonStore 1.0 JsonStore.qml\n")
            (root / "config/qmldir").write_text("singleton Paths 1.0 Paths.qml\n")
            (root / "config/Paths.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    readonly property string cacheDir: %s
    function cachePath(name) { return cacheDir + "/" + name; }
}
''' % json.dumps(str(root / "cache")))
            usage = root / "cache/usage.json"
            usage.write_text(json.dumps({"early": {"count": 4, "lastUsed": 0}, "invalid": None}))
            (root / "shell.qml").write_text('''import QtQuick
import Quickshell
import "services"
ShellRoot {
    Component.onCompleted: UsageTracker.recordUsage("early")
    Timer {
        interval: 500; running: true
        onTriggered: UsageTracker.recordUsage("later")
    }
    Timer { interval: 1500; running: true; onTriggered: Qt.quit() }
}
''')
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / "runtime"), XDG_CACHE_HOME=str(root / "cache"),
                       QT_QPA_PLATFORM="offscreen", QML_DISABLE_DISK_CACHE="1")
            env.pop("WAYLAND_DISPLAY", None)
            result = subprocess.run(["qs", "-p", str(root / "shell.qml")], env=env,
                                    capture_output=True, text=True, timeout=10)
            log = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, log)
            for error in ("TypeError", "ReferenceError", "Failed to load configuration"):
                self.assertNotIn(error, log)
            saved = json.loads(usage.read_text())
            self.assertEqual(saved["early"]["count"], 5)
            self.assertEqual(saved["later"]["count"], 1)
            self.assertNotIn("invalid", saved)
