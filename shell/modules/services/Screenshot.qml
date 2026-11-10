pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals
import qs.modules.theme
import qs.config

QtObject {
    id: root

    signal monitorScreenshotReady(string monitorName, string path)
    signal errorOccurred(string message)
    signal windowListReady(var windows)
    signal monitorsListReady(var monitors)
    signal lensImageReady(string path)
    signal imageSaved(string path)

    property string tempPathBase: Paths.runtimePath("freeze")
    property string lensPath: Paths.runtimePath("lens.png")

    property string captureMode: "normal"
    property string processingMode: "normal"
    property string savedScreenName: ""
    property string toolImagePath: ""

    function startCapture(mode = "normal") {
        if (GlobalStates.screenshotToolVisible || _freezing || cropProcess.running || toolProcess.running
                || cleanupProcess.running || verifyImageProcess.running || lensProcess.running)
            return;
        initialize();
        captureMode = ["normal", "lens", "ocr", "qr"].includes(mode) ? mode : "normal";
        Visibilities.setActiveModule("");
        // Launcher actions have already begun closing the notch when they arrive here.
        captureTimer.interval = Math.max(1, Styling.animDuration) + 50;
        captureTimer.restart();
    }

    property Timer captureTimer: Timer {
        id: captureTimer
        onTriggered: GlobalStates.screenshotToolVisible = true
    }

    function cancelCapture() {
        captureTimer.stop();
        captureMode = "normal";
    }

    function cleanFrozenFrames() {
        if (typeof freezeCleanupProcess === "undefined" || !freezeCleanupProcess || root.monitors.length === 0)
            return;
        const files = root.monitors.map(m => root.tempPathBase + "_" + m.name + ".png");
        freezeCleanupProcess.command = ["rm", "-f", "--"].concat(files);
        freezeCleanupProcess.running = true;
    }

    property Connections visibilityCleanup: Connections {
        target: GlobalStates
        function onScreenshotToolVisibleChanged() {
            if (!GlobalStates.screenshotToolVisible && !cropProcess.running && !root._freezing)
                root.cleanFrozenFrames();
        }
    }

    property string screenshotsDir: ""
    property string finalPath: ""

    property var monitors: []

    property int selectionX: 0
    property int selectionY: 0
    property int selectionW: 0
    property int selectionH: 0

    property real monitorScale: 1.0

    property bool _initialized: false

    function initialize() {
        if (_initialized) return;
        _initialized = true;
        xdgProcess.running = true;
    }

    property Process xdgProcess: Process {
        id: xdgProcess
        command: ["xdg-user-dir", "PICTURES"]
        stdout: StdioCollector {}
        running: false
        onExited: exitCode => {
            const dir = exitCode === 0 ? xdgProcess.stdout.text.trim() : "";
            root.screenshotsDir = (dir || Paths.picturesDir) + "/Screenshots";
            ensureDirProcess.running = true;
        }
    }

    property Process ensureDirProcess: Process {
        id: ensureDirProcess
        command: ["mkdir", "-p", "--", root.screenshotsDir]
        onExited: code => { if (code !== 0) root.errorOccurred("Cannot create screenshot directory"); }
    }

    property Process freezeProcess: Process {
        id: freezeProcess
        command: []
        onExited: exitCode => {
            root._freezing = false;
            if (exitCode === 0) {
                for (let i = 0; i < root.monitors.length; i++) {
                    const m = root.monitors[i];
                    const path = root.tempPathBase + "_" + m.name + ".png";
                    root.monitorScreenshotReady(m.name, path);
                }
            } else {
                root.errorOccurred("Failed to capture screen (grim)");
            }
        }
    }

    property Process freezeCleanupProcess: Process {
        id: freezeCleanupProcess
        running: false
    }

    property Process cropProcess: Process {
        id: cropProcess
        onExited: exitCode => root.finishCrop(exitCode)
    }

    function finishCrop(exitCode) {
        const mode = processingMode;
        processingMode = "normal";
        if (typeof root.cleanFrozenFrames === "function")
            root.cleanFrozenFrames();
        if (exitCode !== 0) {
            root.errorOccurred("Failed to save image");
            return;
        }
        if (mode === "lens") {
            root.runLensScript();
        } else if (mode === "ocr" || mode === "qr") {
            toolImagePath = finalPath;
            toolProcess.command = mode === "ocr"
                ? ["bash", Paths.script("ocr.sh"), LauncherActions.ocrLangString(), toolImagePath]
                : ["bash", Paths.script("qr_scan.sh"), toolImagePath];
            toolProcess.running = true;
        } else {
            copyProcess.running = true;
            root.imageSaved(finalPath);
        }
    }

    property Process toolProcess: Process {
        id: toolProcess
        onExited: cleanupProcess.running = true
    }

    property Process cleanupProcess: Process {
        id: cleanupProcess
        command: ["rm", "-f", "--", root.toolImagePath]
    }

    property Process copyProcess: Process {
        id: copyProcess
        command: ["bash", "-c", 'wl-copy --type image/png < "$1"', "pangu-copy", root.finalPath]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) console.warn("Screenshot Copy Error:", text);
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("Failed to copy to clipboard (exit " + exitCode + ")");
            }
        }
    }

    property Process lensProcess: Process {
        id: lensProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode === 0) {
                cleanupProcess.command = ["rm", "-f", "--", root.lensPath];
                cleanupProcess.running = true;
            } else {
                root.errorOccurred("Failed to open Google Lens: " + lensProcess.stderr.text);
            }
        }
    }

    property bool _freezing: false

    function freezeScreen() {
        if (_freezing) return;
        _freezing = true;

        const qsScreens = Quickshell.screens;
        const mappedMonitors = [];
        for (let i = 0; i < qsScreens.length; i++) {
            const s = qsScreens[i];
            const scale = s.devicePixelRatio || 1; // ShellScreen has no `scale`; reading it yields NaN geometry
            mappedMonitors.push({
                id: i,
                name: s.name,
                x: s.x,
                y: s.y,
                logicalWidth: s.width,
                logicalHeight: s.height,
                width: s.width * scale,
                height: s.height * scale,
                scale: scale
            });
        }
        root.monitors = mappedMonitors;

        root.executeFreezeBatch();
        Qt.callLater(root.fetchWindows);
    }

    function fetchWindows() {
        const monitors = Compositor.monitors.values;
        root.monitorsListReady(monitors);

        const visible = [];
        for (const m of monitors) {
            if (m.activeWorkspace)
                visible.push(m.activeWorkspace.id);
            if (m.activeSpecialWorkspace)
                visible.push(m.activeSpecialWorkspace.id);
        }
        root.windowListReady(Compositor.clients.values
            .filter(c => c.pinned || (c.workspace && visible.includes(c.workspace.id)))
            .map(c => ({
                id: c.address,
                app_id: c.class,
                title: c.title,
                is_floating: c.floating,
                is_focused: c.is_focused,
                is_fullscreen: c.fullscreen,
                is_hidden: c.hidden,
                workspace_id: c.workspace?.id ?? 0,
                pinned: c.pinned,
                workspace: c.workspace,
                at: c.at,
                size: c.size
            })));
    }

    function executeFreezeBatch() {
        if (root.monitors.length === 0) {
            console.warn("Screenshot: No monitors found to freeze");
            _freezing = false;
            return;
        }

        const captures = [];
        for (const monitor of root.monitors)
            captures.push(monitor.name, root.tempPathBase + "_" + monitor.name + ".png");
        freezeProcess.command = ["bash", "-c",
            'mkdir -p -- "$1" || exit; shift; pids=(); status=0; '
            + 'while (( $# )); do grim -o "$1" "$2" & pids+=("$!"); shift 2; done; '
            + 'for pid in "${pids[@]}"; do wait "$pid" || status=1; done; exit "$status"',
            "pangu-freeze", Paths.runtimeDir].concat(captures);
        freezeProcess.running = true;
    }

    function getTimestamp() {
        const d = new Date();
        const pad = n => n < 10 ? "0" + n : n;
        return d.getFullYear() + "-"
            + pad(d.getMonth() + 1) + "-"
            + pad(d.getDate()) + "-"
            + pad(d.getHours()) + "-"
            + pad(d.getMinutes()) + "-"
            + pad(d.getSeconds()) + "-" + d.getMilliseconds();
    }

    function prepareOutput() {
        processingMode = captureMode;
        if (processingMode === "lens") {
            root.finalPath = root.lensPath;
        } else if (processingMode === "ocr" || processingMode === "qr") {
            root.finalPath = Paths.runtimePath(processingMode + "_" + getTimestamp() + ".png");
        } else {
            if (root.screenshotsDir === "") {
                root.screenshotsDir = Paths.picturesDir + "/Screenshots";
            }
            root.finalPath = root.screenshotsDir + "/Screenshot_" + getTimestamp() + ".png";
        }
    }

    function saveCapture(command) {
        prepareOutput();
        // Directory discovery can finish after the user selects a region.
        cropProcess.command = ["bash", "-c", 'mkdir -p -- "$1" && shift && exec "$@"', "pangu-capture",
            finalPath.slice(0, finalPath.lastIndexOf("/"))].concat(command, [finalPath]);
        cropProcess.running = true;
    }

    function processRegion(x, y, w, h) {
        if (w <= 0 || h <= 0 || cropProcess.running)
            return;
        let m = null;
        if (root.monitors.length > 0) {
            m = root.monitors.find(mon => {
                const logicalW = mon.logicalWidth ?? (mon.width / mon.scale);
                const logicalH = mon.logicalHeight ?? (mon.height / mon.scale);
                return x >= mon.x && x < (mon.x + logicalW) && y >= mon.y && y < (mon.y + logicalH);
            });
        }

        if (!m) {
            console.warn("Screenshot: Could not find monitor for region " + x + "," + y);
            root.errorOccurred("Could not find monitor for the selected region");
            return;
        }
        savedScreenName = m.name;

        const scale = m.scale || 1;
        const logicalW = m.logicalWidth ?? (m.width / scale);
        const logicalH = m.logicalHeight ?? (m.height / scale);
        const maxPhysW = Math.round(logicalW * scale);
        const maxPhysH = Math.round(logicalH * scale);

        const localX = Math.max(0, x - m.x);
        const localY = Math.max(0, y - m.y);

        const physX = Math.min(Math.max(0, maxPhysW - 1), Math.round(localX * scale));
        const physY = Math.min(Math.max(0, maxPhysH - 1), Math.round(localY * scale));
        const physW = Math.max(1, Math.min(maxPhysW - physX, Math.round(w * scale)));
        const physH = Math.max(1, Math.min(maxPhysH - physY, Math.round(h * scale)));

        const srcPath = root.tempPathBase + "_" + m.name + ".png";
        const geom = `${physW}x${physH}+${physX}+${physY}`;
        saveCapture(["magick", srcPath, "-crop", geom, "+repage"]);
    }

    function processMonitorScreen(monitorName) {
        if (cropProcess.running || !root.monitors.some(m => m.name === monitorName))
            return;
        savedScreenName = monitorName;
        const srcPath = root.tempPathBase + "_" + monitorName + ".png";
        saveCapture(["cp", "--", srcPath]);
    }

    function runLensScript() {
        verifyImageProcess.command = ["test", "-f", root.lensPath];
        verifyImageProcess.running = true;
    }

    property Process verifyImageProcess: Process {
        id: verifyImageProcess
        onExited: exitCode => {
            if (exitCode === 0) {
                lensProcess.command = ["bash", Paths.script("google_lens.sh"), root.lensPath];
                lensProcess.running = true;
            } else {
                root.errorOccurred("Image file not ready for Google Lens");
            }
        }
    }
}
