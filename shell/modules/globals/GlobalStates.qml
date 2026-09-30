pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services
import qs.config
import qs.modules.widgets.dashboard.wallpapers

Singleton {
    id: root

    readonly property var wallpaperManager: WallpaperService
    property string avatarCacheBuster: ""

    property bool hasAvatar: false

    Process {
        id: avatarProbe
        running: true
        command: ["test", "-f", Paths.avatar]
        onExited: exitCode => {
            root.hasAvatar = exitCode === 0;
        }
    }

    function pickUserAvatar() {
        filePickerProcess.running = true;
    }

    Process {
        id: filePickerProcess
        running: false
        command: ["zenity", "--file-selection", "--title=Select User Icon", "--file-filter=Images | *.png *.jpg *.jpeg *.svg *.webp"]

        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path) {
                    console.log("Selected icon:", path);
                    copyIconProcess.command = ["cp", path, Paths.avatar];
                    copyIconProcess.running = true;
                }
            }
        }
    }

    Process {
        id: copyIconProcess
        running: false
        command: []

        onExited: exitCode => {
            if (exitCode === 0) {
                console.log("Icon updated successfully");
                root.hasAvatar = true;
                avatarCacheBuster = Date.now();
            } else {
                console.warn("Failed to update icon");
            }
        }
    }

    property string launcherSearchText: ""
    property int launcherSelectedIndex: -1
    property int launcherCurrentTab: 0

    function clearLauncherState() {
        launcherSearchText = "";
        launcherSelectedIndex = -1;
    }

    property int dashboardCurrentTab: 0
    
    property int widgetsTabCurrentIndex: 0

    property int wallpaperSelectedIndex: -1

    function getActiveLauncher() {
        let active = Visibilities.getForActive();
        return active ? active.launcher : false;
    }

    function getActiveDashboard() {
        let active = Visibilities.getForActive();
        return active ? active.dashboard : false;
    }

    function getActiveOverview() {
        let active = Visibilities.getForActive();
        return active ? active.overview : false;
    }

    readonly property bool overviewOpen: getActiveOverview()
    readonly property bool launcherOpen: getActiveLauncher()
    readonly property bool dashboardOpen: getActiveDashboard()

    property bool lockscreenVisible: false

    property bool osdVisible: false
    property string osdIndicator: "volume" // volume, mic, brightness

    property bool screenshotToolVisible: false
    property string screenshotCaptureMode: "region" // region, window, screen

    property bool screenRecordToolVisible: false
    property bool screenRecordReplayMode: false

    property bool mirrorWindowVisible: false

    property bool cheatsheetVisible: false
    property bool macrosWindowVisible: false
    property int macrosTargetWorkspaceId: 0
    property string macrosTargetScreenName: ""

    property bool mousePickActive: false
    property bool mousePickValid: false
    property int mousePickX: 0
    property int mousePickY: 0
    property int mousePickSeq: 0

    function beginMousePick() {
        mousePickValid = false;
        mousePickActive = true;
    }

    function finishMousePick(x, y) {
        mousePickX = x;
        mousePickY = y;
        mousePickValid = true;
        mousePickSeq++;
        mousePickActive = false;
    }

    function cancelMousePick() {
        mousePickValid = false;
        mousePickSeq++;
        mousePickActive = false;
    }

    property bool settingsWindowVisible: false
    property int settingsTargetWorkspaceId: 0
    property string settingsTargetScreenName: ""

    property bool themeHasChanges: false
    property var themeSnapshot: null

    function markThemeChanged() {
        if (!themeHasChanges) {
            themeSnapshot = Config.snapshot("theme");
            Config.beginEdit("theme", ["theme"]);
        }
        themeHasChanges = true;
    }

    function applyThemeChanges() {
        if (themeHasChanges) {
            Config.save("theme");
            themeHasChanges = false;
            themeSnapshot = null;
            Config.endEdit("theme");
        }
    }

    function discardThemeChanges() {
        if (themeHasChanges && themeSnapshot) {
            Config.restore("theme", themeSnapshot);
            themeHasChanges = false;
            themeSnapshot = null;
            Config.endEdit("theme");
        }
    }

    property bool shellHasChanges: false
    property var shellSnapshot: null

    readonly property var _shellSections: ["bar", "notch", "workspaces", "overview", "dashboard", "launcher", "dock", "lockscreen", "osd"]

    function createShellSnapshot() {
        const snapshot = {};
        for (const section of _shellSections)
            snapshot[section] = Config.snapshot(section);
        return snapshot;
    }

    function restoreShellSnapshot(snapshot) {
        for (const section of _shellSections)
            Config.restore(section, snapshot[section]);
    }

    function markShellChanged() {
        if (!shellHasChanges) {
            shellSnapshot = createShellSnapshot();
            Config.beginEdit("shell", _shellSections);
        }
        shellHasChanges = true;
    }

    function applyShellChanges() {
        if (shellHasChanges) {
            for (const name of _shellSections)
                Config.save(name);

            shellHasChanges = false;
            shellSnapshot = null;
            Config.endEdit("shell");
        }
    }

    function discardShellChanges() {
        if (shellHasChanges && shellSnapshot) {
            restoreShellSnapshot(shellSnapshot);
            shellHasChanges = false;
            shellSnapshot = null;
            Config.endEdit("shell");
        }
    }

    property bool compositorHasChanges: false
    property var compositorSnapshot: null

    function markCompositorChanged() {
        if (!compositorHasChanges) {
            compositorSnapshot = Config.snapshot("compositor");
            Config.beginEdit("compositor", ["compositor"]);
        }
        compositorHasChanges = true;
    }

    function applyCompositorChanges() {
        if (compositorHasChanges) {
            Config.save("compositor");
            compositorHasChanges = false;
            compositorSnapshot = null;
            Config.endEdit("compositor");
        }
    }

    function discardCompositorChanges() {
        if (compositorHasChanges && compositorSnapshot) {
            Config.restore("compositor", compositorSnapshot);
            compositorHasChanges = false;
            compositorSnapshot = null;
            Config.endEdit("compositor");
        }
    }

    function resetChangeTracking() {
        themeHasChanges = false;
        themeSnapshot = null;
        shellHasChanges = false;
        shellSnapshot = null;
        compositorHasChanges = false;
        compositorSnapshot = null;
        for (const group of ["theme", "shell", "compositor"]) Config.endEdit(group);
    }

    Connections {
        target: Config.notch
        function onPositionChanged() {
            if (!Config.initialLoadComplete)
                return;
            if (Config.notch.position === "bottom" && Config.dock.position === "bottom") {
                Config.dock.position = Config.bar.position === "left" ? "right" : "left";
            } else if (Config.notch.position === "top" && (Config.dock.position === "left" || Config.dock.position === "right")) {
                Config.dock.position = "bottom";
            }
        }
    }

}
