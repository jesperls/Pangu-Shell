import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


SHELL = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class GuiBindingsTest(unittest.TestCase):
    def test_tray_restores_hidden_apps_without_losing_early_edits(self):
        with tempfile.TemporaryDirectory(prefix="pangu-tray-") as directory:
            root = Path(directory)
            services = root / "modules/services"
            backend = root / "testtray"
            services.mkdir(parents=True)
            backend.mkdir()
            source = (SHELL / "modules/services/TrayService.qml").read_text()
            (services / "TrayService.qml").write_text(source.replace("import Quickshell.Services.SystemTray", "import qs.testtray"))
            (services / "qmldir").write_text("singleton TrayService 1.0 TrayService.qml\nsingleton StateService 1.0 StateService.qml\n")
            (services / "StateService.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool initialized: false
    property var saved: ["chat", "music", "chat", null, 42, ""]
    property int writes: 0
    signal stateLoaded
    function get(key, fallback) { return saved; }
    function set(key, value) { saved = value; writes++; }
}
''')
            (backend / "qmldir").write_text("singleton SystemTray 1.0 SystemTray.qml\n")
            (backend / "SystemTray.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property var items: ({values: [{id: "chat"}, {id: "music"}, {id: "mail"}]}) }
''')
            self.run_scene(root, '''import QtQuick
import Quickshell
import qs.modules.services
import qs.testtray
ShellRoot {
    Component.onCompleted: {
        TrayService.setHidden({id: "mail"}, true);
        TrayService.setHidden({id: "chat"}, false);
        if (StateService.writes !== 0) console.log("CHECK_FAILED premature save");
        StateService.initialized = true;
        StateService.stateLoaded();
        if (TrayService.hiddenIds.join(",") !== "music,mail" || StateService.writes !== 1)
            console.log("CHECK_FAILED restore");
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            if (TrayService.visibleItems.length !== 1 || TrayService.visibleItems[0].id !== "chat")
                console.log("CHECK_FAILED visible items");
            SystemTray.items = {values: [{id: "mail"}, {id: "new"}]};
            if (TrayService.hiddenItems.length !== 1 || TrayService.visibleItems.length !== 1)
                console.log("CHECK_FAILED reconnect");
            TrayService.setHidden({id: "mail"}, false);
            if (TrayService.hiddenItems.length || StateService.saved.join(",") !== "music")
                console.log("CHECK_FAILED unhide");
            StateService.stateLoaded();
            if (StateService.writes !== 2) console.log("CHECK_FAILED duplicate restore");
            console.log("CHECK_PASSED"); Qt.quit();
        }
    }
}
''')

    def test_tray_overflow_builds_management_and_hidden_icon_layouts(self):
        with tempfile.TemporaryDirectory(prefix="pangu-tray-ui-") as directory:
            root = Path(directory)
            for name in ("config", "modules/theme", "modules/components", "modules/services", "tray"):
                (root / name).mkdir(parents=True)
            for name in ("SysTray.qml", "SysTrayItem.qml", "TrayIcon.qml", "SystrayMenuItem.qml"):
                source = (SHELL / "modules/bar/systray" / name).read_text()
                (root / "tray" / name).write_text(source.replace("required property SystemTrayItem", "required property var"))
            (root / "modules/services/qmldir").write_text("singleton TrayService 1.0 TrayService.qml\n")
            (root / "modules/services/TrayService.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property var items: [{id: "mail", title: "Mail", icon: "", menu: null}, {id: "music", title: "Music", icon: "", menu: null}]
    property var hiddenIds: []
    readonly property var visibleItems: items.filter(item => !isHidden(item))
    readonly property var hiddenItems: items.filter(item => isHidden(item))
    function isHidden(item) { return hiddenIds.includes(item.id); }
    function setHidden(item, hidden) { hiddenIds = hidden ? [item.id] : []; }
}
''')
            (root / "config/qmldir").write_text("singleton Config 1.0 Config.qml\n")
            (root / "config/Config.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property var bar: ({trayIconSize: 20, traySpacing: 8, trayIconStyle: "original"})
    property var theme: ({font: "Sans", fontSize: 12})
    property bool tintIcons: false
}
''')
            theme = root / "modules/theme"
            (theme / "qmldir").write_text("singleton Styling 1.0 Styling.qml\nsingleton Colors 1.0 Colors.qml\nsingleton Icons 1.0 Icons.qml\n")
            (theme / "Styling.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property int animDuration: 0; function radius(n) { return 8; } function fontSize(n) { return 12 + n; } function srItem(n) { return "white"; } }\n')
            (theme / "Colors.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property color overBackground: "white"; property color overSurfaceVariant: "gray"; property color primary: "orange" }\n')
            shutil.copy(SHELL / "modules/theme/Icons.qml", theme / "Icons.qml")
            components = root / "modules/components"
            (components / "qmldir").write_text("StyledRect 1.0 StyledRect.qml\nStyledToolTip 1.0 StyledToolTip.qml\nTinted 1.0 Tinted.qml\nBarPopup 1.0 BarPopup.qml\nControlChip 1.0 ControlChip.qml\n")
            (components / "StyledRect.qml").write_text('import QtQuick\nItem { property real radius; property color color; property string variant: "common"; property color item: "white"; property real topLeftRadius; property real topRightRadius; property real bottomLeftRadius; property real bottomRightRadius; default property alias contentData: bodyContent.data; property Item body: Item { id: bodyContent; parent: root; anchors.fill: parent }; id: root }\n')
            shutil.copy(SHELL / "modules/components/StyledToolTip.qml", components / "StyledToolTip.qml")
            shutil.copy(SHELL / "modules/components/ControlChip.qml", components / "ControlChip.qml")
            (components / "Tinted.qml").write_text('import QtQuick\nItem { property var sourceItem; property bool active; property bool fullTint }\n')
            (components / "BarPopup.qml").write_text('''import QtQuick
Item {
    property var bar; property var anchorItem; property var parentPopup
    property string groupId; property int popupPadding; property int visualMargin
    property int contentWidth; property int contentHeight
    property bool isOpen: false
    visible: isOpen
    width: contentWidth; height: contentHeight
    function open() { isOpen = true; }
    function close() { isOpen = false; }
    function toggle() { isOpen = !isOpen; }
}
''')
            self.run_scene(root, '''import QtQuick
import Quickshell
import qs.modules.services
import qs.modules.components
import "tray"
ShellRoot {
    QtObject { id: bar; property string orientation: "horizontal"; property string barPosition: "top"; property string screenName: "test" }
    FloatingWindow {
        visible: true; implicitHeight: 200; implicitWidth: 400
        SysTray { id: tray; bar: bar }
        ControlChip { text: "Wallpaper tint"; checked: true }
    }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const match = find(child, name); if (match) return match; }
        return null;
    }
    property int step: 0
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            if (step === 0) find(tray, "trayOverflow").clicked();
            else if (step === 1) {
                if (!tray.managing || !find(tray, "trayManagement")) console.log("CHECK_FAILED management");
                TrayService.setHidden(TrayService.items[0], true);
                find(tray, "trayOverflow").clicked();
                find(tray, "trayOverflow").clicked();
            } else if (step === 2) {
                if (tray.managing || TrayService.hiddenItems.length !== 1) console.log("CHECK_FAILED overflow");
                const hiddenIcon = find(tray, "trayItem-mail");
                if (!hiddenIcon || hiddenIcon.item.id !== "mail" || !hiddenIcon.ownerPopup.isOpen)
                    console.log("CHECK_FAILED hidden icon ownership");
                bar.orientation = "vertical";
                bar.barPosition = "left";
            } else if (step === 3) {
                if (!tray.vertical || tray.implicitHeight <= tray.implicitWidth) console.log("CHECK_FAILED orientation", tray.vertical, tray.implicitWidth, tray.implicitHeight);
                console.log("CHECK_PASSED"); Qt.quit();
            }
            step++;
        }
    }
}
''')

    def test_wallpaper_gallery_keeps_selection_and_adapts_to_density(self):
        with tempfile.TemporaryDirectory(prefix="pangu-gallery-") as directory:
            root = Path(directory)
            self.prepare_settings(root)
            gallery = root / "gallery"
            gallery.mkdir()
            shutil.copy(SHELL / "modules/widgets/dashboard/wallpapers/WallpapersTab.qml", gallery / "WallpapersTab.qml")
            config = root / "config/Config.qml"
            source = config.read_text().replace('property QtObject theme:', 'property var dashboard: ({wallpaperCardWidth: 160, wallpaperShowNames: true})\n    property QtObject theme:')
            source = source.replace('property int fontSize: 11', 'property bool oledMode: false\n        property bool lightMode: false\n        property int fontSize: 11')
            config.write_text(source)
            theme = root / "modules/theme"
            with (theme / "qmldir").open("a") as stream:
                stream.write("singleton Icons 1.0 Icons.qml\n")
            shutil.copy(SHELL / "modules/theme/Icons.qml", theme / "Icons.qml")
            colors = theme / "Colors.qml"
            colors.write_text(colors.read_text().replace('readonly property color error:', 'readonly property color primary: "orange"\n    readonly property color outline: "gray"\n    readonly property color surface: "black"\n    readonly property color error:'))
            components = root / "modules/components"
            (components / "qmldir").write_text("StyledRect 1.0 StyledRect.qml\nStyledToolTip 1.0 StyledToolTip.qml\nControlChip 1.0 ControlChip.qml\n")
            (components / "StyledRect.qml").write_text('''import QtQuick
Item {
    id: root
    property string variant; property real radius; property color item: "white"
    default property alias contentData: body.data
    property Item content: Item { id: body; parent: root; anchors.fill: parent }
}
''')
            for name in ("ControlChip.qml", "StyledToolTip.qml"):
                shutil.copy(SHELL / "modules/components" / name, components / name)
            (gallery / "SearchInput.qml").write_text('''import QtQuick
Item {
    height: 48
    property string text; property string placeholderText; property string iconText
    property bool clearOnEscape; property bool handleTabNavigation; property bool disableCursorNavigation
    property real radius
    signal searchTextChanged(string text)
    signal escapePressed; signal tabPressed; signal shiftTabPressed
    signal downPressed; signal upPressed; signal leftPressed; signal rightPressed; signal accepted
    function focusInput() {}
}
''')
            (gallery / "SchemeSelector.qml").write_text('import QtQuick\nItem { signal schemeSelectorClosed; signal escapePressedOnScheme; signal tabPressed; signal shiftTabPressed; function openAndFocus() {} }\n')
            (gallery / "FilterBar.qml").write_text('import QtQuick\nItem { height: 24; implicitWidth: 400; property var activeFilters: []; signal escapePressedOnFilters; signal tabPressed; signal shiftTabPressed; function focusFilters() {} }\n')
            globals_dir = root / "modules/globals"
            globals_dir.mkdir()
            (globals_dir / "qmldir").write_text("singleton GlobalStates 1.0 GlobalStates.qml\n")
            (globals_dir / "GlobalStates.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property int wallpaperSelectedIndex: -1
    property bool dashboardOpen: false
    property QtObject wallpaperManager: QtObject {
        property var wallpaperPaths: ["/first.png", "/second.png", "/third.png"]
        property var perScreenWallpapers: ({})
        property string currentWallpaper: "/second.png"
        property bool tintEnabled: false
        function scanSubfolders() {}
        function getDisplayName(path) { return path.split("/").pop(); }
        function getFileType(path) { return "image"; }
        function getSubfolderFromPath(path) { return ""; }
    }
}
''')
            services = root / "modules/services"
            with (services / "qmldir").open("a") as stream:
                stream.write("singleton Compositor 1.0 Compositor.qml\nsingleton Visibilities 1.0 Visibilities.qml\n")
            (services / "Compositor.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var focusedMonitor: ({name: "test"}) }\n')
            (services / "Visibilities.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function setActiveModule(name) {} }\n')
            self.run_scene(root, '''import QtQuick
import Quickshell
import qs.config
import qs.modules.globals
import "gallery"
ShellRoot {
    FloatingWindow {
        visible: true; implicitWidth: 800; implicitHeight: 430
        WallpapersTab { id: gallery; anchors.fill: parent }
    }
    property int step: 0
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            if (step === 0) {
                if (gallery.selectedPath !== "/second.png" || gallery.gridColumns !== 4) console.log("CHECK_FAILED initial selection");
                GlobalStates.wallpaperManager.wallpaperPaths = ["/third.png", "/first.png", "/second.png"];
            } else if (step === 1) {
                if (gallery.selectedIndex !== 2 || gallery.selectedPath !== "/second.png") console.log("CHECK_FAILED reordered selection");
                gallery.searchText = "missing";
            } else if (step === 2) {
                if (gallery.selectedIndex !== -1 || gallery.filteredWallpapers.length) console.log("CHECK_FAILED empty search");
                gallery.searchText = "";
                Config.dashboard = {wallpaperCardWidth: 240, wallpaperShowNames: false};
            } else if (step === 3) {
                if (gallery.selectedPath !== "/second.png" || gallery.gridColumns !== 3 || gallery.showNames) console.log("CHECK_FAILED density");
                console.log("CHECK_PASSED"); Qt.quit();
            }
            step++;
        }
    }
}
''')

    def test_frozen_capture_routes_ocr_qr_and_cleans_temporary_images(self):
        with tempfile.TemporaryDirectory(prefix="pangu-capture-") as directory:
            root = Path(directory)
            for name in ("config", "modules/services", "modules/globals", "modules/theme", "bin"):
                (root / name).mkdir(parents=True)
            services = root / "modules/services"
            shutil.copy(SHELL / "modules/services/Screenshot.qml", services / "Screenshot.qml")
            (services / "qmldir").write_text("singleton Screenshot 1.0 Screenshot.qml\nsingleton Visibilities 1.0 Visibilities.qml\nsingleton Compositor 1.0 Compositor.qml\nsingleton LauncherActions 1.0 LauncherActions.qml\n")
            (services / "Visibilities.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function setActiveModule(name) {} }\n')
            (services / "Compositor.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var monitors: ({values: []}); property var clients: ({values: []}) }\n')
            (services / "LauncherActions.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function ocrLangString() { return "eng+jpn"; } }\n')
            (root / "config/qmldir").write_text("singleton Paths 1.0 Paths.qml\n")
            (root / "config/Paths.qml").write_text('''pragma Singleton
