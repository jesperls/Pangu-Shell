import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Services.SystemTray
import qs.config
import qs.modules.theme
import qs.modules.components
import qs.modules.services

StyledRect {
    variant: root.flatStyle ? "transparent" : "bg"
    id: root

    visible: hasItems

    property bool flatStyle: false

    topLeftRadius: root.startRadius
    topRightRadius: root.vertical ? root.startRadius : root.endRadius
    bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
    bottomRightRadius: root.endRadius

    required property var bar
    
    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    property bool vertical: bar.orientation === "vertical"

    readonly property bool hasItems: TrayService.items.length > 0
    readonly property int iconSize: Math.max(16, Math.min(32, Config.bar.trayIconSize ?? 20))
    readonly property int iconSpacing: Math.max(0, Math.min(24, Config.bar.traySpacing ?? 8))
    property bool managing: false

    height: vertical ? implicitHeight : parent.height
    Layout.preferredWidth: implicitWidth
    implicitWidth: hasItems ? itemsLayout.implicitWidth + 16 : 0
    implicitHeight: hasItems ? itemsLayout.implicitHeight + 16 : 0

    GridLayout {
        id: itemsLayout
        anchors.fill: parent
        anchors.margins: 8
        columns: root.vertical ? 1 : trayRepeater.count + 1
        rowSpacing: root.iconSpacing
        columnSpacing: root.iconSpacing

        Repeater {
            id: trayRepeater
            model: TrayService.visibleItems

            SysTrayItem {
                required property SystemTrayItem modelData
                bar: root.bar
                item: modelData
            }
        }

        Button {
            id: overflowButton
            objectName: "trayOverflow"
            implicitWidth: root.iconSize
            implicitHeight: root.iconSize
            hoverEnabled: true
            Accessible.name: "System tray overflow"
            onClicked: {
                root.managing = TrayService.hiddenItems.length === 0;
                overflowPopup.toggle();
            }

            background: Rectangle {
                color: Colors.overBackground
                opacity: overflowButton.down ? 0.15 : overflowButton.hovered ? 0.08 : 0
                radius: Styling.radius(-2)
            }

            contentItem: Text {
                text: Icons.caretRight
                font.family: Icons.font
                font.pixelSize: 16
                color: overflowPopup.isOpen ? Colors.primary : Colors.overSurfaceVariant
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                rotation: (root.bar.barPosition === "top" ? 90 : root.bar.barPosition === "bottom" ? -90
                    : root.bar.barPosition === "right" ? 180 : 0) + (overflowPopup.isOpen ? 180 : 0)
                Behavior on rotation {
                    enabled: Styling.animDuration > 0
                    NumberAnimation { duration: Styling.animDuration / 2; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: { root.managing = true; overflowPopup.open(); }
            }

            StyledToolTip {
                show: overflowButton.hovered && !overflowPopup.isOpen
                tooltipText: TrayService.hiddenItems.length ? "Hidden tray icons" : "Manage tray icons"
                description: "Right-click to choose which icons appear in the bar"
            }
        }
    }

    BarPopup {
        id: overflowPopup
        anchorItem: overflowButton
        bar: root.bar
        popupPadding: 12
        contentWidth: root.managing ? 264 : 4 * 44 + 3 * 8 + 24
        contentHeight: 44 + (root.managing ? Math.min(TrayService.items.length * 44, 352)
            : Math.ceil(TrayService.hiddenItems.length / 4) * 52) + 24

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.managing ? "System tray" : "Hidden apps"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    font.weight: Font.DemiBold
                    color: Colors.overBackground
                    Layout.fillWidth: true
                }
                Button {
                    text: root.managing ? "Done" : "Edit"
                    implicitHeight: 28
                    onClicked: {
                        if (root.managing && !TrayService.hiddenItems.length) overflowPopup.close();
                        else root.managing = !root.managing;
                    }
                    background: StyledRect { variant: parent.hovered ? "focus" : "common"; radius: Styling.radius(-2) }
                    contentItem: Text {
                        text: parent.text
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: overflowPopup.visible
                sourceComponent: root.managing ? managementComponent : hiddenComponent
            }
        }
    }

    Component {
        id: hiddenComponent
        GridLayout {
            columns: 4
            columnSpacing: 8
            rowSpacing: 8
            Repeater {
                model: TrayService.hiddenItems
                delegate: StyledRect {
                    id: hiddenTile
                    required property SystemTrayItem modelData
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    variant: trayItem.containsMouse ? "focus" : "common"
                    radius: Styling.radius(0)
                    SysTrayItem {
                        id: trayItem
                        anchors.fill: parent
                        item: hiddenTile.modelData
                        bar: root.bar
                        popupGroup: "tray-menu-" + (root.bar.screenName ?? "")
                        ownerPopup: overflowPopup
                        onActivated: overflowPopup.close()
                    }
                }
            }
        }
    }

    Component {
        id: managementComponent
        ListView {
            objectName: "trayManagement"
            clip: true
            model: TrayService.items
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: CheckDelegate {
                required property SystemTrayItem modelData
                width: ListView.view.width
                height: 44
                checked: !TrayService.isHidden(modelData)
                onClicked: TrayService.setHidden(modelData, !checked)
                Accessible.name: "Show " + (modelData.title || modelData.id) + " in the bar"
                background: StyledRect { variant: parent.hovered ? "focus" : "transparent"; radius: Styling.radius(-2) }
                contentItem: RowLayout {
                    spacing: 12
                    TrayIcon { item: parent.parent.modelData }
                    Text {
                        text: parent.parent.modelData.title || parent.parent.modelData.id
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                indicator: Text {
                    x: parent.width - width - 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.checked ? Icons.accept : Icons.unpin
                    color: parent.checked ? Colors.primary : Colors.overSurfaceVariant
                    font.family: Icons.font
                    font.pixelSize: 16
                }
                rightPadding: 32
            }
        }
    }
}
