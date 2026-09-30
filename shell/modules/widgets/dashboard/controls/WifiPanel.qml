pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    property bool scanReady: false
    Component.onCompleted: {
        scanReady = true;
        updateScanning();
    }
    Component.onDestruction: NetworkService.setScanClient(root, false)
    onVisibleChanged: if (scanReady) updateScanning()

    function updateScanning() {
        NetworkService.setScanClient(root, visible);
        if (visible) initialScanTimer.restart();
        else initialScanTimer.stop();
    }

    Timer {
        id: initialScanTimer
        interval: 300
        repeat: false
        onTriggered: NetworkService.rescanWifi()
    }

    ListView {
        id: networkList
        anchors.fill: parent
        clip: true
        spacing: 4
        cacheBuffer: 1000
        reuseItems: true

        model: NetworkService.friendlyWifiNetworks

        header: Item {
            width: networkList.width
            height: titlebar.height + 8

            PanelTitlebar {
                id: titlebar
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                title: NetworkService.wifiDevice ? "Wi-Fi" : "Network"
                statusText: NetworkService.ethernet ? "Ethernet connected" : (NetworkService.wifiConnecting ? "Connecting..." : (NetworkService.wifiStatus === "limited" ? "Limited" : ""))
                statusColor: NetworkService.wifiStatus === "limited" ? Colors.warning : Styling.srItem("overprimary")
                showToggle: NetworkService.wifiDevice !== null
                toggleChecked: NetworkService.wifiStatus !== "disabled"

                actions: [
                    {
                        icon: Icons.globe,
                        tooltip: "Open captive portal",
                        enabled: NetworkService.wifiStatus === "limited",
                        onClicked: function () {
                            NetworkService.openPublicWifiPortal();
                        }
                    },
                    {
                        icon: Icons.popOpen,
                        tooltip: "Network settings",
                        onClicked: function () {
                            ApplicationLauncher.launchCommand(["nm-connection-editor"]);
                        }
                    },
                    {
                        icon: Icons.sync,
                        tooltip: "Rescan networks",
                        enabled: NetworkService.wifiEnabled && NetworkService.wifiDevice !== null,
                        loading: NetworkService.wifiScanning,
                        onClicked: function () {
                            NetworkService.rescanWifi();
                        }
                    }
                ]

                onToggleChanged: checked => {
                    NetworkService.enableWifi(checked);
                    if (checked) {
                        NetworkService.rescanWifi();
                    }
                }
            }
        }

        delegate: Item {
            required property var modelData
            width: networkList.width
            height: networkItem.height

            WifiNetworkItem {
                id: networkItem
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                network: parent.modelData
            }
        }

        Text {
            anchors.centerIn: parent
            visible: networkList.count === 0 && !NetworkService.wifiScanning
            text: !NetworkService.wifiDevice ? "No Wi-Fi adapter detected" : (NetworkService.wifiEnabled ? "No Wi-Fi networks found" : "Wi-Fi is disabled")
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            color: Colors.overSurfaceVariant
        }
    }
}