import Quickshell
Singleton {
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") + "/pangu"
    readonly property string picturesDir: Quickshell.env("XDG_CACHE_HOME") + "/pictures"
    function runtimePath(name) { return runtimeDir + "/" + name; }
    function script(name) { return SCRIPT_ROOT + "/" + name; }
}
'''.replace("SCRIPT_ROOT", json.dumps(str(SHELL / "scripts"))))
            (root / "modules/globals/qmldir").write_text("singleton GlobalStates 1.0 GlobalStates.qml\n")
            (root / "modules/globals/GlobalStates.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool screenshotToolVisible: false }\n')
            (root / "modules/theme/qmldir").write_text("singleton Styling 1.0 Styling.qml\n")
            (root / "modules/theme/Styling.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property int animDuration: 0 }\n')
            stub = root / "bin/stub"
            stub.write_text(f"#!{shutil.which('python3')}\n" + '''import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ["PANGU_CAPTURE_LOG"], "a") as log:
    log.write(json.dumps([name] + sys.argv[1:]) + "\\n")
if name in ("grim", "magick"):
    pathlib.Path(sys.argv[-1]).write_bytes(b"frozen frame")
elif name in ("tesseract", "zbarimg"):
    print("recognized")
elif name == "wl-copy":
    sys.stdin.buffer.read()
