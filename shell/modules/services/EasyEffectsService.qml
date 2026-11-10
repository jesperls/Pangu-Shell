pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services

Singleton {
    id: root

    property bool available: false
    property bool bypassed: false

    property var outputPresets: []
    property var inputPresets: []

    property string activeOutputPreset: ""
    property string activeInputPreset: ""

    property int _replyIndex: 2
    property bool queryPending: false

    function _query() {
        if (!socket.connected) return;
        if (_replyIndex < 2) {
            queryPending = true;
            socket.flush();
            return;
        }
        queryPending = false;
        _replyIndex = 0;
        queryTimeout.restart();
        socket.write("get_global_bypass\nget_last_loaded_preset:input\nget_last_loaded_preset:output\n");
        socket.flush();
    }

    function setBypass(enable: bool) {
        if (!socket.connected) return;
        socket.write("global_bypass:" + (enable ? "1" : "0") + "\n");
        _query();
    }

    function loadOutputPreset(name: string) {
        if (!socket.connected) return;
        socket.write("load_preset:output:" + name + "\n");
        _query();
    }

    function loadInputPreset(name: string) {
        if (!socket.connected) return;
        socket.write("load_preset:input:" + name + "\n");
        _query();
    }

    function refresh() {
        outputPresetsProcess.running = true;
        inputPresetsProcess.running = true;
        if (socket.connected) {
            _query();
        } else {
            socket.connected = true;
        }
    }

    function openApp() {
        ApplicationLauncher.launchCommand(["easyeffects"]);
    }

    function initialize() {
        refresh();
    }

    Timer {
        id: queryTimeout
        interval: 5000
        onTriggered: socket.connected = false
    }

    Timer {
        id: deviceChangeTimer
        interval: 600
        onTriggered: if (socket.connected) root._query()
    }

    Connections {
        target: Audio
        function onSinkChanged() { deviceChangeTimer.restart(); }
        function onSourceChanged() { deviceChangeTimer.restart(); }
    }

    Socket {
        id: socket
        path: (Quickshell.env("XDG_RUNTIME_DIR") || Paths.cacheDir) + "/EasyEffectsServer"
        connected: false
        onConnectionStateChanged: {
            root.available = connected;
            root._replyIndex = 2;
            root.queryPending = false;
            queryTimeout.stop();
            if (connected) {
                root._query();
            }
        }
        onError: root.available = false
        parser: SplitParser {
            onRead: data => {
                if (root._replyIndex === 0) {
                    const m = data.match(/^([12])(.*)$/); // get_global_bypass reply has no newline, fusing it to the next line
                    if (m) {
                        root.bypassed = (m[1] === "1");
                        root.activeInputPreset = m[2];
                    }
                    root._replyIndex = 1;
                } else if (root._replyIndex === 1) {
                    root.activeOutputPreset = data;
                    root._replyIndex = 2;
                    queryTimeout.stop();
                    if (root.queryPending) root._query();
                }
            }
        }
    }

    function parsePresetNames(text) {
        const seen = new Set();
        return text.split("\n")
            .filter(n => n.endsWith(".json"))
            .map(n => n.slice(0, -5))
            .filter(n => {
                if (!n || seen.has(n)) return false;
                seen.add(n);
                return true;
            })
            .sort();
    }

    Process {
        id: outputPresetsProcess
        command: ["sh", "-c", "ls -1 -- \"$1\" \"$2\" 2>/dev/null || true", "sh",
            Paths.dataHome + "/easyeffects/output", Paths.configHome + "/easyeffects/output"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.outputPresets = root.parsePresetNames(text)
        }
    }

    Process {
        id: inputPresetsProcess
        command: ["sh", "-c", "ls -1 -- \"$1\" \"$2\" 2>/dev/null || true", "sh",
            Paths.dataHome + "/easyeffects/input", Paths.configHome + "/easyeffects/input"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.inputPresets = root.parsePresetNames(text)
        }
    }
}
