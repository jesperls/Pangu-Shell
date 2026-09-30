import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SHELL = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("qs"), "quickshell is required for native QML tests")
class ThemeExportsTest(unittest.TestCase):
    def test_native_exports_follow_live_settings(self):
        with tempfile.TemporaryDirectory(prefix="pangu-themes-") as directory:
            root = Path(directory)
            for name in ("config", "modules/globals", "modules/components", "theme", "cache/pangu", "bin", "runtime"):
                (root / name).mkdir(parents=True)
            (root / "runtime").chmod(0o700)
            for source in (SHELL / "modules/theme").glob("*.qml"):
                shutil.copy(source, root / "theme" / source.name)
            for component in ("ThemeReloader", "GeneratedFile"):
                shutil.copy(SHELL / f"modules/components/{component}.qml", root / f"modules/components/{component}.qml")
            (root / "modules/components/qmldir").write_text("ThemeReloader 1.0 ThemeReloader.qml\nGeneratedFile 1.0 GeneratedFile.qml\n")
            (root / "theme/qmldir").write_text("".join(
                ("singleton " if file.stem == "Colors" else "")
                + f"{file.stem} 1.0 {file.name}\n"
                for file in (root / "theme").glob("*.qml")
            ))
            (root / "config/qmldir").write_text(
                "singleton Config 1.0 Config.qml\nsingleton Paths 1.0 Paths.qml\n"
            )
            (root / "config/Config.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool initialLoadComplete: true
    property bool oledMode: false
    property QtObject theme: QtObject {
        property bool lightMode: false
        property string font: "Initial Font"
        property QtObject srBg: QtObject { property real opacity: 0.85 }
    }
}
''')
            (root / "config/Paths.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    readonly property string configHome: %s
    readonly property string cacheHome: %s
    function cachePath(name) { return cacheHome + "/pangu/" + name; }
}
''' % (json.dumps(str(root / "output")), json.dumps(str(root / "cache"))))
            (root / "modules/globals/qmldir").write_text("singleton GlobalStates 1.0 GlobalStates.qml\n")
            wallpaper = "/wallpapers/Quote's $wallpaper.png"
            (root / "modules/globals/GlobalStates.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property var wallpaperManager: ({currentWallpaper: %s}) }
''' % json.dumps(wallpaper))
            shutil.copy(SHELL / "assets/colors/Nord/dark.json", root / "cache/pangu/colors.json")
            for command in ("pkill", "gsettings", "pywalfox", "walogram"):
                stub = root / "bin" / command
                stub.write_text(f"#!{shutil.which('bash')}\n" + (
                    'printf \'%s\\n\' "$*" >> "$PANGU_TEST_GSETTINGS_LOG"\n'
                    if command == "gsettings" else "exit 0\n"
                ))
                stub.chmod(0o755)
            (root / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "theme"
import "config"
ShellRoot {
    property color background: Colors.background
    FileView { id: paletteFile; path: Colors.path }
    Timer {
        interval: 1000; running: true
        onTriggered: Config.theme.lightMode = true
    }
    Timer {
        interval: 500; running: true
        onTriggered: {
            Config.theme.srBg.opacity = 0.5;
            Config.theme.font = "Latest Font";
            const palette = JSON.parse(paletteFile.text());
            palette.background = "#123456";
            paletteFile.setText(JSON.stringify(palette));
        }
    }
    Timer { interval: 2500; running: true; onTriggered: Qt.quit() }
}
''')
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / "runtime"),
                       PANGU_TEST_GSETTINGS_LOG=str(root / "gsettings.log"),
                       XDG_CACHE_HOME=str(root / "cache"), QT_QPA_PLATFORM="offscreen",
                       QML_DISABLE_DISK_CACHE="1", PATH=str(root / "bin") + ":" + os.environ["PATH"])
            env.pop("WAYLAND_DISPLAY", None)
            entrypoints = []
            for version in (3, 4):
                entrypoint = root / f"output/gtk-{version}.0/gtk.css"
                entrypoint.parent.mkdir(parents=True)
                source = root / f"gtk-{version}.css"
                source.write_text(f'@import url("file://{root}/cache/pangu/gtk.css");\n')
                entrypoint.symlink_to(source)
                entrypoints.append((entrypoint, source))
            result = subprocess.run(["qs", "-p", str(root / "shell.qml")], env=env,
                                    capture_output=True, text=True, timeout=15)
            log = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, log)
            settings_calls = (root / "gsettings.log").read_text().splitlines()
            self.assertEqual([line for line in settings_calls if " color-scheme " in line], [
                "set org.gnome.desktop.interface color-scheme prefer-dark",
                "set org.gnome.desktop.interface color-scheme prefer-light",
            ])
            for error in ("TypeError", "ReferenceError", "Failed to load configuration", "Generated file write failed"):
                self.assertNotIn(error, log)
            self.assertIn("background #123456", (root / "cache/pangu/kitty.conf").read_text())
            self.assertIn("background_opacity 0.5", (root / "cache/pangu/kitty.conf").read_text())
            self.assertIn("--font: Latest Font,", (root / "output/vesktop/themes/pangu.css").read_text())
            self.assertEqual((root / "cache/wal/wal").read_text(), wallpaper)
            self.assertTrue((root / "cache/wal/base46-dark.lua").read_text().endswith("return M"))
            json.loads((root / "cache/wal/colors.json").read_text())
            gtk = (root / "cache/pangu/gtk.css").read_text()
            self.assertIn("@define-color window_bg_color rgba(18, 52, 86, 0.5);", gtk)
            for entrypoint, source in entrypoints:
                self.assertTrue(entrypoint.is_symlink())
                self.assertEqual(entrypoint.readlink(), source)
                self.assertEqual(entrypoint.read_text(), f'@import url("file://{root}/cache/pangu/gtk.css");\n')
            qt = (root / "output/qt5ct/colors/pangu.colors").read_text()
            self.assertTrue(qt)
            self.assertEqual(qt, (root / "output/qt6ct/colors/pangu.colors").read_text())
            self.assertEqual(qt.count("[Colors:"), 8)
            for section in ("Button", "Complementary", "Header", "Selection", "Tooltip", "View", "Window"):
                self.assertIn(f"[Colors:{section}]", qt)
            self.assertIn("[Colors:Header][Inactive]", qt)
            self.assertIn("[General]", qt)
