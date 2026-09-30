pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    property bool active: false
    property bool restored: false
    property bool stopping: false
    property int restartFailures: 0
    readonly property int temperature: Math.max(1000, Math.min(6500, Config.system.nightLight?.temperature ?? 4500))

    function toggle() {
        active = !active;
    }

    function reconcile() {
        restartTimer.stop();
        restartFailures = 0;
        if (wlsunsetProcess.running) {
            stopping = true;
            wlsunsetProcess.running = false;
        } else if (!stopping && active && restored && Config.initialLoadComplete) {
            restartTimer.interval = 150;
            restartTimer.restart();
        }
    }

    function processExited(code) {
        const expected = stopping;
        stopping = false;
        if (!active || !restored || !Config.initialLoadComplete)
            return;
        if (!expected) {
            restartFailures++;
            console.warn("Night light exited:", code);
        }
        restartTimer.interval = expected ? 150 : Math.min(30000, 300 * Math.pow(2, Math.min(7, restartFailures - 1)));
        restartTimer.restart();
    }

    function restore() {
        active = StateService.get("nightLight", false) === true;
        restored = true;
        reconcile();
    }

    onActiveChanged: {
        if (restored) StateService.set("nightLight", active);
        reconcile();
    }
    onTemperatureChanged: if (active) reconcile()
    Component.onCompleted: if (StateService.initialized) restore()

    Timer {
        id: restartTimer
        onTriggered: {
            if (root.active && root.restored && Config.initialLoadComplete && !root.stopping)
                wlsunsetProcess.running = true;
        }
    }

    Process {
        id: wlsunsetProcess
        command: ["wlsunset", "-t", String(root.temperature - 1), "-T", String(root.temperature)]
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn("Night light:", text.trim())
        }
        onExited: code => root.processExited(code)
    }

    Timer {
        interval: 30000
        running: wlsunsetProcess.running
        onTriggered: root.restartFailures = 0
    }

    Connections {
        target: StateService
        function onStateLoaded() { root.restore(); }
    }

    Connections {
        target: Config
        function onInitialLoadCompleteChanged() { root.reconcile(); }
    }
}
