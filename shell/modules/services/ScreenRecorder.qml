pragma Singleton

import QtQuick
import Quickshell.Io
import qs.config

QtObject {
    id: root

    property bool isRecording: false
    property string duration: ""
    property bool canRecordDirectly: false
    property bool capabilitiesReady: false

    property bool _initialized: false

    function initialize() {
        if (_initialized) return;
        _initialized = true;
        checkCapabilitiesProcess.running = true;
        xdgVideosProcess.running = true;
        checkProcess.running = true;
    }

    property Process checkCapabilitiesProcess: Process {
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

    property Process xdgVideosProcess: Process {
        id: xdgVideosProcess
        command: ["xdg-user-dir", "VIDEOS"]
        running: false
        stdout: StdioCollector {
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                var dir = xdgVideosProcess.stdout.text.trim();
                if (dir === "") {
                    dir = Paths.videosDir;
                }
                root.videosDir = dir + "/Recordings";
            } else {
                root.videosDir = Paths.videosDir + "/Recordings";
            }
        }
    }

    property Timer statusTimer: Timer {
        interval: 1000
        repeat: true
        running: root.isRecording && !SuspendManager.isSuspending
        onTriggered: {
            checkProcess.running = true;
        }
    }

    property Process checkProcess: Process {
        id: checkProcess
        command: ["bash", "-c", "pgrep -u \"$(id -u)\" -fa '^([^ ]*/)?\\.?gpu-screen-recorder(-wrapped)?( |$)' | grep -v \"^$$ \" | grep -v ' -r ' | grep -q ."]
        onExited: exitCode => {
            var wasRecording = root.isRecording;
            root.isRecording = startProcess.running || (exitCode === 0);

            if (root.isRecording && !wasRecording) {
                console.log("[ScreenRecorder] Detected running instance.");
            }

            if (root.isRecording) {
                timeProcess.running = true;
            } else {
                root.duration = "";
            }
        }
    }

    property Process timeProcess: Process {
        id: timeProcess
        command: ["bash", "-c", "pid=$(pgrep -u \"$(id -u)\" -fa '^([^ ]*/)?\\.?gpu-screen-recorder(-wrapped)?( |$)' | grep -v \"^$$ \" | grep -v ' -r ' | awk 'NR==1 {print $1}'); if [ -n \"$pid\" ]; then ps -o etime= -p \"$pid\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.duration = text.trim();
            }
        }
    }

    function toggleRecording() {
        if (isRecording) {
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

    property Process prepareProcess: Process {
        id: prepareProcess
        command: ["mkdir", "-p", root.videosDir]
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.starting = false;
                console.warn("[ScreenRecorder] failed to create output dir:", root.videosDir);
                return;
            }
            notifyStartProcess.running = true;
            startProcess.running = true;
        }
    }

    property Process notifyStartProcess: Process {
        id: notifyStartProcess
        command: ["notify-send", "Screen Recorder", "Starting recording..."]
    }

    property Process startProcess: Process {
        id: startProcess
        onStarted: {
            root.starting = false;
            root.isRecording = true;
        }

        stdout: StdioCollector {
            onStreamFinished: console.log("[ScreenRecorder] OUT: " + text)
        }
        stderr: StdioCollector {
            id: stderrCollector
            onStreamFinished: {
                console.warn("[ScreenRecorder] ERR: " + text);
            }
        }

        onExited: exitCode => {
            root.starting = false;
            root.isRecording = false;
            root.duration = "";
            console.log("[ScreenRecorder] Exited with code: " + exitCode);
            if (exitCode !== 0 && exitCode !== 130 && exitCode !== 2) {  // 2 = SIGINT
                notifyErrorProcess.running = true;
            } else {
                notifySavedProcess.running = true;
            }
        }
    }

    property Process notifyErrorProcess: Process {
        id: notifyErrorProcess
        command: ["notify-send", "-u", "critical", "Screen Recorder Error", "Failed to start. Check logs."]
    }

    property Process notifySavedProcess: Process {
        id: notifySavedProcess
        command: ["notify-send", "Screen Recorder", "Recording saved to " + root.videosDir]
    }

    property Process stopProcess: Process {
        id: stopProcess
        command: ["bash", "-c", "pgrep -u \"$(id -u)\" -fa '^([^ ]*/)?\\.?gpu-screen-recorder(-wrapped)?( |$)' | grep -v \"^$$ \" | grep -v ' -r ' | awk '{print $1}' | xargs -r kill -INT"]
    }
}
