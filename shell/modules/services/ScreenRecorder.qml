pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services

Singleton {
    id: root

    property bool isRecording: false
    property string duration: ""
    property bool canRecordDirectly: false
    property bool capabilitiesReady: false

    property bool _initialized: false
    property real startedAtMs: 0
    property int adoptedPid: 0
    property string lastOutputFile: ""

    function initialize() {
        if (_initialized) return;
        _initialized = true;
        checkCapabilitiesProcess.running = true;
        xdgVideosProcess.running = true;
        adoptScanProcess.running = true;
    }

    function formatElapsed(ms) {
        const totalSec = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(totalSec / 3600);
        const m = Math.floor((totalSec % 3600) / 60);
        const s = totalSec % 60;
        const pad = n => String(n).padStart(2, "0");
        return h > 0 ? `${pad(h)}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
    }

    Process {
        id: checkCapabilitiesProcess
        command: ["bash", "-c", "if [ -f /run/current-system/sw/bin/nixos-version ]; then if [ -x /run/wrappers/bin/gsr-kms-server ]; then echo true; else echo false; fi; else echo true; fi"]
        running: false
        stdout: StdioCollector {}
        onExited: code => {
            root.canRecordDirectly = code === 0 && checkCapabilitiesProcess.stdout.text.trim() === "true";
            root.capabilitiesReady = true;
        }
    }

    property string videosDir: Paths.videosDir + "/Recordings"
    property bool starting: false

    Process {
        id: xdgVideosProcess
        command: ["xdg-user-dir", "VIDEOS"]
        running: false
        stdout: StdioCollector {}
        onExited: exitCode => {
            if (exitCode === 0) {
                const dir = xdgVideosProcess.stdout.text.trim() || Paths.videosDir;
                root.videosDir = dir + "/Recordings";
            } else {
                root.videosDir = Paths.videosDir + "/Recordings";
            }
        }
    }

    Process {
        id: adoptScanProcess
        command: ["bash", "-c", "pgrep -u \"$(id -u)\" -fa '^([^ ]*/)?\\.?gpu-screen-recorder(-wrapped)?( |$)' | grep -v \"^$$ \" | grep -v ' -r ' | awk 'NR==1 {print $1}'"]
        running: false
        stdout: StdioCollector {}
        onExited: exitCode => {
            const pid = exitCode === 0 ? parseInt(adoptScanProcess.stdout.text.trim(), 10) : 0;
            if (pid > 0 && !startProcess.running) {
                root.adoptedPid = pid;
                root.startedAtMs = Date.now();
                root.isRecording = true;
                root.duration = root.formatElapsed(0);
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.isRecording && !SuspendManager.isSuspending
        onTriggered: {
            if (root.startedAtMs > 0)
                root.duration = root.formatElapsed(Date.now() - root.startedAtMs);
            if (root.adoptedPid > 0 && !startProcess.running && !adoptCheckProcess.running) {
                adoptCheckProcess.command = ["kill", "-0", String(root.adoptedPid)];
                adoptCheckProcess.running = true;
            }
        }
    }

    Process {
        id: adoptCheckProcess
        running: false
        onExited: exitCode => {
            if (exitCode !== 0 && root.adoptedPid > 0 && !startProcess.running) {
                root.adoptedPid = 0;
                root.isRecording = false;
                root.duration = "";
            }
        }
    }

    function toggleRecording() {
        if (isRecording) {
            if (startProcess.running && startProcess.processId > 0) {
                stopProcess.command = ["kill", "-INT", String(startProcess.processId)];
            } else if (root.adoptedPid > 0) {
                stopProcess.command = ["kill", "-INT", String(root.adoptedPid)];
            } else {
                stopProcess.command = ["bash", "-c", "pgrep -u \"$(id -u)\" -fa '^([^ ]*/)?\\.?gpu-screen-recorder(-wrapped)?( |$)' | grep -v \"^$$ \" | grep -v ' -r ' | awk '{print $1}' | xargs -r kill -INT"];
            }
            stopProcess.running = true;
        } else {
            startRecording(false, false, "portal", "");
        }
    }

    function startRecording(recordAudioOutput, recordAudioInput, mode, regionStr) {
        if (isRecording || starting)
            return;
        if (["portal", "screen", "region"].indexOf(mode) === -1)
            return;
        root.starting = true;

        var outputFile = root.videosDir + "/" + new Date().toISOString().replace(/[:.]/g, "-") + ".mp4";
        root.lastOutputFile = outputFile;
        var cmd = ["gpu-screen-recorder", "-f", "60", "-w", mode, "-fallback-cpu-encoding", "yes"];
        if (mode === "region" && regionStr)
            cmd.push("-region", regionStr);

        var audioSources = [];
        if (recordAudioOutput)
            audioSources.push("default_output");
        if (recordAudioInput)
            audioSources.push("default_input");
        if (audioSources.length > 0)
            cmd.push("-a", audioSources.join("|"));
        cmd.push("-o", outputFile);
        startProcess.command = cmd;

        prepareProcess.running = true;
    }

    Process {
        id: prepareProcess
        command: ["mkdir", "-p", root.videosDir]
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.starting = false;
                console.warn("[ScreenRecorder] failed to create output dir:", root.videosDir);
                return;
            }
            startProcess.running = true;
        }
    }

    Process {
        id: startProcess
        onStarted: {
            root.starting = false;
            root.adoptedPid = 0;
            root.startedAtMs = Date.now();
            root.duration = "00:00";
            root.isRecording = true;
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("[ScreenRecorder]", text.trim());
            }
        }

        onExited: exitCode => {
            root.starting = false;
            root.isRecording = false;
            root.duration = "";
            if (exitCode !== 0 && exitCode !== 130 && exitCode !== 2) { // 2 = SIGINT
                Notifications.notifyInternal({
                    summary: "Screen Recorder Error",
                    body: "Recording failed. Check system logs."
                });
            } else if (root.lastOutputFile !== "") {
                verifyOutputProcess.command = ["test", "-s", root.lastOutputFile];
                verifyOutputProcess.running = true;
            }
        }
    }

    Process {
        id: verifyOutputProcess
        running: false
        onExited: exitCode => {
            if (exitCode === 0) {
                Notifications.notifyInternal({
                    summary: "Screen Recorder",
                    body: "Recording saved to " + root.lastOutputFile
                });
            }
        }
    }

    Process {
        id: stopProcess
        running: false
    }
}
