import QtQuick
import qs.modules.theme
import qs.modules.components
import qs.config

StyledRect {
    id: root

    property string icon: ""
    property string tooltip: ""
    property string tone: "ghost" // ghost | common | primary | danger
    property bool enabled: true
    property int size: 30
    property int iconSize: 15
    signal clicked

    readonly property bool hovered: mouse.containsMouse
    readonly property color foreground: {
        if (!root.enabled)
            return Colors.outline;
        if (root.tone === "danger" && !root.hovered)
            return Colors.error;
        if (root.tone === "ghost" && !root.hovered)
            return Colors.overSurfaceVariant;
        return root.item;
    }

    variant: {
        if (!root.enabled)
            return "common";
        if (root.tone === "primary")
            return root.hovered ? "primaryfocus" : "primary";
        if (root.tone === "danger")
            return root.hovered ? "errorfocus" : "transparent";
        if (root.tone === "ghost")
            return root.hovered ? "focus" : "transparent";
        return root.hovered ? "focus" : "common";
    }

    implicitWidth: size
    implicitHeight: size
    radius: Styling.radius(-6)
    opacity: root.enabled ? 1.0 : 0.5

    Text {
        anchors.centerIn: parent
        text: root.icon
        font.family: Icons.font
        font.pixelSize: root.iconSize
        color: root.foreground
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    StyledToolTip {
        show: mouse.containsMouse && root.tooltip !== ""
        tooltipText: root.tooltip
    }
}
