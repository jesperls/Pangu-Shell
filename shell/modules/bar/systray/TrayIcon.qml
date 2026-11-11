import QtQuick
import Quickshell.Widgets
import qs.config
import qs.modules.components
import qs.modules.theme

Item {
    id: root
    required property var item
    property bool hovered: false
    property int iconSize: Math.max(16, Math.min(32, Config.bar.trayIconSize ?? 20))
    implicitWidth: iconSize
    implicitHeight: iconSize
    opacity: hovered || Config.bar.trayIconStyle === "original" ? 1.0 : 0.86

    Behavior on opacity {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration / 2
        }
    }

    IconImage {
        id: icon
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        source: root.item?.icon ?? ""
        smooth: true
    }

    Tinted {
        anchors.fill: icon
        sourceItem: icon
        active: Config.bar.trayIconStyle === "monochrome" || (Config.bar.trayIconStyle !== "original" && Config.tintIcons)
        fullTint: Config.bar.trayIconStyle === "monochrome"
    }
}
