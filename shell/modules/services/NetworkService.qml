pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking

Singleton {
    id: root

    readonly property var wifiDevice: (Networking.devices.values ?? []).find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDevice: {
        const devices = (Networking.devices.values ?? []).filter(d => d.type === DeviceType.Wired);
        return devices.find(d => d.connected) ?? devices[0] ?? null;
    }

    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool ethernet: wiredDevice?.connected ?? false
    readonly property bool wifi: (wifiDevice?.connected ?? false) && Networking.connectivity !== NetworkConnectivity.Limited

    readonly property string wifiStatus: {
        if (!wifiEnabled || !wifiDevice)
            return "disabled";
        switch (wifiDevice.state) {
        case ConnectionState.Connecting:
            return "connecting";
        case ConnectionState.Connected:
            return Networking.connectivity === NetworkConnectivity.Limited ? "limited" : "connected";
        default:
            return "disconnected";
        }
    }

    readonly property bool wifiConnecting: wifiStatus === "connecting"
    readonly property int networkStrength: active?.strength ?? 0

    property bool wifiScanning: false
    property var scanClients: []

    function setScanClient(client, enabled) {
        const clients = root.scanClients.filter(entry => entry !== client);
        root.scanClients = enabled ? clients.concat([client]) : clients;
    }

    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root.scanClients.length > 0 && root.wifiEnabled && !SuspendManager.isSuspending
        when: root.wifiDevice !== null
    }
    property list<var> friendlyWifiNetworks: []
    property var active: null

    property bool wasEnabledBeforeSleep: false

    property var suspendConnections: Connections {
        target: SuspendManager
        function onPreparingForSleep() {
            root.wasEnabledBeforeSleep = root.wifiEnabled;
        }
        function onWakingUp() {
            if (root.wasEnabledBeforeSleep) {
                root.enableWifi(true);
            }
        }
    }

    property var _wrapperMap: new Map()

    Component {
        id: apComp
        WifiAccessPoint {}
    }

    function updateFriendlyList() {
        syncDebounce.restart();
    }

    Timer {
        id: syncDebounce
        interval: 50
        repeat: false
        onTriggered: root._syncNetworks()
    }

    function _syncNetworks() {
        const nets = wifiDevice?.networks.values ?? [];
        for (const [nat, wrap] of Array.from(_wrapperMap.entries())) {
            if (nets.indexOf(nat) === -1) {
                _wrapperMap.delete(nat);
                wrap.destroy();
            }
        }
        for (const nat of nets) {
            if (!_wrapperMap.has(nat)) {
                _wrapperMap.set(nat, apComp.createObject(root, {
                    network: nat
                }));
            }
        }
        const wrappers = nets.map(n => _wrapperMap.get(n)).filter(w => w.ssid);
        wrappers.sort((a, b) => {
            if (a.active && !b.active)
                return -1;
            if (!a.active && b.active)
                return 1;
            return b.strength - a.strength;
        });
        friendlyWifiNetworks = wrappers;
        active = wrappers.find(w => w.active) ?? null;
    }

    Connections {
        target: root.wifiDevice?.networks ?? null
        function onValuesChanged() {
            root.updateFriendlyList();
        }
    }

    onWifiDeviceChanged: updateFriendlyList()

    Timer {
        id: scanPulse
        interval: 4000
        repeat: false
        onTriggered: root.wifiScanning = false
    }

    function rescanWifi(): void {
        if (!wifiDevice || !wifiEnabled)
            return;
        wifiScanning = true;
        scanPulse.restart();
        updateFriendlyList();
    }

    function enableWifi(enabled = true): void {
        Networking.wifiEnabled = enabled;
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        accessPoint.network.connect();
    }

    function disconnectWifiNetwork(): void {
        active?.network.disconnect();
    }

    function changePassword(network: WifiAccessPoint, password: string): void {
        network.askingPassword = false;
        network.network.connectWithPsk(password);
    }

    function openPublicWifiPortal() {
        ApplicationLauncher.launchCommand(["xdg-open", "https://nmcheck.gnome.org/"]);
    }
}