elif name == "xdg-user-dir":
    print(pathlib.Path(os.environ["XDG_CACHE_HOME"]) / "pictures")
''')
            stub.chmod(0o755)
            for name in ("grim", "magick", "tesseract", "zbarimg", "wl-copy", "notify-send", "xdg-user-dir"):
                (root / "bin" / name).symlink_to(stub)
            self.run_scene(root, '''import QtQuick
import Quickshell
import qs.modules.services
import qs.modules.globals
ShellRoot {
    id: root
    property int step: 0
    Component.onCompleted: Screenshot.startCapture("ocr")
    Connections {
        target: GlobalStates
        function onScreenshotToolVisibleChanged() {
            if (GlobalStates.screenshotToolVisible) Screenshot.freezeScreen();
        }
    }
    Connections {
        target: Screenshot
        function onMonitorScreenshotReady(name, path) {
            Screenshot.processRegion(10, 20, 30, 40);
            GlobalStates.screenshotToolVisible = false;
            Screenshot.cancelCapture();
        }
        function onErrorOccurred(message) { console.log("CHECK_FAILED", message); Qt.quit(); }
        function onImageSaved(path) { root.step = 4; }
    }
    Connections {
        target: Screenshot.toolProcess
        function onExited(code) {
            if (code !== 0) { console.log("CHECK_FAILED recognition"); Qt.quit(); return; }
            root.step++;
        }
    }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            if (Screenshot.cleanupProcess.running || Screenshot.toolProcess.running) return;
            if (root.step === 1) {
                root.step = 2;
                Screenshot.startCapture("qr");
            } else if (root.step === 3) {
                Screenshot.startCapture("lens");
                Screenshot.cancelCapture();
                root.step = 5;
                Screenshot.startCapture();
            } else if (root.step === 4 && !Screenshot.copyProcess.running) {
                console.log("CHECK_PASSED"); Qt.quit();
            }
        }
    }
}
''', {"PATH": str(root / "bin") + ":" + os.environ["PATH"], "PANGU_CAPTURE_LOG": str(root / "calls.jsonl")})
            calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
            self.assertEqual([call[0] for call in calls].count("grim"), 3)
            self.assertEqual([call[0] for call in calls].count("wl-copy"), 3)
            self.assertEqual([call[0] for call in calls].count("tesseract"), 1)
            self.assertEqual([call[0] for call in calls].count("zbarimg"), 1)
            runtime = root / "runtime/pangu"
            self.assertFalse(list(runtime.glob("ocr_*.png")))
            self.assertFalse(list(runtime.glob("qr_*.png")))
            self.assertEqual(len(list((root / "cache/pictures/Screenshots").glob("*.png"))), 1)

    def test_tmux_details_ignore_late_replies_and_coalesce_selections(self):
        with tempfile.TemporaryDirectory(prefix="pangu-tmux-") as directory:
            root = Path(directory)
            services = root / "modules/services"
            services.mkdir(parents=True)
            shutil.copy(SHELL / "modules/services/TmuxSessionInfo.qml", services / "TmuxSessionInfo.qml")
            (services / "qmldir").write_text("TmuxSessionInfo 1.0 TmuxSessionInfo.qml\n")
            (root / "bin").mkdir()
            stub = root / "bin/tmux"
            stub.write_text(f"#!{shutil.which('python3')}\n" + '''import json, os, sys, time
command = sys.argv[1]
session = sys.argv[sys.argv.index("-t") + 1]
with open(os.environ["PANGU_TEST_TMUX_LOG"], "a") as log:
    log.write(json.dumps([command, session]) + "\\n")
time.sleep((0.15 if command == "list-windows" else 0.3) if session == "first" else 0.02)
if session == "missing":
    sys.exit(1)
if command == "list-windows":
    print("0:1:" + session + ":editor")
else:
    print("0:80:20:0:0:1:command:" + session)
    print("1:80:10:20:0:0:shell")
''')
            stub.chmod(0o755)
            self.run_scene(root, '''import QtQuick
