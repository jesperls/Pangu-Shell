pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

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
        interval: 2000
        onTriggered: socket.connected = false
    }

    Socket {
        id: socket
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/EasyEffectsServer"
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
                    const m = data.match(/^([12])(.*)$/);  // get_global_bypass reply has no newline, fusing it to the next line
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

    Process {
        id: outputPresetsProcess
        command: ["ls", "-1", "--", Paths.dataHome + "/easyeffects/output"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.outputPresets = text.split("\n").filter(n => n.endsWith(".json")).map(n => n.slice(0, -5))
        }
    }

    Process {
        id: inputPresetsProcess
        command: ["ls", "-1", "--", Paths.dataHome + "/easyeffects/input"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.inputPresets = text.split("\n").filter(n => n.endsWith(".json")).map(n => n.slice(0, -5))
        }
    }
}
