import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.components
import qs.config

PanelWindow {
    id: root

    required property var targetScreen
    screen: targetScreen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    visible: GlobalStates.mousePickActive
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: GlobalStates.mousePickActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: Colors.scrim
        opacity: 0.25
    }

    StyledRect {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 48
        variant: "popup"
        radius: Styling.radius(0)
        implicitWidth: hint.implicitWidth + 24
        implicitHeight: hint.implicitHeight + 16

        Text {
            id: hint
            anchors.centerIn: parent
            text: qsTr("Click where the macro should press — Esc or right-click to cancel")
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            color: Colors.overBackground
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.CrossCursor
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                GlobalStates.finishMousePick(Math.round(root.targetScreen.x + mouse.x), Math.round(root.targetScreen.y + mouse.y));
            else
                GlobalStates.cancelMousePick();
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: GlobalStates.mousePickActive
        onActivated: GlobalStates.cancelMousePick()
    }
}
