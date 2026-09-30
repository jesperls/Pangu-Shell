pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    property bool active: false
    property bool saving: false
    readonly property int bufferSeconds: Config.system.replay?.seconds ?? 60
    property string captureMode: "screen"
    property string captureRegion: ""
    property bool audioOutput: true
    property bool audioInput: false
    property int activeSeconds: bufferSeconds
    property string videosDir: ""
    property int daemonPid: 0
    property bool adopted: false

    property bool _initialized: false
    property bool _scanned: false
    property bool _pendingStart: false
    property bool _stopping: false

    function initialize() {
        if (_initialized)
            return;
        _initialized = true;
        ScreenRecorder.initialize();
        xdgVideosProcess.running = true;
        scanProcess.running = true;
    }

    function startWithOptions(mode, region, out, inp, seconds) {
        if (root.active || root._pendingStart || prepareProcess.running || daemonProcess.running)
            return;
        root.captureMode = mode === "region" && region ? "region" : "screen";
        root.captureRegion = region || "";
        root.audioOutput = out;
        root.audioInput = inp;
        root.activeSeconds = seconds > 0 ? seconds : root.bufferSeconds;
        start();
    }

    function start() {
        if (root.active || root._pendingStart || prepareProcess.running || daemonProcess.running)
            return;
        root._pendingStart = true;
        initialize();
        maybeStart();
    }

    function stop() {
        if (!root.active || root.daemonPid <= 0)
            return;
        root._stopping = true;
        stopProcess.command = ["kill", "-INT", "" + root.daemonPid];
        stopProcess.running = true;
        if (root.adopted) {
            root.adopted = false;
            root.daemonPid = 0;
            root.active = false;
            root._stopping = false;
        }
    }

    function toggle() {
        if (root.active) {
            stop();
        } else {
            start();
        }
    }

    function saveClip() {
        if (!root.active || root.daemonPid <= 0 || root.saving)
            return;
        root.saving = true;
        saveProcess.command = ["kill", "-USR1", "" + root.daemonPid];
        saveProcess.running = true;
    }

    function maybeStart() {
        if (!root._pendingStart || !root._scanned || root.videosDir === "" || !ScreenRecorder.capabilitiesReady)
            return;
        root._pendingStart = false;
        if (!ScreenRecorder.canRecordDirectly) {
            Notifications.notifyInternal({
                summary: "Replay",
                body: "Direct screen capture is unavailable without the NixOS gpu-screen-recorder wrapper"
            });
            return;
        }
        if (!root.active)
            prepareProcess.running = true;
    }

    onActiveChanged: if (StateService.initialized) StateService.set("replay", root.active)

    Component.onCompleted: {
        initialize();
        if (StateService.initialized)
            restore();
    }

    function restore() {
        if (StateService.get("replay", false)) {
            const opts = StateService.get("replayOptions", null);
            if (opts) {
                root.captureMode = opts.mode || "screen";
                root.captureRegion = opts.region || "";
                root.audioOutput = opts.out !== false;
                root.audioInput = opts.inp === true;
                root.activeSeconds = opts.seconds > 0 ? opts.seconds : root.bufferSeconds;
            }
            start();
        }
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            root.restore();
        }
    }

    Connections {
        target: ScreenRecorder
        function onCapabilitiesReadyChanged() { root.maybeStart(); }
    }

    Process {
        id: xdgVideosProcess
        command: ["xdg-user-dir", "VIDEOS"]
        running: false
        stdout: StdioCollector {}
        onExited: exitCode => {
            var dir = exitCode === 0 ? xdgVideosProcess.stdout.text.trim() : "";
            if (dir === "")
                dir = Paths.videosDir;
            root.videosDir = dir + "/Replays";
            root.maybeStart();
        }
    }

    Process {
        id: scanProcess
        command: ["bash", "-c", "pgrep -u \"$(id -u)\" -fa '^([^ ]*/)?\\.?gpu-screen-recorder(-wrapped)?( |$)' || true"]
        running: false
        stdout: StdioCollector {}
        onExited: exitCode => {
            var pid = 0;
            var lines = scanProcess.stdout.text.split("\n");
            for (var i = 0; i < lines.length; i++) {
                if (lines[i].indexOf(" -r ") !== -1) {
                    pid = parseInt(lines[i]);
                    break;
                }
            }
            root._scanned = true;
            if (pid > 0) {
                console.log("[Replay] Adopted running replay daemon, pid " + pid);
                root.daemonPid = pid;
                root.adopted = true;
                root.active = true;
                root._pendingStart = false;
            } else {
                root.maybeStart();
            }
        }
    }

    Process {
        id: prepareProcess
        command: ["mkdir", "-p", root.videosDir]
        running: false
        onExited: exitCode => {
            if (exitCode !== 0) {
                Notifications.notifyInternal({summary: "Replay", body: "Could not create replay directory"});
                return;
            }
            var cmd = ["gpu-screen-recorder", "-f", "60", "-fallback-cpu-encoding", "yes"];
            if (root.captureMode === "region" && root.captureRegion !== "") {
                cmd.push("-w", "region", "-region", root.captureRegion);
            } else {
                cmd.push("-w", "screen");
            }
            var audioSources = [];
            if (root.audioOutput)
                audioSources.push("default_output");
            if (root.audioInput)
                audioSources.push("default_input");
            if (audioSources.length > 0)
                cmd.push("-a", audioSources.join("|"));
            cmd.push("-r", "" + root.activeSeconds, "-c", "mp4", "-o", root.videosDir);
            daemonProcess.command = cmd;
            daemonProcess.running = true;
        }
    }

    Process {
        id: daemonProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: console.log("[Replay] OUT: " + text)
        }
        stderr: StdioCollector {
            onStreamFinished: console.warn("[Replay] ERR: " + text)
        }
        onStarted: {
            root.daemonPid = daemonProcess.processId;
            root.adopted = false;
            root.active = true;
            if (StateService.initialized)
                StateService.set("replayOptions", {
                    mode: root.captureMode,
                    region: root.captureRegion,
                    out: root.audioOutput,
                    inp: root.audioInput,
                    seconds: root.activeSeconds
                });
        }
        onExited: exitCode => {
            root.daemonPid = 0;
            root.active = false;
            root.saving = false;
            if (!root._stopping && exitCode !== 0 && exitCode !== 130 && exitCode !== 2) {
                Notifications.notifyInternal({
                    summary: "Replay",
                    body: "Replay buffer stopped unexpectedly. Check logs."
                });
            }
            root._stopping = false;
        }
    }

    Process {
        id: stopProcess
        running: false
    }

    Process {
        id: saveProcess
        running: false
        onExited: exitCode => {
            if (exitCode === 0) {
                savingResetTimer.restart();
                Notifications.notifyInternal({
                    summary: "Replay",
                    body: "Requested saving the last " + root.activeSeconds + "s to " + root.videosDir
                });
            } else {
                root.saving = false;
                Notifications.notifyInternal({
                    summary: "Replay",
                    body: "Failed to save clip: replay daemon not responding"
                });
            }
        }
    }

    Timer {
        id: savingResetTimer
        interval: 1500
        onTriggered: root.saving = false
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.active && root.adopted && !SuspendManager.isSuspending
        onTriggered: {
            adoptCheckProcess.command = ["kill", "-0", "" + root.daemonPid];
            adoptCheckProcess.running = true;
        }
    }

    Process {
        id: adoptCheckProcess
        running: false
        onExited: exitCode => {
            if (exitCode !== 0 && root.adopted) {
                root.adopted = false;
                root.daemonPid = 0;
                root.active = false;
            }
        }
    }
}