import Quickshell
import "modules/services"
ShellRoot {
    property int step: 0
    TmuxSessionInfo {
        id: info
        sessionName: "first"
        onWindowsChanged: {
            if (windows.some(window => window.name.startsWith("first")))
                console.log("CHECK_FAILED stale windows");
        }
        onPanesChanged: {
            if (panes.some(pane => pane.command.endsWith("first")))
                console.log("CHECK_FAILED stale panes");
        }
    }
    Timer { interval: 10; running: true; onTriggered: info.sessionName = "middle" }
    Timer { interval: 20; running: true; onTriggered: info.sessionName = "last" }
    Timer {
        interval: 600; running: true; repeat: true
        onTriggered: {
            if (step === 0) {
                if (info.loading || info.windows.length !== 1 || info.windows[0].name !== "last:editor"
                    || info.panes.length !== 2 || info.panes[0].command !== "command:last"
                    || info.panes[0].totalWidth !== 80 || info.panes[0].totalHeight !== 30) {
                    console.log("CHECK_FAILED latest details"); Qt.quit(); return;
                }
                info.sessionName = "missing";
            } else {
                if (info.loading || info.windows.length || info.panes.length) {
                    console.log("CHECK_FAILED failed query state"); Qt.quit(); return;
                }
                info.sessionName = "";
                console.log("CHECK_PASSED"); Qt.quit();
            }
            step++;
        }
    }
}
''', {
                "PATH": str(root / "bin") + ":" + os.environ["PATH"],
                "PANGU_TEST_TMUX_LOG": str(root / "requests.jsonl"),
            })
            requests = [json.loads(line) for line in (root / "requests.jsonl").read_text().splitlines()]
            self.assertEqual(sorted(session for _, session in requests), ["first", "first", "last", "last", "missing", "missing"])

    def test_emoji_history_is_shared_queued_and_persistent(self):
        for clear in (False, True):
            with self.subTest(clear=clear), tempfile.TemporaryDirectory(prefix="pangu emoji's-") as directory:
                root = Path(directory)
                for name in ("config", "modules/components", "modules/services", "assets", "cache/pangu"):
                    (root / name).mkdir(parents=True)
                shutil.copy(SHELL / "config/Paths.qml", root / "config/Paths.qml")
                (root / "config/qmldir").write_text("singleton Paths 1.0 Paths.qml\n")
                shutil.copy(SHELL / "modules/services/EmojiService.qml", root / "modules/services/EmojiService.qml")
                (root / "modules/services/qmldir").write_text("singleton EmojiService 1.0 EmojiService.qml\n")
                shutil.copy(SHELL / "modules/components/JsonStore.qml", root / "modules/components/JsonStore.qml")
                (root / "modules/components/qmldir").write_text("JsonStore 1.0 JsonStore.qml\n")
                smile = {"emoji": "😀", "name": "grinning face", "slug": "grinning_face"}
                (root / "assets/emojis.json").write_text(json.dumps({"😀": smile, "👍": {"name": "thumbs up"}}))
                history = root / "cache/pangu/emojis.json"
                history.write_text(json.dumps([{**smile, "usage": 5, "lastUsed": 1}, None, {}]))
                expected = 1 if clear else 8
                scene = '''import QtQuick
import Quickshell
import "modules/services"
ShellRoot {
    property QtObject firstView: QtObject { readonly property var entries: EmojiService.recent }
    property QtObject secondView: QtObject { readonly property var entries: EmojiService.recent }
    property int step: 0
    Component.onCompleted: {
        EmojiService.remember({emoji: "😀", name: "grinning face"});
        EmojiService.remember({emoji: "😀", name: "grinning face"});
        %s
        EmojiService.remember({emoji: "👍🏽", name: "thumbs up (medium)"});
    }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            if (!EmojiService.emojis.length || !firstView.entries.length) return;
            if (step === 0) EmojiService.remember({emoji: "😀", name: "grinning face"});
            if (step === 3) {
                const smile = firstView.entries.find(entry => entry.emoji === "😀");
                const thumb = secondView.entries.find(entry => entry.emoji === "👍🏽");
                if (firstView.entries.length !== 2 || EmojiService.emojis.length !== 2
                    || !smile || smile.usage !== %d || !thumb || thumb.usage !== 1
                    || JSON.stringify(firstView.entries) !== JSON.stringify(secondView.entries)) {
                    console.log("CHECK_FAILED shared history"); Qt.quit(); return;
                }
                console.log("CHECK_PASSED"); Qt.quit();
            }
            step++;
        }
    }
}
''' % ("EmojiService.clearRecent();" if clear else "", expected)
                self.run_scene(root, scene)
                saved = json.loads(history.read_text())
                self.assertEqual(next(entry for entry in saved if entry["emoji"] == "😀")["usage"], expected)
                self.run_scene(root, '''import QtQuick
import Quickshell
import "modules/services"
ShellRoot {
    readonly property var entries: EmojiService.recent
    Timer {
        interval: 500; running: true
        onTriggered: {
            const smile = entries.find(entry => entry.emoji === "😀");
            console.log(entries.length === 2 && smile && smile.usage === %d
                ? "CHECK_PASSED" : "CHECK_FAILED persisted history");
            Qt.quit();
        }
    }
}
''' % expected)

    def test_ocr_autosaves_independently_of_shell_drafts(self):
        with tempfile.TemporaryDirectory(prefix="pangu-settings-") as directory:
            root = Path(directory)
            self.prepare_config(root)
            panel = (SHELL / "modules/widgets/dashboard/controls/ShellPanel.qml").read_text()
            ocr = re.search(r'Repeater\s*\{\s*model:\s*\[\s*\{label: "English".*?onToggled:.*?\n\s*\}\n\s*\}', panel, re.S)
            self.assertIsNotNone(ocr)
            (root / "ToggleRow.qml").write_text('''import QtQuick
Item { property string label; property bool checked; signal toggled(bool value) }
''')
            scene = '''import QtQuick
