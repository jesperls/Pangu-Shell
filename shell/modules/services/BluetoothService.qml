pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.modules.globals

Singleton {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter

    readonly property bool enabled: adapter?.enabled ?? false
    readonly property bool discovering: adapter?.discovering ?? false
    readonly property int connectedDevices: {
        _rev;
        return (adapter?.devices.values ?? []).filter(d => d.connected).length;
    }
    readonly property bool connected: connectedDevices > 0

    property int _rev: 0

    readonly property var friendlyDeviceList: {
        _rev;
        return [...(adapter?.devices.values ?? [])].sort((a, b) => {
            if (a.connected && !b.connected)
                return -1;
            if (!a.connected && b.connected)
                return 1;
            if (a.paired && !b.paired)
                return -1;
            if (!a.paired && b.paired)
                return 1;
            return (a.name || "").localeCompare(b.name || "");
        });
    }

    property bool wasEnabledBeforeSleep: false

    property var suspendConnections: Connections {
        target: SuspendManager
        function onPreparingForSleep() {
            root.wasEnabledBeforeSleep = root.enabled;
            root.stopDiscovery();
        }
        function onWakingUp() {
            if (root.wasEnabledBeforeSleep) {
                root.setEnabled(true);
            }
        }
    }

    Variants {
        model: root.adapter ? [...root.adapter.devices.values] : []

        QtObject {
            id: watcher
            required property var modelData
            readonly property Connections conn: Connections {
                target: watcher.modelData
                function onConnectedChanged() {
                    root._rev++;
                }
                function onPairedChanged() {
                    root._rev++;
                }
                function onNameChanged() {
                    root._rev++;
                }
            }
        }
    }

    Timer {
        id: scanTimer
        interval: 15000
        repeat: false
        onTriggered: root.stopDiscovery()
    }

    function initialize() {
    }

    function setEnabled(value: bool): void {
        if (adapter && !SuspendManager.isSuspending) {
            adapter.enabled = value;
        }
    }

    function toggle(): void {
        setEnabled(!enabled);
    }

    function startDiscovery(): void {
        if (adapter && enabled && !SuspendManager.isSuspending) {
            adapter.discovering = true;
            scanTimer.restart();
        }
    }

    function stopDiscovery(): void {
        if (adapter) {
            adapter.discovering = false;
        }
        scanTimer.stop();
    }

    function updateDevices(): void {
        _rev++;
    }

    function connectDevice(device: BluetoothDevice): void {
        device.trusted = true;
        device.connect();
    }
}
