import QtQuick
import qs.modules.theme
import qs.modules.components
import qs.config

Rectangle {
    id: root
    property bool active: false
    property int buttonIndex: 0
    property bool alignTop: false
    property string tone: "error"
    signal buttonIndexRequested(int index)
    signal cancelRequested
    signal confirmRequested
    anchors.right: parent.right
    anchors.top: root.alignTop ? parent.top : undefined
    anchors.topMargin: root.alignTop ? 8 : 0
    anchors.verticalCenter: root.alignTop ? undefined : parent.verticalCenter
    anchors.rightMargin: 8
    width: 68
    height: 32
    color: "transparent"
    opacity: root.active ? 1.0 : 0.0
    visible: opacity > 0

    transform: Translate {
        x: root.active ? 0 : 80

        Behavior on x {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration
                easing.type: Easing.OutQuart
            }
        }
    }

    Behavior on opacity {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration / 2
            easing.type: Easing.OutQuart
        }
    }

    StyledRect {
        id: deleteHighlight
        variant: root.tone === "secondary" ? "oversecondary" : "overerror"
        radius: Styling.radius(-4)
        visible: root.active
        z: 0

        property real activeButtonMargin: 2
        property real idx1X: root.buttonIndex
        property real idx2X: root.buttonIndex

        x: {
            let minX = Math.min(idx1X, idx2X) * 36 + activeButtonMargin;
            return minX;
        }

        y: activeButtonMargin

        width: {
            let stretchX = Math.abs(idx1X - idx2X) * 36 + 32 - activeButtonMargin * 2;
            return stretchX;
        }

        height: 32 - activeButtonMargin * 2

        Behavior on idx1X {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration / 3
                easing.type: Easing.OutSine
            }
        }
        Behavior on idx2X {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration
                easing.type: Easing.OutSine
            }
        }
    }

    Row {
        id: actionButtons
        anchors.fill: parent
        spacing: 4

        Rectangle {
            id: cancelButton
            width: 32
            height: 32
            color: "transparent"
            radius: 6
            border.width: 0
            border.color: Colors.outline
            z: 1

            property bool isHighlighted: root.buttonIndex === 0

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.cancelRequested()
                onEntered: {
                    root.buttonIndexRequested(0);
                }
                onExited: parent.color = "transparent"
            }

            Text {
                anchors.centerIn: parent
                text: Icons.cancel
                color: cancelButton.isHighlighted ? (root.tone === "secondary" ? Colors.overSecondaryContainer : Colors.overErrorContainer) : (root.tone === "secondary" ? Colors.overSecondary : Colors.overError)
                font.pixelSize: 14
                font.family: Icons.font
                textFormat: Text.RichText

                Behavior on color {
                    enabled: Styling.animDuration > 0
                    ColorAnimation {
                        duration: Styling.animDuration / 2
                        easing.type: Easing.OutQuart
                    }
                }
            }
        }

        Rectangle {
            id: confirmButton
            width: 32
            height: 32
            color: "transparent"
            radius: 6
            z: 1

            property bool isHighlighted: root.buttonIndex === 1

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.confirmRequested()
                onEntered: {
                    root.buttonIndexRequested(1);
                }
                onExited: parent.color = "transparent"
            }

            Text {
                anchors.centerIn: parent
                text: Icons.accept
                color: confirmButton.isHighlighted ? (root.tone === "secondary" ? Colors.overSecondaryContainer : Colors.overErrorContainer) : (root.tone === "secondary" ? Colors.overSecondary : Colors.overError)
                font.pixelSize: 14
                font.family: Icons.font
                textFormat: Text.RichText

                Behavior on color {
                    enabled: Styling.animDuration > 0
                    ColorAnimation {
                        duration: Styling.animDuration / 2
                        easing.type: Easing.OutQuart
                    }
                }
            }
        }
    }
}
