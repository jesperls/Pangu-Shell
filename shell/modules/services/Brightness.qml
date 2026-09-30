pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import qs.modules.services
import QtQuick

Singleton {
    id: root

    signal brightnessChanged(real value, var screen)

    property var ddcMonitors: []
    property list<BrightnessMonitor> monitors: []

    function syncMonitors() {
        const previous = root.monitors.slice();
        root.monitors = Quickshell.screens.map(screen => previous.find(monitor => monitor.screen === screen)
            || monitorComp.createObject(root, {screen}));
        previous.filter(monitor => root.monitors.indexOf(monitor) === -1).forEach(monitor => monitor.destroy());
    }

    Component.onCompleted: syncMonitors()
    Connections {
        target: Quickshell
        function onScreensChanged() { root.syncMonitors(); }
    }

    property bool syncBrightness: StateService.get("syncBrightness", false)

    property var suspendConnections: Connections {
        target: SuspendManager
        function onWakingUp() {
            ddcDetectTimer.restart();
        }
    }

    onSyncBrightnessChanged: {
        if (StateService.initialized) {
            StateService.set("syncBrightness", syncBrightness);
        }
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            root.syncBrightness = StateService.get("syncBrightness", false);
        }
    }

    function isInternalScreen(screen: ShellScreen): bool {
        if (!screen || !screen.name)
            return false;
        const lower = screen.name.toLowerCase();
        return lower.includes("edp") || lower.includes("lvds") || lower.includes("dsi");
    }

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.screen === screen);
    }

    function increaseBrightness(): void {
        if (!Compositor.focusedMonitor)
            return;
        const focusedName = Compositor.focusedMonitor.name;
        const monitor = monitors.find(m => focusedName === m.screen.name);
        if (monitor)
            monitor.setBrightness(monitor.brightness + 0.05);
    }

    function decreaseBrightness(): void {
        if (!Compositor.focusedMonitor)
            return;
        const focusedName = Compositor.focusedMonitor.name;
        const monitor = monitors.find(m => focusedName === m.screen.name);
        if (monitor)
            monitor.setBrightness(monitor.brightness - 0.05);
    }

    reloadableId: "brightness"

    onMonitorsChanged: {
        ddcMonitors = [];
        ddcDetectTimer.restart();
    }

    Timer {
        id: ddcDetectTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!SuspendManager.isSuspending) {
                ddcProc.running = true;
            }
        }
    }

    Process {
        id: ddcProc

        property var found: []
        onStarted: found = []
        command: ["ddcutil", "detect", "--brief"]
        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: data => {
                const trimmed = data.trim();
                if (!trimmed.startsWith("Display "))
                    return;

                const lines = trimmed.split("\n").map(l => l.trim()).filter(l => l.length > 0);
                const busLine = lines.find(l => l.startsWith("I2C bus:"));
                if (!busLine)
                    return;

                const busSplit = busLine.split("/dev/i2c-");
                const busNum = busSplit.length > 1 ? busSplit[1] : "";
                if (!busNum)
                    return;

                const modelLine = lines.find(l => l.startsWith("Model:"));
                const monitorLine = lines.find(l => l.startsWith("Monitor:"));
                const manufacturerLine = lines.find(l => l.startsWith("Mfg id:"));

                let model = "";
                if (modelLine) {
                    model = modelLine.split(":").slice(1).join(":").trim();
                } else if (monitorLine) {
                    model = monitorLine.split(":").slice(1).join(":").trim();
                }

                if (manufacturerLine && model) {
                    const manufacturer = manufacturerLine.split(":").slice(1).join(":").trim();
                    if (manufacturer && !model.startsWith(manufacturer))
                        model = `${manufacturer} ${model}`;
                }

                const connectorLine = lines.find(line => line.startsWith("DRM connector:")) || "";
                const connector = connectorLine.match(/card\d+-(.+)$/)?.[1] || "";
                ddcProc.found.push({model, busNum, connector});
            }
        }
        onExited: code => root.ddcMonitors = code === 0 ? found : []
    }

    component BrightnessMonitor: QtObject {
        id: monitor

        required property ShellScreen screen
        readonly property int monitorIndex: root.monitors.indexOf(this)
        readonly property bool useBrightnessctl: root.isInternalScreen(screen)
        readonly property var ddcEntry: {
            if (useBrightnessctl || root.ddcMonitors.length === 0)
                return null;

            const usedBuses = [];
            for (let i = 0; i < monitorIndex; ++i) {
                const mon = root.monitors[i];
                if (mon && mon.ddcEntry && mon.ddcEntry.busNum && !usedBuses.includes(mon.ddcEntry.busNum))
                    usedBuses.push(mon.ddcEntry.busNum);
            }

            const connectorMatch = root.ddcMonitors.find(entry => entry.connector === screen.name && !usedBuses.includes(entry.busNum));
            if (connectorMatch) return connectorMatch;

            const screenModel = screen && screen.model ? screen.model.toLowerCase() : "";
            if (screenModel) {
                const modelMatch = root.ddcMonitors.find(entry => entry.model && entry.model.toLowerCase() === screenModel && !usedBuses.includes(entry.busNum));
                if (modelMatch)
                    return modelMatch;
            }

            for (let i = 0; i < root.ddcMonitors.length; ++i) {
                const entry = root.ddcMonitors[i];
                if (entry && entry.busNum && !usedBuses.includes(entry.busNum))
                    return entry;
            }

            return null;
        }
        readonly property bool isDdc: !useBrightnessctl && !!ddcEntry
        readonly property string busNum: isDdc ? ddcEntry.busNum : ""
        property int rawMaxBrightness: 100
        property real brightness
        property bool ready: false

        onBrightnessChanged: {
            if (monitor.ready) {
                root.brightnessChanged(monitor.brightness, monitor.screen);
            }
        }

        function initialize() {
            monitor.ready = false;
            if (!useBrightnessctl && !isDdc)
                return;
            if (isDdc && !busNum)
                return;
            initProc.command = isDdc ? ["ddcutil", "-b", busNum, "getvcp", "10"] : ["sh", "-c", `echo "a b c $(brightnessctl g) $(brightnessctl m)"`];
            initProc.running = true;
        }

        readonly property Process initProc: Process {
            stdout: SplitParser {
                onRead: data => {
                    const trimmed = data.trim();
                    const verboseMatch = trimmed.match(/current\s+value\s*=\s*(\d+).*max\s+value\s*=\s*(\d+)/);
                    if (verboseMatch) {
                        const currentRaw = parseInt(verboseMatch[1]);
                        const maxRaw = parseInt(verboseMatch[2]);
                        if (!isNaN(currentRaw) && !isNaN(maxRaw) && maxRaw > 0) {
                            monitor.rawMaxBrightness = maxRaw;
                            monitor.brightness = currentRaw / monitor.rawMaxBrightness;
                            monitor.ready = true;
                            root.brightnessChanged(monitor.brightness, monitor.screen);
                        }
                        return;
                    }
                    const tokens = trimmed.split(/\s+/);
                    if (tokens.length < 2)
                        return;
                    const currentRaw = parseInt(tokens[tokens.length - 2]);
                    const maxRaw = parseInt(tokens[tokens.length - 1]);
                    if (isNaN(currentRaw) || isNaN(maxRaw) || maxRaw <= 0)
                        return;
                    monitor.rawMaxBrightness = maxRaw;
                    monitor.brightness = currentRaw / monitor.rawMaxBrightness;
                    monitor.ready = true;
                    root.brightnessChanged(monitor.brightness, monitor.screen);
                }
            }
        }

        property var setTimer: Timer {
            id: setTimer
            interval: monitor.isDdc ? 300 : 0
            onTriggered: {
                syncBrightness();
            }
        }

        property bool writePending: false
        readonly property Process setProc: Process {
            onExited: {
                if (monitor.writePending) {
                    monitor.writePending = false;
                    monitor.syncBrightness();
                }
            }
        }

        function syncBrightness() {
            if (!ready || (isDdc && !busNum))
                return;
            if (setProc.running) {
                writePending = true;
                return;
            }
            const rounded = Math.round(monitor.brightness * monitor.rawMaxBrightness);
            setProc.command = isDdc ? ["ddcutil", "-b", busNum, "setvcp", "10", rounded] : ["brightnessctl", "--class", "backlight", "s", rounded, "--quiet"];
            setProc.running = true;
        }

        function setBrightness(value: real): void {
            if (!ready || !Number.isFinite(value)) return;
            value = Math.max(0.01, Math.min(1, value));
            monitor.brightness = value;
            setTimer.restart();
        }

        Component.onCompleted: {
            initialize();
        }

        onBusNumChanged: {
            initialize();
        }
    }

    Component {
        id: monitorComp

        BrightnessMonitor {}
    }

    IpcHandler {
        target: "brightness"

        function set(value: real, monitorName: string) {
            if (!monitorName || monitorName === "") {
                for (let i = 0; i < root.monitors.length; ++i) {
                    const mon = root.monitors[i];
                    if (mon && mon.ready) {
                        mon.setBrightness(value);
                    }
                }
            } else {
                const monitor = root.monitors.find(m => m.screen.name === monitorName);
                if (monitor && monitor.ready) {
                    monitor.setBrightness(value);
                } else {
                    console.warn("Monitor not found or not ready:", monitorName);
                }
            }
        }

        function adjust(delta: real, monitorName: string) {
            if (!monitorName || monitorName === "") {
                for (let i = 0; i < root.monitors.length; ++i) {
                    const mon = root.monitors[i];
                    if (mon && mon.ready) {
                        mon.setBrightness(mon.brightness + delta);
                    }
                }
            } else {
                const monitor = root.monitors.find(m => m.screen.name === monitorName);
                if (monitor && monitor.ready) {
                    monitor.setBrightness(monitor.brightness + delta);
                } else {
                    console.warn("Monitor not found or not ready:", monitorName);
                }
            }
        }
    }
}
