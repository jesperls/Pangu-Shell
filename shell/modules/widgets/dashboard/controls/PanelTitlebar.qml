pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.config

RowLayout {
    id: root

    property string title: ""
    property string statusText: ""
    property color statusColor: Styling.srItem("overprimary")
    property bool showToggle: false
    property bool toggleChecked: false

    property var actions: []


    signal toggleChanged(bool checked)

    Layout.fillWidth: true
    Layout.preferredHeight: 36
    spacing: 8

    Text {
        text: root.title
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(0)
        font.weight: Font.Medium
        color: Colors.overBackground
    }

    Text {
        visible: root.statusText !== ""
        text: root.statusText
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-2)
        color: root.statusColor
    }

    Item {
        Layout.fillWidth: true
    }

    Repeater {
        model: root.actions

        delegate: Button {
            id: actionButton
            required property var modelData
            required property int index
            flat: true
            implicitWidth: 28
            implicitHeight: 28
            enabled: (modelData.enabled !== undefined ? modelData.enabled : true) && !(modelData.loading ?? false)

            property bool isLoading: modelData.loading ?? false

            background: StyledRect {
                variant: actionButton.hovered ? "focus" : "common"
                radius: Styling.radius(-4)
            }

            contentItem: Text {
                id: iconText
                text: actionButton.modelData.icon || ""
                font.family: Icons.font
                font.pixelSize: 14
                color: actionButton.isLoading ? Styling.srItem("overprimary") : (actionButton.enabled ? Colors.overBackground : Colors.outline)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                RotationAnimation on rotation {
                    running: actionButton.isLoading
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }

            onClicked: {
                if (actionButton.modelData.onClicked) {
                    actionButton.modelData.onClicked();
                }
            }

            StyledToolTip {
                visible: actionButton.hovered && actionButton.modelData.tooltip
                tooltipText: actionButton.modelData.tooltip || ""
            }
        }
    }

    Switch {
        id: toggleSwitch
        visible: root.showToggle
        checked: root.toggleChecked
        onCheckedChanged: root.toggleChanged(checked)

        indicator: Rectangle {
            implicitWidth: 40
            implicitHeight: 20
            x: toggleSwitch.leftPadding
            y: parent.height / 2 - height / 2
            radius: height / 2
            color: toggleSwitch.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
            border.color: toggleSwitch.checked ? Styling.srItem("overprimary") : Colors.outline

            Behavior on color {
                enabled: Styling.animDuration > 0
                ColorAnimation {
                    duration: Styling.animDuration / 2
                }
            }

            Rectangle {
                x: toggleSwitch.checked ? parent.width - width - 2 : 2
                y: 2
                width: parent.height - 4
                height: width
                radius: width / 2
                color: toggleSwitch.checked ? Colors.background : Colors.overSurfaceVariant

                Behavior on x {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
        background: null
    }
}