import Quickshell
import "config"
import "modules/globals"
ShellRoot {
    Item {
        id: controls
        %s
    }
    property int step: 0
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            if (!Config.initialLoadComplete) return;
            if (step === 0) {
                const rows = languageRows;
                if (rows.count !== 7) { console.log("CHECK_FAILED language count"); Qt.quit(); return; }
                rows.itemAt(2).toggled(true);
                if (GlobalStates.shellHasChanges) { console.log("CHECK_FAILED OCR draft"); Qt.quit(); return; }
                GlobalStates.markShellChanged();
                Config.notch.position = "bottom";
                rows.itemAt(0).toggled(false);
            } else if (step === 1) {
                GlobalStates.discardShellChanges();
                if (Config.notch.position !== "top" || Config.dock.position !== "bottom"
                    || !Config.system.ocr.lat || Config.system.ocr.eng || GlobalStates.shellHasChanges) {
                    console.log("CHECK_FAILED discard"); Qt.quit(); return;
                }
                Config.notch.position = "bottom";
                if (GlobalStates.shellHasChanges || Config.dock.position !== "left") {
                    console.log("CHECK_FAILED automatic placement draft"); Qt.quit(); return;
                }
            } else if (step === 4) {
                console.log("CHECK_PASSED"); Qt.quit();
            }
            step++;
        }
    }
}
''' % ocr.group().replace("Repeater {", "Repeater { id: languageRows", 1)
            self.run_scene(root, scene, {
                "HOME": str(root), "XDG_CONFIG_HOME": str(root / "settings"),
                "XDG_DATA_HOME": str(root / "data"), "PANGU_NIX_OVERRIDES": "",
            })
            persisted = json.loads((root / "settings/pangu/config/system.json").read_text())
            self.assertTrue(persisted["ocr"]["lat"])
            self.assertFalse(persisted["ocr"]["eng"])
            self.assertEqual(json.loads((root / "settings/pangu/config/dock.json").read_text())["position"], "left")

    def prepare_config(self, root):
        config = root / "config"
        config.mkdir()
        for name in ("Config", "ConfigFile", "Paths"):
            shutil.copy(SHELL / f"config/{name}.qml", config / f"{name}.qml")
        shutil.copy(SHELL / "config/SettingsData.js", config / "SettingsData.js")
        (config / "qmldir").write_text(
            "singleton Config 1.0 Config.qml\nConfigFile 1.0 ConfigFile.qml\nsingleton Paths 1.0 Paths.qml\n"
        )
        globals_dir = root / "modules/globals"
        globals_dir.mkdir(parents=True)
        source = (SHELL / "modules/globals/GlobalStates.qml").read_text()
        source = source.replace("import qs.modules.services\n", "").replace(
            "import qs.modules.widgets.dashboard.wallpapers\n", ""
        )
        (globals_dir / "GlobalStates.qml").write_text(source)
        (globals_dir / "qmldir").write_text(
            "singleton GlobalStates 1.0 GlobalStates.qml\n"
            "singleton WallpaperService 1.0 WallpaperService.qml\n"
            "singleton Visibilities 1.0 Visibilities.qml\n"
        )
        for name, body in (("WallpaperService", ""), ("Visibilities", "function getForActive() { return null; }")):
            (globals_dir / f"{name}.qml").write_text(f"pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}\n")

    def test_theme_drafts_and_presets_track_new_fields_and_preserve_objects(self):
        with tempfile.TemporaryDirectory(prefix="pangu-presets-") as directory:
            root = Path(directory)
            self.prepare_config(root)
            (root / "modules/globals/WallpaperService.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property string activeColorPreset: ""
    function setColorPreset(name) { activeColorPreset = name; }
}
''')
            config = root / "config/Config.qml"
            source = config.read_text().replace(
                "property real shadowBlur: 1", "property real shadowBlur: 1\n            property real futureSetting: 7"
            ).replace(
                'property string label: "Background"', 'property string label: "Background"\n                property real futureSetting: 8'
            )
            config.write_text(source)
            services = root / "modules/services"
            services.mkdir()
            shutil.copy(SHELL / "modules/services/LayoutPresets.qml", services / "LayoutPresets.qml")
            (services / "qmldir").write_text("singleton LayoutPresets 1.0 LayoutPresets.qml\n")
            theme = root / "modules/theme"
            theme.mkdir()
            (theme / "qmldir").write_text("singleton Icons 1.0 Icons.qml\n")
            (theme / "Icons.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { readonly property string cube: "cube" }\n')
            self.run_scene(root, '''import QtQuick
import Quickshell
import "config"
import "modules/globals"
import "modules/services"
ShellRoot {
    property int step: 0
    property var baseline
    property var expected
    property var backgroundObject
    property string presetId
    readonly property int presetCount: LayoutPresets.presets.length
    function check(condition, message) {
        if (!condition) { console.log("CHECK_FAILED", message); Qt.quit(); }
    }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            if (!Config.initialLoadComplete) return;
            if (step === 0) {
                baseline = JSON.stringify(Config.snapshot("theme"));
                backgroundObject = Config.theme.srBg;
                GlobalStates.markThemeChanged();
                Config.theme.futureSetting = 10;
                Config.theme.srBg.futureSetting = 11;
                Config.theme.srBg.gradient = [["primary", 0.1], ["secondary", 0.9]];
                Config.theme.srBg.border = ["primary", 3];
                check(GlobalStates.themeSnapshot.srBg.gradient[0][0] === "background", "snapshot alias");
            } else if (step === 1) {
                GlobalStates.discardThemeChanges();
                check(JSON.stringify(Config.snapshot("theme")) === baseline, "discard omitted a field");
                check(Config.theme.srBg === backgroundObject, "discard replaced the JSON object");
                GlobalStates.markThemeChanged();
                Config.theme.futureSetting = 10;
                Config.theme.srBg.futureSetting = 11;
                Config.theme.srBg.border = ["primary", 3];
                expected = JSON.stringify(Config.snapshot("theme"));
                presetId = LayoutPresets.saveCurrent("Complete theme", "test");
            } else if (step === 2) {
                Config.theme.futureSetting = 12;
                Config.theme.srBg.futureSetting = 13;
                Config.theme.srBg.border = ["secondary", 5];
                const preset = LayoutPresets.getPreset(presetId);
                preset.theme.unknownSetting = 99;
                preset.theme.srBg.unknownSetting = 99;
                LayoutPresets.apply(presetId);
                check(JSON.stringify(Config.snapshot("theme")) === expected, "preset omitted or aliased a field");
                check(Config.theme.srBg === backgroundObject, "preset replaced the JSON object");
                check(!GlobalStates.themeHasChanges && !Config.isPaused("theme"), "preset left a draft open");
            } else if (step === 3) {
                LayoutPresets.apply("pangu");
                check(Config.theme.roundness === 16 && Config.theme.futureSetting === 10, "partial preset reset omitted fields");
            } else if (step === 6) {
                console.log("CHECK_PASSED"); Qt.quit();
            }
            step++;
        }
    }
}
''', {
                "HOME": str(root), "XDG_CONFIG_HOME": str(root / "settings"),
                "XDG_DATA_HOME": str(root / "data"), "PANGU_NIX_OVERRIDES": "",
            })
            persisted = json.loads((root / "settings/pangu/config/theme.json").read_text())
            self.assertEqual(persisted["futureSetting"], 10)
            self.assertEqual(persisted["srBg"]["futureSetting"], 11)
            saved = json.loads((root / "settings/pangu/layouts.json").read_text())["presets"][0]
            self.assertEqual(saved["theme"]["srBg"]["border"], ["primary", 3])
            self.assertNotIn("adapterUpdated", saved["theme"])

    def test_pending_reload_preserves_applied_theme(self):
        with tempfile.TemporaryDirectory(prefix="pangu-apply-") as directory:
            root = Path(directory)
            self.prepare_config(root)
            self.run_scene(root, '''import QtQuick
import Quickshell
import "config"
import "modules/globals"
ShellRoot {
    property int step: 0
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            if (!Config.initialLoadComplete) return;
            if (step === 0) {
                GlobalStates.markThemeChanged();
                Config.theme.font = "Applied font";
                Config.files.theme.reloadPending = true;
                GlobalStates.applyThemeChanges();
            } else if (step === 5) {
                if (Config.theme.font !== "Applied font" || Config.isPaused("theme")) {
                    console.log("CHECK_FAILED applied settings lost"); Qt.quit(); return;
                }
                console.log("CHECK_PASSED"); Qt.quit();
            }
            step++;
        }
    }
}
''', {
                "HOME": str(root), "XDG_CONFIG_HOME": str(root / "settings"),
                "XDG_DATA_HOME": str(root / "data"), "PANGU_NIX_OVERRIDES": "",
            })
            self.assertEqual(json.loads((root / "settings/pangu/config/theme.json").read_text())["font"], "Applied font")

    def test_settings_snapshots_use_file_names_for_pinned_apps(self):
        with tempfile.TemporaryDirectory(prefix="pangu-pinned-settings-") as directory:
            root = Path(directory)
            self.prepare_config(root)
            self.run_scene(root, '''import QtQuick
import Quickshell
import "config"
ShellRoot {
    property int step: 0
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            if (!Config.initialLoadComplete) return;
            if (step === 0) {
                if (!Config.adapterKeys("pinnedapps").includes("apps")
                    || Config.snapshot("pinnedapps").apps[0] !== "kitty") {
                    console.log("CHECK_FAILED pinned apps alias"); Qt.quit(); return;
                }
                Config.restore("pinnedapps", {apps: ["firefox"]});
            } else if (step === 3) {
                console.log(Config.pinnedApps.apps[0] === "firefox" ? "CHECK_PASSED" : "CHECK_FAILED restore");
                Qt.quit();
            }
            step++;
        }
    }
}
''', {
                "HOME": str(root), "XDG_CONFIG_HOME": str(root / "settings"),
                "XDG_DATA_HOME": str(root / "data"), "PANGU_NIX_OVERRIDES": "",
            })
            self.assertEqual(json.loads((root / "data/pangu/pinnedapps.json").read_text())["apps"], ["firefox"])

    def test_unreadable_config_does_not_block_other_services(self):
        with tempfile.TemporaryDirectory(prefix="pangu-load-failure-") as directory:
            root = Path(directory)
            self.prepare_config(root)
            invalid = root / "settings/pangu/config/performance.json"
            invalid.mkdir(parents=True)
            self.run_scene(root, '''import QtQuick
import Quickshell
import "config"
ShellRoot {
    readonly property bool loaded: Config.initialLoadComplete
    Timer {
        interval: 800; running: true
        onTriggered: {
            console.log(loaded && Config.files.performance.ready ? "CHECK_PASSED" : "CHECK_FAILED load stalled");
            Qt.quit();
        }
    }
}
''', {
                "HOME": str(root), "XDG_CONFIG_HOME": str(root / "settings"),
                "XDG_DATA_HOME": str(root / "data"), "PANGU_NIX_OVERRIDES": "",
            })
            self.assertTrue(invalid.is_dir())

    def prepare_settings(self, root):
        for directory in ("config", "modules/components", "modules/theme", "modules/services"):
            (root / directory).mkdir(parents=True)
        (root / "config/qmldir").write_text("singleton Config 1.0 Config.qml\n")
        (root / "config/Config.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    readonly property string defaultFont: "Sans"
    readonly property int roundness: 16
    property QtObject theme: QtObject {
        property int animDuration: 120
        property string font: "Sans"
        property string monoFont: "Monospace"
        property int fontSize: 11
        property int monoFontSize: 11
    }
}
''')
        theme = root / "modules/theme"
        shutil.copy(SHELL / "modules/theme/Styling.qml", theme / "Styling.qml")
        (theme / "qmldir").write_text("singleton Styling 1.0 Styling.qml\nsingleton Colors 1.0 Colors.qml\n")
        (theme / "Colors.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    readonly property color overBackground: "white"
    readonly property color overSurfaceVariant: "gray"
    readonly property color error: "red"
}
''')
        services = root / "modules/services"
        (services / "qmldir").write_text("singleton GameModeService 1.0 GameModeService.qml\n")
        (services / "GameModeService.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property bool toggled: false }
''')

    def test_animation_timing_follows_game_mode_without_changing_settings(self):
        with tempfile.TemporaryDirectory(prefix="pangu-animation-") as directory:
            root = Path(directory)
            self.prepare_settings(root)
            self.run_scene(root, '''import QtQuick
import Quickshell
import "config"
import "modules/theme"
import "modules/services"
ShellRoot {
    readonly property int duration: Styling.animDuration
    property int step: 0
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            const expected = [120, 0, 0, 250][step];
            const setting = step < 2 ? 120 : 250;
            if (duration !== expected || Config.theme.animDuration !== setting) {
                console.log("CHECK_FAILED", duration, Config.theme.animDuration);
                Qt.quit();
                return;
            }
            if (step === 0) GameModeService.toggled = true;
            if (step === 1) Config.theme.animDuration = 250;
            if (step === 2) GameModeService.toggled = false;
            if (step++ === 3) {
                console.log("CHECK_PASSED");
                Qt.quit();
            }
        }
    }
}
''')

    def test_settings_inputs_reject_invalid_values_and_preserve_precision(self):
        with tempfile.TemporaryDirectory(prefix="pangu-inputs-") as directory:
            root = Path(directory)
            self.prepare_settings(root)
            components = root / "modules/components"
            for component in ("SettingsNumberInputRow", "SettingsTextInputRow"):
                shutil.copy(SHELL / f"modules/components/{component}.qml", components / f"{component}.qml")
            (components / "qmldir").write_text(
                "SettingsNumberInputRow 1.0 SettingsNumberInputRow.qml\n"
                "SettingsTextInputRow 1.0 SettingsTextInputRow.qml\nStyledRect 1.0 StyledRect.qml\n"
            )
            (components / "StyledRect.qml").write_text('''import QtQuick
