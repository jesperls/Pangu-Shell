pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals
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
                for (var i = 0; i < root.monitors.length; i++) {
                    var m = root.monitors[i];
                    var path = root.tempPathBase + "_" + m.name + ".png";
                    root.monitorScreenshotReady(m.name, path);
                }
            } else {
                root.errorOccurred("Failed to capture screen (grim)")
            }
        }
    }
    
    property Process cropProcess: Process {
        id: cropProcess
        onExited: exitCode => {
            if (exitCode === 0) {
                if (root.captureMode === "lens") {
                    root.runLensScript()
                    root.captureMode = "normal" 
                } else {
                    copyProcess.running = true
                    root.imageSaved(root.finalPath)
                }
            } else {
                root.errorOccurred("Failed to save image")
            }
        }
    }

    property Process copyProcess: Process {
        id: copyProcess
        command: ["bash", "-c", 'wl-copy --type image/png < "$1"', "pangu-copy", root.finalPath]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) console.warn("Screenshot Copy Error: " + text)
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("Failed to copy to clipboard (Exit code: " + exitCode + ")")
            }
        }
    }

    property Process lensProcess: Process {
        id: lensProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode === 0) {
                console.log("Screenshot: Google Lens script executed successfully")
            } else {
                root.errorOccurred("Failed to open Google Lens: " + lensProcess.stderr.text)
            }
        }
    }

    property bool _freezing: false

    function freezeScreen() {
        if (_freezing) return;
        _freezing = true;

        var qsScreens = Quickshell.screens;
        var mappedMonitors = [];
        for (var i = 0; i < qsScreens.length; i++) {
             var s = qsScreens[i];
             var scale = s.devicePixelRatio || 1; // ShellScreen has no `scale`; reading it yields NaN geometry
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

        const visible = monitors.map(m => m.activeWorkspace ? m.activeWorkspace.id : -1);
        root.windowListReady(Compositor.clients.values
            .filter(c => c.pinned || visible.includes(c.workspace.id))
            .map(c => ({
                id: c.address,
                app_id: c.class,
                title: c.title,
                is_floating: c.floating,
                is_focused: c.is_focused,
                is_fullscreen: c.fullscreen,
                is_hidden: c.hidden,
                workspace_id: c.workspace.id,
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
        
        const captures = root.monitors.flatMap(m => [m.name, root.tempPathBase + "_" + m.name + ".png"]);
        freezeProcess.command = ["bash", "-c",
            'mkdir -p -- "$1" || exit; shift; pids=(); status=0; '
            + 'while (( $# )); do grim -o "$1" "$2" & pids+=("$!"); shift 2; done; '
            + 'for pid in "${pids[@]}"; do wait "$pid" || status=1; done; exit "$status"',
            "pangu-freeze", Paths.runtimeDir].concat(captures);
        freezeProcess.running = true;
    }

    function getTimestamp() {
        var d = new Date()
        var pad = (n) => n < 10 ? '0' + n : n;
        return d.getFullYear() + '-' + 
               pad(d.getMonth() + 1) + '-' + 
               pad(d.getDate()) + '-' + 
               pad(d.getHours()) + '-' + 
               pad(d.getMinutes()) + '-' + 
               pad(d.getSeconds());
    }

    function processRegion(x, y, w, h) {
        if (root.captureMode === "lens") {
            root.finalPath = root.lensPath;
        } else {
            if (root.screenshotsDir === "") {
                root.screenshotsDir = Paths.picturesDir + "/Screenshots"
            }
            var filename = "Screenshot_" + getTimestamp() + ".png"
            root.finalPath = root.screenshotsDir + "/" + filename
        }
        
        var m = null;
        if (root.monitors.length > 0) {
            m = root.monitors.find(mon => {
                var logicalW = mon.logicalWidth ?? (mon.width / mon.scale);
                var logicalH = mon.logicalHeight ?? (mon.height / mon.scale);

                return x >= mon.x && x < (mon.x + logicalW) &&
                       y >= mon.y && y < (mon.y + logicalH);
            });
        }
        
        if (!m) {
            console.warn("Screenshot: Could not find monitor for region " + x + "," + y);
            if (root.monitors.length > 0) m = root.monitors[0];
            else return; 
        }
        
        var localX = x - m.x;
        var localY = y - m.y;
        
        var physX = Math.round(localX * m.scale);
        var physY = Math.round(localY * m.scale);
        var physW = Math.round(w * m.scale);
        var physH = Math.round(h * m.scale);
        
        console.log(`Screenshot: Cropping on monitor ${m.name} (Scale ${m.scale})`);
        console.log(`Screenshot: Logical Local: ${localX},${localY} ${w}x${h} -> Physical: ${physX},${physY} ${physW}x${physH}`);
        
        var srcPath = root.tempPathBase + "_" + m.name + ".png";
        
        var geom = `${physW}x${physH}+${physX}+${physY}`;
        cropProcess.command = ["magick", srcPath, "-crop", geom, root.finalPath];
        cropProcess.running = true;
    }

    function processMonitorScreen(monitorName) {
         if (root.captureMode === "lens") {
            root.finalPath = root.lensPath;
        } else {
            if (root.screenshotsDir === "") {
                root.screenshotsDir = Paths.picturesDir + "/Screenshots"
            }
            var filename = "Screenshot_" + getTimestamp() + ".png"
            root.finalPath = root.screenshotsDir + "/" + filename
        }
        
        var srcPath = root.tempPathBase + "_" + monitorName + ".png";
        cropProcess.command = ["cp", srcPath, root.finalPath];
        cropProcess.running = true;
    }

    function runLensScript() {
        verifyImageProcess.command = ["test", "-f", root.lensPath];
        verifyImageProcess.running = true;
    }
    
    property Process verifyImageProcess: Process {
        id: verifyImageProcess
        onExited: exitCode => {
            if (exitCode === 0) {
                var scriptPath = Paths.script("google_lens.sh");
                lensProcess.command = ["bash", scriptPath, root.lensPath];
                lensProcess.running = true;
            } else {
                root.errorOccurred("Image file not ready for Google Lens")
            }
        }
    }
}
