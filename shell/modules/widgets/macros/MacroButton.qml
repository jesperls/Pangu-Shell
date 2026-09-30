import QtQuick
import qs.modules.theme
import qs.modules.components
import qs.config

StyledRect {
    id: root

    property string text: ""
    property string icon: ""
    property string tone: "common" // common | primary | danger
    property bool enabled: true
    signal clicked

    readonly property bool hovered: mouse.containsMouse
    readonly property color foreground: root.enabled ? root.item : Colors.outline

    variant: {
        if (!root.enabled)
            return "common";
        if (root.tone === "primary")
            return root.hovered ? "primaryfocus" : "primary";
        if (root.tone === "danger")
            return root.hovered ? "errorfocus" : "error";
        return root.hovered ? "focus" : "common";
    }

    implicitWidth: content.implicitWidth + 24
    implicitHeight: 36
    radius: Styling.radius(-2)
    opacity: root.enabled ? 1.0 : 0.5

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            text: root.icon
            font.family: Icons.font
            font.pixelSize: 14
            color: root.foreground
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.text !== ""
            text: root.text
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            font.bold: true
            color: root.foreground
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