Rectangle { property string variant: "common"; property color item: "white" }
''')
            self.run_scene(root, '''import QtQuick
import Quickshell
import "modules/components"
Item {
    property int prefixEdits: 0
    function input(item) {
        if (item.acceptableInput !== undefined) return item;
        for (const child of item.children || []) {
            const found = input(child);
            if (found) return found;
        }
        return null;
    }
    function check(condition) {
        if (!condition) console.log("CHECK_FAILED");
    }
    SettingsNumberInputRow {
        id: integerRow
        width: 320; value: 24; minValue: 1; maxValue: 40
        onValueEdited: newValue => value = newValue
    }
    SettingsNumberInputRow {
        id: decimalRow
        width: 320; value: 0.15; decimals: 2; maxValue: 1
        onValueEdited: newValue => value = newValue
    }
    SettingsTextInputRow {
        id: prefixRow
        width: 320; value: ";"; trimValue: true; allowEmpty: false; maximumLength: 4
        onValueEdited: newValue => { prefixEdits++; value = newValue; }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            const integer = input(integerRow), decimal = input(decimalRow), prefix = input(prefixRow);
            check(integer.text === "24" && decimal.text === "0.15");
            for (const invalid of ["999", "2.5", "", "-"]) {
                integer.text = invalid;
                integer.editingFinished();
                check(integerRow.value === 24 && integer.text === "24");
            }
            integer.text = "32";
            integer.editingFinished();
            check(integerRow.value === 32);
            decimal.text = "0.25";
            decimal.editingFinished();
            check(decimalRow.value === 0.25);
            decimal.text = "1.25";
            decimal.editingFinished();
            check(decimalRow.value === 0.25 && decimal.text === "0.25");
            prefix.text = "   ";
            prefix.editingFinished();
            check(prefixEdits === 0 && prefixRow.value === ";");
            prefix.text = " xy ";
            prefix.editingFinished();
            check(prefixEdits === 1 && prefixRow.value === "xy");
            console.log("CHECK_PASSED");
            Qt.quit();
        }
    }
}
''')

    def run_scene(self, root, scene, extra_env=None):
        (root / "runtime").mkdir(mode=0o700, exist_ok=True)
        (root / "shell.qml").write_text(scene)
        env = dict(os.environ, XDG_RUNTIME_DIR=str(root / "runtime"), XDG_CACHE_HOME=str(root / "cache"),
                   QT_QPA_PLATFORM="offscreen", QML_DISABLE_DISK_CACHE="1")
        env.pop("WAYLAND_DISPLAY", None)
        env.update(extra_env or {})
        try:
            result = subprocess.run(["qs", "-p", str(root / "shell.qml")], env=env,
                                    capture_output=True, text=True, timeout=10)
        except subprocess.TimeoutExpired as error:
            self.fail((error.stdout or b"").decode() + (error.stderr or b"").decode())
        log = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, log)
        for error in ("TypeError", "ReferenceError", "Binding loop", "CHECK_FAILED", "Cannot assign", "Unable to assign"):
            self.assertNotIn(error, log)
        self.assertIn("CHECK_PASSED", log)

    def test_compositor_observes_delayed_replies_and_refreshes_during_event_streams(self):
        with tempfile.TemporaryDirectory(prefix="pangu-compositor-") as directory:
            root = Path(directory)
            services = root / "modules/services"
            backend = services / "backend"
            backend.mkdir(parents=True)
            source = (SHELL / "modules/services/Compositor.qml").read_text()
            (services / "Compositor.qml").write_text(source.replace("import Quickshell.Hyprland", 'import "backend"'))
            (services / "qmldir").write_text("singleton Compositor 1.0 Compositor.qml\n")
            (backend / "qmldir").write_text("singleton Hyprland 1.0 Hyprland.qml\n")
            (backend / "Hyprland.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    id: root
    property int refreshCount: 0
    property QtObject focusedMonitor: QtObject {
        property int id: 0
        property string name: "DP-1"
        property int width: 3840
        property int height: 1440
        property real scale: 2
        property int x: 0
        property int y: 0
        property QtObject activeWorkspace: root.focusedWorkspace
        property var lastIpcObject: ({transform: 0})
    }
    property QtObject focusedWorkspace: QtObject {
        property int id: 1
        property string name: "1"
        property QtObject monitor: root.focusedMonitor
        property var lastIpcObject: ({})
    }
    property QtObject activeToplevel: QtObject {
        property string address: "0xabc"
        property string title: "Initial"
        property var lastIpcObject: ({address: "0xabc", title: "Initial", workspace: {id: 1}, fullscreen: 0})
    }
    property QtObject monitors: QtObject { property var values: [root.focusedMonitor] }
    property QtObject workspaces: QtObject { property var values: [root.focusedWorkspace] }
    property QtObject toplevels: QtObject { property var values: [root.activeToplevel] }
    signal rawEvent(var event)
    function refreshToplevels() { refreshCount++; }
    function refreshWorkspaces() {}
    function refreshMonitors() {}
}
''')
            self.run_scene(root, '''import QtQuick
import Quickshell
import "modules/services"
import "modules/services/backend"
ShellRoot {
    property int step: 0
    property int settledRefreshCount: 0
    readonly property var client: Compositor.focusedClient
    function check(condition) { if (!condition) console.log("CHECK_FAILED", step); }
    Timer {
        id: events
        interval: 5; repeat: true; running: true
        onTriggered: Hyprland.rawEvent(step < 2 ? {name: "activewindow", data: ""}
            : {name: "custom", data: "centergap,DP-1,100,500,1"})
    }
    Timer {
        interval: 160; repeat: true; running: true
        onTriggered: {
            if (step === 0) {
                check(client && client.title === "Initial");
                Hyprland.activeToplevel.lastIpcObject = {address: "0xabc", title: "Late reply", workspace: {id: 1}, fullscreen: 0, fullscreenClient: 2};
                Hyprland.focusedMonitor.lastIpcObject = {transform: 5};
            }
            if (step === 1) {
                check(client.title === "Late reply" && !Compositor.hasFullscreenWindow("DP-1"));
                check(Compositor.focusedMonitor.logicalWidth === 720 && Compositor.focusedMonitor.logicalHeight === 1920);
                check(Hyprland.refreshCount > 2);
            }
            if (step === 2) settledRefreshCount = Hyprland.refreshCount;
            if (step++ === 3) {
                check(Hyprland.refreshCount === settledRefreshCount);
                check(Compositor.gapFor("DP-1").width === 500);
                console.log("CHECK_PASSED");
                Qt.quit();
            }
        }
    }
}
''')

    def test_boot_lock_marker_survives_service_runtime_cleanup(self):
        with tempfile.TemporaryDirectory(prefix="pangu-boot-lock-") as directory:
            root = Path(directory)
            for folder in ("config", "modules/services", "modules/globals"):
                (root / folder).mkdir(parents=True)
            (root / "config/qmldir").write_text("singleton Config 1.0 Config.qml\n")
            (root / "config/Config.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool initialLoadComplete: true
    property QtObject lockscreen: QtObject { property bool lockOnBoot: true }
}
''')
            (root / "modules/globals/qmldir").write_text("singleton GlobalStates 1.0 GlobalStates.qml\n")
            (root / "modules/globals/GlobalStates.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property bool lockscreenVisible: false }
''')
            (root / "modules/services/qmldir").write_text("singleton LockscreenService 1.0 LockscreenService.qml\n")
            shutil.copy(SHELL / "modules/services/LockscreenService.qml", root / "modules/services/LockscreenService.qml")
            for expected in (True, False, True):
                if expected and (root / "runtime/pangu-session-started").exists():
                    (root / "runtime/pangu-session-started").rmdir()
                (root / "runtime/pangu").mkdir(parents=True, exist_ok=True)
                scene = '''import QtQuick
import Quickshell
import "modules/services"
import "modules/globals"
ShellRoot {
    Component.onCompleted: void LockscreenService.ipc
    Timer {
        interval: 200; running: true
        onTriggered: {
            console.log(GlobalStates.lockscreenVisible === EXPECTED ? "CHECK_PASSED" : "CHECK_FAILED");
            Qt.quit();
        }
    }
}
'''.replace("EXPECTED", "true" if expected else "false")
                self.run_scene(root, scene)
                shutil.rmtree(root / "runtime/pangu")

    def test_overview_delegate_owner_and_geometry(self):
        with tempfile.TemporaryDirectory(prefix="pangu-overview-") as directory:
            root = Path(directory)
            source = (SHELL / "modules/widgets/overview/Overview.qml").read_text()
            start = source.index("            Repeater {\n                model: windowSpace.filteredWindowData")
            end = source.index("            Rectangle {\n                id: focusedWorkspaceIndicator", start)
            delegate = source[start:end].replace("Repeater {", "Repeater {\n                id: testedWindows", 1)
            window = (SHELL / "modules/widgets/overview/OverviewWindow.qml").read_text()
            declarations = [line for line in window.splitlines()
                            if re.match(r"    (required )?property (var|Item|real|int|bool|string) ", line)
                            and "atInitPosition" not in line]
            signals = [line for line in window.splitlines() if line.startswith("    signal ")]
            (root / "OverviewWindow.qml").write_text("import QtQuick\nItem {\n" + "\n".join(declarations + signals) + "\n}\n")
            self.run_scene(root, '''import QtQuick
import Quickshell
Item {
    id: overviewRoot
    width: 1000; height: 500
    property real workspaceImplicitWidth: 300
    property real workspaceImplicitHeight: 200
    property int workspacePadding: 8
    property int workspaceSpacing: 12
    property int columns: 3
    property int workspacesShown: 6
    property var monitorData: ({x: 0, y: 0})
    property string barPosition: "top"
    property int barReserved: 40
    function isWindowMatched(address) { return true; }
    function isWindowSelected(address) { return false; }
    Item {
        id: windowSpace
        property var filteredWindowData: [
            {windowData: {workspace: {id: 1}, address: "first"}, toplevel: null},
            {windowData: {workspace: {id: 2}, address: "second"}, toplevel: null}
        ]
    }
''' + delegate + '''
    Timer {
        interval: 200; running: true
        onTriggered: {
            const first = testedWindows.itemAt(0);
            const second = testedWindows.itemAt(1);
            console.log(first && second && first.overviewItem === overviewRoot &&
                first.availableWorkspaceWidth === 300 && second.xOffset === 324
                ? "CHECK_PASSED" : "CHECK_FAILED");
            Qt.quit();
        }
    }
}
''')

    def test_list_highlights_follow_delegate_geometry_and_handle_empty_models(self):
        for tab in ("clipboard/ClipboardTab", "notes/NotesTab", "tmux/TmuxTab", "emoji/EmojiTab"):
            with self.subTest(tab=tab), tempfile.TemporaryDirectory(prefix="pangu-list-") as directory:
                root = Path(directory)
                self.prepare_settings(root)
                source = (SHELL / f"modules/widgets/dashboard/{tab}.qml").read_text()
                start = source.index("highlight: ResultsHighlight {")
                end = source.index("}", start) + 1
                highlight = source[start:end].replace("emojiList", "resultsList")
                components = root / "modules/components"
                shutil.copy(SHELL / "modules/components/ResultsHighlight.qml", components / "ResultsHighlight.qml")
                (components / "qmldir").write_text("ResultsHighlight 1.0 ResultsHighlight.qml\nStyledRect 1.0 StyledRect.qml\n")
                (components / "StyledRect.qml").write_text('import QtQuick\nRectangle { property string variant }\n')
                self.run_scene(root, '''import QtQuick
import Quickshell
import "config"
import "modules/theme"
import "modules/components"
Item {
    id: root
    width: 320; height: 200
    property int selectedIndex: resultsList.currentIndex
    property bool deleteMode: false
    property bool aliasMode: false
    property bool renameMode: false
    property bool isAtRecent: false
    property real recentX: 0
    property real recentContentX: 0
    property int expandedItemIndex: 2
    property int step: 0
    Component.onCompleted: Config.theme.animDuration = 0
    ListView {
        id: resultsList
        width: 320; height: 100
        model: [48, 48, 160, 48]
        currentIndex: 2
        delegate: Item { required property int modelData; width: 320; height: modelData }
''' + highlight + '''
    }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (step === 0) resultsList.positionViewAtIndex(2, ListView.Contain);
            if (step === 1) {
                const item = resultsList.currentItem, highlight = resultsList.highlightItem;
                if (!item || !highlight || highlight.height !== 160 || highlight.y !== item.y)
                    console.log("CHECK_FAILED");
                resultsList.model = [];
                resultsList.currentIndex = -1;
            }
            if (step++ === 2) {
                if (resultsList.highlightItem && resultsList.highlightItem.visible)
                    console.log("CHECK_FAILED stale highlight");
                console.log("CHECK_PASSED");
                Qt.quit();
            }
        }
    }
}
''')

    def test_visibility_lookup_has_no_registration_side_effect(self):
        with tempfile.TemporaryDirectory(prefix="pangu-visibility-") as directory:
            root = Path(directory)
            services = root / "modules/services"
            services.mkdir(parents=True)
            shutil.copy(SHELL / "modules/services/Visibilities.qml", services / "Visibilities.qml")
            (services / "qmldir").write_text("singleton Visibilities 1.0 Visibilities.qml\nsingleton Compositor 1.0 Compositor.qml\n")
            (services / "Compositor.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property var focusedMonitor: ({name: "absent"}) }
''')
            self.run_scene(root, '''import QtQuick
import Quickshell
import "modules/services"
ShellRoot {
    readonly property var absent: Visibilities.getForScreen("absent")
    Timer {
        interval: 200; running: true
        onTriggered: {
            const registered = Object.keys(Visibilities.screens).length;
            console.log(absent === null && registered === Quickshell.screens.length
                ? "CHECK_PASSED" : "CHECK_FAILED");
            Qt.quit();
        }
    }
}
''')
