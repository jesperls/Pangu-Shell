import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.modules.components

Item {
    id: root
    required property var item
    property int iconSize: Math.max(16, Math.min(32, Config.bar.trayIconSize ?? 20))
    implicitWidth: iconSize
    implicitHeight: iconSize

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
