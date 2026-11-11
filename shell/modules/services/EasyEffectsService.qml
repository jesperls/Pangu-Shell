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
    property var deviceBindings: ({ output: {}, input: {} })

    property int _replyIndex: 2
    property bool queryPending: false
    property bool _pendingAutoApply: false

    function _loadBindings() {
        const saved = StateService.get("easyEffectsDevicePresets", null);
        if (saved && typeof saved === "object") {
            root.deviceBindings = {
                output: Object.assign({}, saved.output || {}),
                input: Object.assign({}, saved.input || {})
            };
        }
    }

    function getDeviceBinding(isOutput: bool, deviceName: string) {
        if (!deviceName) return null;
        const group = isOutput ? (root.deviceBindings.output || {}) : (root.deviceBindings.input || {});
        return group[deviceName] ?? null;
    }

    function setDeviceBinding(isOutput: bool, deviceName: string, presetName: string, bypassState: bool) {
        if (!deviceName) return;
        const key = isOutput ? "output" : "input";
        const nextGroup = Object.assign({}, root.deviceBindings[key] || {});
        nextGroup[deviceName] = {
            preset: presetName || "",
            bypass: Boolean(bypassState)
        };
        const next = {
            output: key === "output" ? nextGroup : Object.assign({}, root.deviceBindings.output || {}),
            input: key === "input" ? nextGroup : Object.assign({}, root.deviceBindings.input || {})
        };
        root.deviceBindings = next;
        if (StateService.initialized)
            StateService.set("easyEffectsDevicePresets", next);
    }

    function _applyBindingsForCurrentDevices() {
        if (!socket.connected || !(Config.system?.audio?.autoSwitchPresets ?? true))
            return;
        const sinkName = Audio.sink?.name ?? "";
        const outBind = getDeviceBinding(true, sinkName);
        if (outBind) {
            socket.write("global_bypass:" + (outBind.bypass ? "1" : "0") + "\n");
            if (!outBind.bypass && outBind.preset)
                socket.write("load_preset:output:" + outBind.preset + "\n");
        }
        const sourceName = Audio.source?.name ?? "";
        const inBind = getDeviceBinding(false, sourceName);
        if (inBind && inBind.preset)
            socket.write("load_preset:input:" + inBind.preset + "\n");
    }

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
        const sinkName = Audio.sink?.name ?? "";
        if (sinkName) {
            const prev = getDeviceBinding(true, sinkName);
            setDeviceBinding(true, sinkName, prev?.preset || root.activeOutputPreset, enable);
        }
        _query();
    }

    function loadOutputPreset(name: string) {
        if (!socket.connected) return;
        if (root.bypassed)
            socket.write("global_bypass:0\n");
        socket.write("load_preset:output:" + name + "\n");
        const sinkName = Audio.sink?.name ?? "";
        if (sinkName)
            setDeviceBinding(true, sinkName, name, false);
        _query();
    }

    function loadInputPreset(name: string) {
        if (!socket.connected) return;
        socket.write("load_preset:input:" + name + "\n");
        const sourceName = Audio.source?.name ?? "";
        if (sourceName)
            setDeviceBinding(false, sourceName, name, false);
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
        interval: 650
        onTriggered: {
            if (!socket.connected) {
                root._pendingAutoApply = true;
                socket.connected = true;
                return;
            }
            root._applyBindingsForCurrentDevices();
            root._query();
        }
    }

    Timer {
        id: startupConnectTimer
        interval: 1500
        running: Config.initialLoadComplete && (Config.system?.audio?.autoSwitchPresets ?? true)
        repeat: false
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        if (StateService.initialized)
            root._loadBindings();
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            root._loadBindings();
        }
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
                if (root._pendingAutoApply) {
                    root._pendingAutoApply = false;
                    root._applyBindingsForCurrentDevices();
                }
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
