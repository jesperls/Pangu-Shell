import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.services
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

    readonly property bool isPrimaryGrabScreen: root.targetScreen?.name === (Compositor.focusedMonitor?.name || Quickshell.screens[0]?.name)
    readonly property string mode: GlobalStates.mousePickMode || "point"

    color: "transparent"
    visible: GlobalStates.mousePickActive
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "pangu:mouse-pick"
    WlrLayershell.keyboardFocus: GlobalStates.mousePickActive && root.isPrimaryGrabScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Eyedropper uses a zero-opacity surface so screen colors stay untinted while aiming.
    Rectangle {
        anchors.fill: parent
        color: Colors.scrim
        opacity: root.mode === "eyedropper" ? 0.0 : 0.22
    }

    Rectangle {
        visible: root.mode === "region" && pickMouse.selecting
        x: Math.min(pickMouse.startLocalX, pickMouse.curLocalX)
        y: Math.min(pickMouse.startLocalY, pickMouse.curLocalY)
        width: Math.abs(pickMouse.curLocalX - pickMouse.startLocalX)
        height: Math.abs(pickMouse.curLocalY - pickMouse.startLocalY)
        color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.16)
        border.width: 2
        border.color: Styling.srItem("overprimary")
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
            text: {
                if (GlobalStates.mousePickHint)
                    return GlobalStates.mousePickHint;
                if (root.mode === "region")
                    return qsTr("Drag to select area to watch — Esc or right-click to cancel");
                if (root.mode === "eyedropper")
                    return qsTr("Click any pixel to pick its color — Esc or right-click to cancel");
                return qsTr("Click where the macro should target — Esc or right-click to cancel");
            }
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            color: Colors.overBackground
        }
    }

    StyledRect {
        id: coordBadge
        visible: pickMouse.containsMouse
        variant: "popup"
        radius: Styling.radius(-4)
        implicitWidth: coordText.implicitWidth + 16
        implicitHeight: coordText.implicitHeight + 8
        x: Math.max(8, Math.min(root.width - implicitWidth - 8, pickMouse.curLocalX + 18))
        y: Math.max(8, Math.min(root.height - implicitHeight - 8, pickMouse.curLocalY + 18))

        Text {
            id: coordText
            anchors.centerIn: parent
            font.family: Config.theme.monoFont
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overBackground
            text: {
                const gx = Math.round(root.targetScreen.x + pickMouse.curLocalX);
                const gy = Math.round(root.targetScreen.y + pickMouse.curLocalY);
                if (root.mode === "region" && pickMouse.selecting) {
                    const sx = Math.round(root.targetScreen.x + pickMouse.startLocalX);
                    const sy = Math.round(root.targetScreen.y + pickMouse.startLocalY);
                    const rx = Math.min(sx, gx);
                    const ry = Math.min(sy, gy);
                    const rw = Math.abs(gx - sx);
                    const rh = Math.abs(gy - sy);
                    return rx + ", " + ry + " · " + rw + "×" + rh;
                }
                return gx + ", " + gy;
            }
        }
    }

    MouseArea {
        id: pickMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.CrossCursor

        property real startLocalX: 0
        property real startLocalY: 0
        property real curLocalX: 0
        property real curLocalY: 0
        property bool selecting: false

        onPressed: mouse => {
            curLocalX = mouse.x;
            curLocalY = mouse.y;
            if (mouse.button !== Qt.LeftButton) {
                selecting = false;
                GlobalStates.cancelMousePick();
                return;
            }
            if (root.mode === "region") {
                startLocalX = mouse.x;
                startLocalY = mouse.y;
                selecting = true;
            }
        }

        onPositionChanged: mouse => {
            curLocalX = mouse.x;
            curLocalY = mouse.y;
        }

        onReleased: mouse => {
            if (mouse.button !== Qt.LeftButton || root.mode !== "region" || !selecting)
                return;
            selecting = false;
            const sx = Math.round(root.targetScreen.x + startLocalX);
            const sy = Math.round(root.targetScreen.y + startLocalY);
            const ex = Math.round(root.targetScreen.x + mouse.x);
            const ey = Math.round(root.targetScreen.y + mouse.y);
            const rw = Math.abs(ex - sx);
            const rh = Math.abs(ey - sy);
            if (rw >= 2 && rh >= 2)
                GlobalStates.finishRegionPick(Math.min(sx, ex), Math.min(sy, ey), rw, rh);
        }

        onClicked: mouse => {
            if (root.mode === "region")
                return;
            if (mouse.button === Qt.LeftButton)
                GlobalStates.finishMousePick(Math.round(root.targetScreen.x + mouse.x), Math.round(root.targetScreen.y + mouse.y));
            else
                GlobalStates.cancelMousePick();
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: GlobalStates.mousePickActive
        onActivated: {
            pickMouse.selecting = false;
            GlobalStates.cancelMousePick();
        }
    }
}
