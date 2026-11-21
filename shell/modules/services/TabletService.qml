pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config
import qs.modules.components
import qs.modules.services
import "tablet_utils.js" as TabletUtils

Singleton {
    id: root

    readonly property bool enabled: Boolean(Config.tablet?.enabled)
    property string state: "off"
    property string statusMessage: "Disabled"
    property string deviceSerial: ""
    property string deviceModel: ""
    property string transport: ""
    property string wifiIp: ""
    property string digitizerName: ""
    property string eventPath: ""
    property bool grabActive: false
    property bool hasTouch: false
    property bool touchpadActive: false
    property bool wirelessBusy: false
    property string wirelessFeedback: ""
    property bool wirelessError: false
    property int tabletMaxX: 20832
    property int tabletMaxY: 15624
    property int tabletMaxPressure: 4095
    property bool hasTilt: true
    property var availableDevices: []

    property bool penInProx: false
    property bool penTouching: false
    property real penX: 0.5
    property real penY: 0.5
    property real penRawX: 0.5
    property real penRawY: 0.5
    property real penPressure: 0.0
    property real penRawPressure: 0.0
    property int penTiltX: 0
    property int penTiltY: 0
    property var touchFingers: []

    property bool telemetryActive: false
    property bool _manualWifiDisconnect: false
    property bool _stopping: false
    property int _restartFailures: 0
    property string _lastAppliedLua: ""
    property string _lastAppliedTouchpadLua: ""

    readonly property bool connected: state === "connected"
    readonly property real tabletAspect: TabletUtils.effectiveTabletAspect(
        root.tabletMaxX, root.tabletMaxY, Config.tablet?.rotation ?? 0
    )

    readonly property var effectiveRegion: TabletUtils.resolveTargetRegion(
        Config.tablet,
        Compositor.monitors.values,
        Compositor.clients.values,
        Compositor.focusedMonitor,
        Compositor.gaps,
        root.tabletAspect,
        Compositor.focusedClient
    )

    readonly property var activeRect: TabletUtils.computeActiveRect(
        root.tabletAspect,
        Config.tablet?.areaScale ?? 1.0,
        Config.tablet?.areaOffsetX ?? 0.0,
        Config.tablet?.areaOffsetY ?? 0.0,
        Config.tablet?.aspectMode ?? "fit-tablet",
        root.effectiveRegion?.targetAspect ?? (16 / 9)
    )

    readonly property string runtimeConfigPath: Paths.runtimePath("tablet.json")

    readonly property string runtimeConfigJson: {
        const t = Config.tablet;
        const region = root.effectiveRegion;
        return JSON.stringify({
            deviceSerial: String(t?.deviceSerial || ""),
            wirelessAddress: String(t?.wirelessAddress || ""),
            wirelessAutoConnect: t?.wirelessAutoConnect !== false && !root._manualWifiDisconnect,
            inputMode: String(t?.inputMode || "pen"),
            rotation: Number(t?.rotation || 0),
            flipX: Boolean(t?.flipX),
            flipY: Boolean(t?.flipY),
            aspectMode: String(t?.aspectMode || "fit-tablet"),
            targetAspect: Number(region?.targetAspect || (16 / 9)),
            areaScale: Number(t?.areaScale ?? 1.0),
            areaOffsetX: Number(t?.areaOffsetX ?? 0.0),
            areaOffsetY: Number(t?.areaOffsetY ?? 0.0),
            pressureEnabled: t?.pressureEnabled !== false,
            pressureGamma: Number(t?.pressureGamma ?? 1.0),
            pressureMin: Number(t?.pressureMin ?? 0.0),
            pressureMax: Number(t?.pressureMax ?? 1.0),
            tiltEnabled: t?.tiltEnabled !== false,
            smoothing: Number(t?.smoothing ?? 0),
            eraserEnabled: t?.eraserEnabled !== false,
            swapStylusButtons: Boolean(t?.swapStylusButtons),
            suppressPen: t?.suppressPen !== false,
            suppressTouch: t?.suppressTouch !== false,
            keepAwake: t?.keepAwake !== false,
            touchpadSpeed: Number(t?.touchpadSpeed ?? 1.0),
            touchpadRotation: String(t?.touchpadRotation || "auto"),
            touchpadPalmRejectMs: Number(t?.touchpadPalmRejectMs ?? 350),
            telemetry: Boolean(root.telemetryActive)
        });
    }

    function setEnabled(value) {
        if (Boolean(value))
            root._manualWifiDisconnect = false;
        if (Config.tablet.enabled !== Boolean(value))
            Config.tablet.enabled = Boolean(value);
    }

    function toggle() {
        setEnabled(!Config.tablet.enabled);
    }

    function setInputMode(mode) {
        const next = (mode === "hybrid" || mode === "touchpad") ? mode : "pen";
        if (Config.tablet.inputMode !== next)
            Config.tablet.inputMode = next;
    }

    function cycleInputMode() {
        const cur = Config.tablet.inputMode || "pen";
        setInputMode(cur === "pen" ? "hybrid" : (cur === "hybrid" ? "touchpad" : "pen"));
    }

    function toggleTouchpadMode() {
        const cur = Config.tablet.inputMode || "pen";
        setInputMode(cur === "touchpad" ? "pen" : "touchpad");
    }

    function reconnect() {
        root._manualWifiDisconnect = false;
        if (!Config.tablet.enabled) {
            refreshDevices();
            return;
        }
        _restartFailures = 0;
        if (bridgeProcess.running) {
            _stopping = true;
            bridgeProcess.running = false;
        } else {
            reconcile();
        }
    }

    function refreshDevices() {
        if (!probeProcess.running)
            probeProcess.running = true;
    }

    function _runWirelessAction(args, onSuccess) {
        if (wirelessProcess.running)
            return;
        root.wirelessBusy = true;
        root.wirelessError = false;
        root.wirelessFeedback = "";
        wirelessProcess.onSuccessCallback = onSuccess || null;
        wirelessProcess.outputText = "";
        wirelessProcess.exited = false;
        wirelessProcess.streamDone = false;
        wirelessProcess.exitCode = -1;
        wirelessProcess.command = ["python3", Paths.script("tablet_bridge.py")].concat(args);
        wirelessProcess.running = true;
    }

    function enableWireless() {
        root._manualWifiDisconnect = false;
        const args = ["--enable-wifi"];
        if (root.deviceSerial && root.transport === "usb")
            args.push(root.deviceSerial);
        _runWirelessAction(args, res => {
            batchUpdate(() => {
                if (res.address)
                    Config.tablet.wirelessAddress = String(res.address);
                if (Config.tablet.deviceSerial && Config.tablet.deviceSerial !== String(res.address || ""))
                    Config.tablet.deviceSerial = "";
            });
            root.refreshDevices();
        });
    }

    function connectWireless(address) {
        const addr = String(address || Config.tablet.wirelessAddress || "").trim();
        if (!addr) {
            root.wirelessError = true;
            root.wirelessFeedback = "Enter an IP:port address first";
            return;
        }
        root._manualWifiDisconnect = false;
        if (Config.tablet.wirelessAddress !== addr)
            Config.tablet.wirelessAddress = addr;
        _runWirelessAction(["--connect", addr], res => {
            const finalAddr = String(res.address || addr);
            batchUpdate(() => {
                if (res.address)
                    Config.tablet.wirelessAddress = finalAddr;
                if (Config.tablet.deviceSerial && Config.tablet.deviceSerial !== finalAddr)
                    Config.tablet.deviceSerial = "";
                if (!Config.tablet.enabled)
                    Config.tablet.enabled = true;
            });
            root.refreshDevices();
        });
    }

    function disconnectWireless(address) {
        root._manualWifiDisconnect = true;
        if (Config.initialLoadComplete && root.enabled)
            runtimeFile.write(root.runtimeConfigJson);
        const activeWifi = root.transport === "wifi" ? root.deviceSerial : "";
        const addr = String(address || activeWifi || Config.tablet.wirelessAddress || "").trim();
        const args = addr ? ["--disconnect", addr] : ["--disconnect"];
        _runWirelessAction(args, () => {
            if (root.transport === "wifi")
                root.transport = "";
            root.refreshDevices();
        });
    }

    function toggleWireless() {
        if (root.wirelessBusy)
            return;
        if (root.transport === "wifi")
            disconnectWireless(root.deviceSerial || Config.tablet.wirelessAddress);
        else if (root.connected && root.transport === "usb")
            enableWireless();
        else if (Config.tablet.wirelessAddress)
            connectWireless(Config.tablet.wirelessAddress);
    }

    function pairWireless(address, code) {
        const addr = String(address || "").trim();
        const pin = String(code || "").trim();
        if (!addr || !pin) {
            root.wirelessError = true;
            root.wirelessFeedback = "Enter both pairing IP:port and 6-digit code";
            return;
        }
        _runWirelessAction(["--pair", addr, pin], null);
    }

    // Coalesce multi-property writes into one atomic save to avoid racing ConfigFile writes.
    function batchUpdate(fn) {
        Config.beginEdit("tablet-batch", ["tablet"]);
        try {
            fn();
        } finally {
            Config.save("tablet");
            Config.endEdit("tablet-batch");
        }
    }

    function selectScreen(monitorName) {
        batchUpdate(() => {
            Config.tablet.monitor = String(monitorName || "");
            Config.tablet.targetMode = "screen";
        });
    }

    function selectCentered(monitorName, width, height, matchLayout) {
        batchUpdate(() => {
            if (monitorName !== undefined)
                Config.tablet.monitor = String(monitorName || "");
            if (width > 0)
                Config.tablet.centeredWidth = Math.round(width);
            if (height > 0)
                Config.tablet.centeredHeight = Math.round(height);
            if (matchLayout !== undefined)
                Config.tablet.centeredMatchLayout = Boolean(matchLayout);
            Config.tablet.targetMode = "centered";
        });
    }

    function selectArea(x, y, width, height) {
        batchUpdate(() => {
            Config.tablet.areaX = Math.round(x);
            Config.tablet.areaY = Math.round(y);
            Config.tablet.areaWidth = Math.max(32, Math.round(width));
            Config.tablet.areaHeight = Math.max(32, Math.round(height));
            Config.tablet.targetMode = "area";
        });
    }

    function selectWindow(client) {
        if (!client)
            return;
        const addr = String(client.address || "");
        const cls = String(client["class"] || client.initialClass || "");
        const title = String(client.title || cls || "");
        const at = TabletUtils.pairOf(client.at);
        const size = TabletUtils.pairOf(client.size);
        batchUpdate(() => {
            Config.tablet.windowAddress = addr;
            Config.tablet.windowClass = cls;
            Config.tablet.windowTitle = title;
            if (at && size && size[0] > 0 && size[1] > 0) {
                Config.tablet.areaX = Math.round(at[0]);
                Config.tablet.areaY = Math.round(at[1]);
                Config.tablet.areaWidth = Math.max(32, Math.round(size[0]));
                Config.tablet.areaHeight = Math.max(32, Math.round(size[1]));
            }
            Config.tablet.targetMode = "window";
        });
    }

    function selectFocusedWindow() {
        batchUpdate(() => {
            Config.tablet.windowAddress = "";
            Config.tablet.windowClass = "";
            Config.tablet.windowTitle = "";
            Config.tablet.targetMode = "window";
        });
    }

    function focusTrackedWindow() {
        const win = TabletUtils.findTrackedWindow(Config.tablet, Compositor.clients.values, Compositor.focusedClient);
        if (win && win.address)
            Compositor.dispatch("focuswindow address:" + win.address);
    }

    function resetDefaults() {
        batchUpdate(() => {
            Config.tablet.inputMode = "pen";
            Config.tablet.targetMode = "centered";
            Config.tablet.centeredWidth = 2560;
            Config.tablet.centeredHeight = 1440;
            Config.tablet.centeredMatchLayout = false;
            Config.tablet.aspectMode = "fit-tablet";
            Config.tablet.areaScale = 1.0;
            Config.tablet.areaOffsetX = 0.0;
            Config.tablet.areaOffsetY = 0.0;
            Config.tablet.rotation = 0;
            Config.tablet.flipX = false;
            Config.tablet.flipY = false;
            Config.tablet.relativeMode = false;
            Config.tablet.pressureEnabled = true;
            Config.tablet.pressureGamma = 1.0;
            Config.tablet.pressureMin = 0.0;
            Config.tablet.pressureMax = 1.0;
            Config.tablet.tiltEnabled = true;
            Config.tablet.smoothing = 0;
            Config.tablet.eraserEnabled = true;
            Config.tablet.swapStylusButtons = false;
            Config.tablet.suppressPen = true;
            Config.tablet.suppressTouch = true;
            Config.tablet.keepAwake = true;
            Config.tablet.touchpadSpeed = 1.0;
            Config.tablet.touchpadAccelProfile = "adaptive";
            Config.tablet.touchpadScrollFactor = 1.0;
            Config.tablet.touchpadNaturalScroll = true;
            Config.tablet.touchpadTapToClick = true;
            Config.tablet.touchpadTapAndDrag = true;
            Config.tablet.touchpadDrag3fg = 0;
            Config.tablet.touchpadDisableWhileTyping = false;
            Config.tablet.touchpadPalmRejectMs = 350;
            Config.tablet.touchpadRotation = "auto";
        });
    }

    function applyHyprlandRegion(force) {
        if (!Config.initialLoadComplete || !root.enabled)
            return;
        const lua = TabletUtils.buildHyprlandLua(root.effectiveRegion, Boolean(Config.tablet?.relativeMode));
        if (!lua || (!force && lua === root._lastAppliedLua))
            return;
        root._lastAppliedLua = lua;
        Compositor.request("eval " + lua, reply => {
            if (reply.trim() !== "ok")
                console.warn("TabletService: Hyprland tablet config failed:", reply);
        });
    }

    function applyHyprlandTouchpad(force) {
        if (!Config.initialLoadComplete || !root.enabled)
            return;
        const mode = Config.tablet?.inputMode || "pen";
        if (mode === "pen")
            return;
        const lua = TabletUtils.buildHyprlandTouchpadLua(Config.tablet);
        if (!lua || (!force && lua === root._lastAppliedTouchpadLua))
            return;
        root._lastAppliedTouchpadLua = lua;
        Compositor.request("eval " + lua, reply => {
            if (reply.trim() !== "ok")
                console.warn("TabletService: Hyprland touchpad config failed:", reply);
        });
    }

    function clearPenState() {
        root.penInProx = false;
        root.penTouching = false;
        root.penPressure = 0;
        root.penRawPressure = 0;
        root.touchFingers = [];
    }

    function handleBridgeLine(line) {
        const trimmed = String(line || "").trim();
        if (!trimmed)
            return;
        let msg;
        try {
            msg = JSON.parse(trimmed);
        } catch (err) {
            return;
        }
        if (msg.type === "status") {
            root.state = String(msg.state || "waiting");
            root.statusMessage = String(msg.message || "");
            if (Array.isArray(msg.devices))
                root.availableDevices = msg.devices;
            if (msg.serial !== undefined)
                root.deviceSerial = String(msg.serial || "");
            if (msg.transport !== undefined)
                root.transport = String(msg.transport || "");
            if (msg.wifiIp !== undefined)
                root.wifiIp = String(msg.wifiIp || "");
            if (msg.model !== undefined)
                root.deviceModel = String(msg.model || "");
            if (msg.device !== undefined)
                root.digitizerName = String(msg.device || "");
            if (msg.eventPath !== undefined)
                root.eventPath = String(msg.eventPath || "");
            if (msg.grabActive !== undefined)
                root.grabActive = Boolean(msg.grabActive);
            if (msg.hasTouch !== undefined)
                root.hasTouch = Boolean(msg.hasTouch);
            if (msg.touchpadActive !== undefined)
                root.touchpadActive = Boolean(msg.touchpadActive);
            if (msg.maxX > 0)
                root.tabletMaxX = Number(msg.maxX);
            if (msg.maxY > 0)
                root.tabletMaxY = Number(msg.maxY);
            if (msg.maxPressure > 0)
                root.tabletMaxPressure = Number(msg.maxPressure);
            if (msg.hasTilt !== undefined)
                root.hasTilt = Boolean(msg.hasTilt);
            if (root.state === "connected") {
                root._restartFailures = 0;
                applyTimer.restart();
            } else {
                root.touchpadActive = false;
                root.clearPenState();
            }
        } else if (msg.type === "pen") {
            root.penInProx = Boolean(msg.inProx);
            root.penTouching = Boolean(msg.touching);
            root.penX = Number(msg.x ?? 0.5);
            root.penY = Number(msg.y ?? 0.5);
            root.penRawX = Number(msg.rawX ?? 0.5);
            root.penRawY = Number(msg.rawY ?? 0.5);
            root.penPressure = Number(msg.pressure ?? 0);
            root.penRawPressure = Number(msg.rawPressure ?? 0);
            root.penTiltX = Number(msg.tiltX ?? 0);
            root.penTiltY = Number(msg.tiltY ?? 0);
        } else if (msg.type === "touch") {
            root.touchFingers = Array.isArray(msg.fingers) ? msg.fingers : [];
        }
    }

    function reconcile() {
        if (!Config.initialLoadComplete)
            return;
        const shouldRun = root.enabled && !SuspendManager.isSuspending;
        if (!shouldRun) {
            restartTimer.stop();
            root._restartFailures = 0;
            root._lastAppliedLua = "";
            root._lastAppliedTouchpadLua = "";
            if (bridgeProcess.running) {
                root._stopping = true;
                bridgeProcess.running = false;
            }
            root.state = "off";
            root.statusMessage = "Disabled";
            root.deviceSerial = "";
            root.transport = "";
            root.wifiIp = "";
            root.grabActive = false;
            root.touchpadActive = false;
            root.clearPenState();
            return;
        }
        runtimeFile.write(root.runtimeConfigJson);
        applyTimer.restart();
        if (!bridgeProcess.running && !restartTimer.running) {
            root._stopping = false;
            if (root.state === "off") {
                root.state = "waiting";
                root.statusMessage = "Starting tablet bridge...";
            }
            bridgeProcess.command = ["python3", Paths.script("tablet_bridge.py"), "--config", root.runtimeConfigPath];
            bridgeProcess.running = true;
        }
    }

    function processExited(exitCode) {
        const expected = root._stopping || !root.enabled || SuspendManager.isSuspending;
        root._stopping = false;
        root.clearPenState();
        if (expected) {
            if (root.enabled && !SuspendManager.isSuspending)
                reconcile();
            return;
        }
        root._restartFailures = Math.min(10, root._restartFailures + 1);
        root.state = "error";
        root.statusMessage = "Bridge exited (code " + exitCode + "), retrying...";
        restartTimer.interval = Math.min(30000, 1000 * Math.pow(2, Math.min(4, root._restartFailures - 1)));
        restartTimer.restart();
    }

    GeneratedFile {
        id: runtimeFile
        path: root.runtimeConfigPath
    }

    Process {
        id: bridgeProcess
        running: false
        stdout: SplitParser {
            onRead: line => root.handleBridgeLine(line)
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim())
                    console.warn("TabletService:", line.trim());
            }
        }
        onExited: code => root.processExited(code)
    }

    Process {
        id: probeProcess
        running: false
        command: ["python3", Paths.script("tablet_bridge.py"), "--probe"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    if (Array.isArray(parsed.devices))
                        root.availableDevices = parsed.devices;
                } catch (err) {
                }
            }
        }
    }

    Process {
        id: wirelessProcess
        running: false
        property var onSuccessCallback: null
        property string outputText: ""
        property bool exited: false
        property bool streamDone: false
        property int exitCode: -1

        function finishIfReady() {
            if (!exited || !streamDone)
                return;
            root.wirelessBusy = false;
            let parsed = null;
            try {
                parsed = JSON.parse(wirelessProcess.outputText);
            } catch (err) {
                parsed = null;
            }
            const ok = exitCode === 0 && parsed && parsed.ok !== false;
            root.wirelessError = !ok;
            root.wirelessFeedback = (parsed && parsed.message) ? String(parsed.message) : (ok ? "Done" : "Wireless ADB action failed");
            if (ok && wirelessProcess.onSuccessCallback)
                wirelessProcess.onSuccessCallback(parsed);
            wirelessProcess.onSuccessCallback = null;
            wirelessProcess.outputText = "";
        }

        stdout: StdioCollector {
            onStreamFinished: {
                wirelessProcess.outputText = text.trim();
                wirelessProcess.streamDone = true;
                wirelessProcess.finishIfReady();
            }
        }
        onExited: code => {
            wirelessProcess.exitCode = code;
            wirelessProcess.exited = true;
            wirelessProcess.finishIfReady();
        }
    }

    Timer {
        id: restartTimer
        interval: 1500
        onTriggered: root.reconcile()
    }

    Timer {
        id: applyTimer
        interval: 40
        onTriggered: {
            root.applyHyprlandRegion(false);
            root.applyHyprlandTouchpad(false);
        }
    }

    Timer {
        id: writeTimer
        interval: 40
        onTriggered: {
            if (Config.initialLoadComplete && root.enabled)
                runtimeFile.write(root.runtimeConfigJson);
        }
    }

    onEnabledChanged: reconcile()
    onRuntimeConfigJsonChanged: if (Config.initialLoadComplete && root.enabled) writeTimer.restart()
    onEffectiveRegionChanged: if (Config.initialLoadComplete && root.enabled) applyTimer.restart()

    Connections {
        target: Config
        function onInitialLoadCompleteChanged() {
            if (Config.initialLoadComplete)
                root.reconcile();
        }
    }

    Connections {
        target: Config.tablet
        function onRelativeModeChanged() {
            if (Config.initialLoadComplete && root.enabled)
                applyTimer.restart();
        }
        function onInputModeChanged() {
            if (Config.initialLoadComplete && root.enabled)
                applyTimer.restart();
        }
        function onTouchpadNaturalScrollChanged() {
            if (Config.initialLoadComplete && root.enabled)
                applyTimer.restart();
        }
        function onTouchpadTapToClickChanged() {
            if (Config.initialLoadComplete && root.enabled)
                applyTimer.restart();
        }
        function onTouchpadTapAndDragChanged() {
            if (Config.initialLoadComplete && root.enabled)
                applyTimer.restart();
        }
        function onTouchpadScrollFactorChanged() {
            if (Config.initialLoadComplete && root.enabled)
                applyTimer.restart();
        }
        function onTouchpadDrag3fgChanged() {
            if (Config.initialLoadComplete && root.enabled)
                applyTimer.restart();
        }
        function onTouchpadDisableWhileTypingChanged() {
            if (Config.initialLoadComplete && root.enabled)
                applyTimer.restart();
        }
        function onTouchpadAccelProfileChanged() {
            if (Config.initialLoadComplete && root.enabled)
                applyTimer.restart();
        }
    }

    Connections {
        target: SuspendManager
        function onIsSuspendingChanged() {
            root.reconcile();
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && root.enabled) {
                root.applyHyprlandRegion(true);
                root.applyHyprlandTouchpad(true);
            }
        }
    }

    Component.onCompleted: {
        if (Config.initialLoadComplete)
            reconcile();
    }
}
