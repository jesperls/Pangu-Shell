import QtQuick
import Quickshell.Networking

QtObject {
    id: root

    required property WifiNetwork network

    readonly property bool active: network?.connected ?? false
    readonly property int strength: Math.round((network?.signalStrength ?? 0) * 100)
    readonly property string ssid: network?.name ?? ""
    readonly property bool isSecure: network ? network.security !== WifiSecurityType.Open && network.security !== WifiSecurityType.Unknown : false

    property bool askingPassword: false

    onActiveChanged: NetworkService.updateFriendlyList()
    onStrengthChanged: NetworkService.updateFriendlyList()
    onSsidChanged: NetworkService.updateFriendlyList()

    readonly property Connections failWatch: Connections {
        target: root.network
        function onConnectionFailed(reason) {
            if (reason === ConnectionFailReason.NoSecrets) {
                root.askingPassword = true;
            }
        }
    }
}
