pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.components
import qs.modules.services

Singleton {
    id: root

    property var values: []
    property int bars: 20
    property int refCount: 0
    property bool available: true
    property bool retried: false

    readonly property bool shouldRun: Config.performance.audioVisualizer && refCount > 0 && MprisController.isPlaying && !SuspendManager.isSuspending

    function acquire() {
        refCount++;
    }

    function release() {
        refCount = Math.max(0, refCount - 1);
    }

    function start() {
        if (!root.shouldRun || !root.available || cavaProc.running) return;
        configFile.write("[general]\nbars = " + root.bars
            + "\nframerate = 30\n[output]\nmethod = raw\nraw_target = /dev/stdout"
            + "\ndata_format = ascii\nascii_max_range = 100\n");
    }

    onShouldRunChanged: {
        if (shouldRun) {
            retried = false;
            available = true;
            root.start();
        } else {
            retryTimer.stop();
            cavaProc.running = false;
            values = [];
        }
    }

    Connections {
        target: Audio
        function onSinkChanged() {
            if (cavaProc.running) {
                root.retried = false;
                cavaProc.running = false;
            }
        }
    }

    GeneratedFile {
        id: configFile
        path: Paths.runtimePath("cava.conf")
        onWritten: if (root.shouldRun && root.available) cavaProc.running = true
        onFailed: root.available = false
    }

    Process {
        id: cavaProc
        command: ["cava", "-p", configFile.path]

        stdout: SplitParser {
            onRead: data => {
                const parts = data.split(";");
                const next = [];
                for (let i = 0; i < root.bars; i++) {
                    const v = parseInt(parts[i], 10);
                    next.push(isNaN(v) ? 0 : Math.min(1, v / 100));
                }
                root.values = next;
            }
        }

        onExited: {
            root.values = [];
            if (!root.shouldRun)
                return;
            if (root.retried) {
                root.available = false;
            } else {
                root.retried = true;
                retryTimer.restart();
            }
        }
    }

    Timer {
        id: healthyTimer
        interval: 10000
        running: cavaProc.running
        onTriggered: root.retried = false
    }

    Timer {
        id: retryTimer
        interval: 1000
        onTriggered: root.start()
    }
}
