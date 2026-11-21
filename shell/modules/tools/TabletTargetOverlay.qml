pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.theme

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
    readonly property string mode: GlobalStates.tabletPickMode || "area"
    readonly property var monitorInfo: Compositor.monitorFor(root.targetScreen)
    readonly property real screenOriginX: root.monitorInfo ? root.monitorInfo.x : (root.targetScreen?.x ?? 0)
    readonly property real screenOriginY: root.monitorInfo ? root.monitorInfo.y : (root.targetScreen?.y ?? 0)
    readonly property var screenWindows: {
        const mon = root.monitorInfo;
        const clients = Compositor.clients.values || [];
        if (!mon)
            return [];
        const visibleWs = [];
        if (mon.activeWorkspace)
            visibleWs.push(mon.activeWorkspace.id);
        if (mon.activeSpecialWorkspace)
            visibleWs.push(mon.activeSpecialWorkspace.id);
        return clients
            .filter(c => {
                if (!c || c.mapped === false || c.hidden || c.title === "Pangu Settings")
                    return false;
                const onScreen = c.pinned || (c.workspace && visibleWs.indexOf(c.workspace.id) !== -1);
                if (!onScreen)
                    return false;
                return Boolean(c.at && c.at.length >= 2 && c.size && c.size.length >= 2 && Number(c.size[0]) > 0 && Number(c.size[1]) > 0);
            })
            .slice()
            .sort((a, b) => {
                if (Boolean(a.floating) !== Boolean(b.floating))
                    return a.floating ? 1 : -1;
                return (Number(b.focusHistoryID) || 0) - (Number(a.focusHistoryID) || 0);
            });
    }

    color: "transparent"
    visible: GlobalStates.tabletPickActive
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "pangu:tablet-pick"
    WlrLayershell.keyboardFocus: GlobalStates.tabletPickActive && root.isPrimaryGrabScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: Colors.scrim
        opacity: root.mode === "screen" && screenHover.containsMouse ? 0.14 : 0.28
    }

    // Current mapped region outline for spatial reference while picking.
    Rectangle {
        readonly property var r: TabletService.effectiveRegion
        visible: Boolean(r && r.width > 0 && r.height > 0)
            && (r.globalX + r.width > root.screenOriginX)
            && (r.globalX < root.screenOriginX + root.width)
            && (r.globalY + r.height > root.screenOriginY)
            && (r.globalY < root.screenOriginY + root.height)
        x: (r?.globalX ?? 0) - root.screenOriginX
        y: (r?.globalY ?? 0) - root.screenOriginY
        width: r?.width ?? 0
        height: r?.height ?? 0
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(Colors.secondary.r, Colors.secondary.g, Colors.secondary.b, 0.65)
    }

    // Screen mode border highlight.
    Rectangle {
        anchors.fill: parent
        visible: root.mode === "screen" && screenHover.containsMouse
        color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.12)
        border.width: 3
        border.color: Styling.srItem("overprimary")

        StyledRect {
            anchors.centerIn: parent
            variant: "popup"
            radius: Styling.radius(0)
            implicitWidth: screenLabel.implicitWidth + 28
            implicitHeight: screenLabel.implicitHeight + 18

            Text {
                id: screenLabel
                anchors.centerIn: parent
                text: (root.targetScreen?.name || "Screen") + "  ·  " + Math.round(root.width) + " × " + Math.round(root.height)
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.fontSize(1)
                font.weight: Font.Bold
                color: Colors.overBackground
            }
        }
    }

    // Area drag selection rectangle.
    Rectangle {
        id: dragRect
        visible: root.mode === "area" && areaMouse.selecting
        x: Math.min(areaMouse.startX, areaMouse.curX)
        y: Math.min(areaMouse.startY, areaMouse.curY)
        width: Math.abs(areaMouse.curX - areaMouse.startX)
        height: Math.abs(areaMouse.curY - areaMouse.startY)
        color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.18)
        border.width: 2
        border.color: Styling.srItem("overprimary")
    }

    // Screen mode click handler.
    MouseArea {
        id: screenHover
        anchors.fill: parent
        visible: root.mode === "screen"
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                GlobalStates.cancelTabletPick();
                return;
            }
            TabletService.selectScreen(root.targetScreen.name);
            GlobalStates.finishTabletPick();
        }
    }

    // Area mode drag handler.
    MouseArea {
        id: areaMouse
        anchors.fill: parent
        visible: root.mode === "area"
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor

        property real startX: 0
        property real startY: 0
        property real curX: 0
        property real curY: 0
        property bool selecting: false

        function clampX(v) {
            return Math.max(0, Math.min(root.width, v));
        }

        function clampY(v) {
            return Math.max(0, Math.min(root.height, v));
        }

        onPressed: mouse => {
            curX = clampX(mouse.x);
            curY = clampY(mouse.y);
            if (mouse.button !== Qt.LeftButton) {
                selecting = false;
                GlobalStates.cancelTabletPick();
                return;
            }
            startX = curX;
            startY = curY;
            selecting = true;
        }

        onPositionChanged: mouse => {
            curX = clampX(mouse.x);
            curY = clampY(mouse.y);
        }

        onReleased: mouse => {
            if (mouse.button !== Qt.LeftButton || !selecting)
                return;
            selecting = false;
            const ex = clampX(mouse.x);
            const ey = clampY(mouse.y);
            const gx1 = Math.round(root.screenOriginX + startX);
            const gy1 = Math.round(root.screenOriginY + startY);
            const gx2 = Math.round(root.screenOriginX + ex);
            const gy2 = Math.round(root.screenOriginY + ey);
            const rw = Math.abs(gx2 - gx1);
            const rh = Math.abs(gy2 - gy1);
            if (rw >= 24 && rh >= 24) {
                TabletService.selectArea(Math.min(gx1, gx2), Math.min(gy1, gy2), rw, rh);
                GlobalStates.finishTabletPick();
            }
        }
    }

    // Window mode clickable window targets.
    Item {
        anchors.fill: parent
        visible: root.mode === "window"

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: GlobalStates.cancelTabletPick()
        }

        Repeater {
            model: root.screenWindows
            delegate: Rectangle {
                id: winTarget
                required property var modelData
                readonly property real originX: root.monitorInfo ? root.monitorInfo.x : root.targetScreen.x
                readonly property real originY: root.monitorInfo ? root.monitorInfo.y : root.targetScreen.y
                x: Number(modelData.at[0] || 0) - originX
                y: Number(modelData.at[1] || 0) - originY
                width: Number(modelData.size[0] || 0)
                height: Number(modelData.size[1] || 0)
                color: winMouse.containsMouse ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.22) : "transparent"
                border.width: winMouse.containsMouse ? 2 : 1
                border.color: winMouse.containsMouse ? Styling.srItem("overprimary") : Qt.rgba(Colors.outline.r, Colors.outline.g, Colors.outline.b, 0.5)

                StyledRect {
                    visible: winMouse.containsMouse && winTarget.width >= 60 && winTarget.height >= 36
                    anchors.centerIn: parent
                    variant: "popup"
                    radius: Styling.radius(-2)
                    implicitWidth: Math.max(40, Math.min(winTarget.width - 16, winCaption.implicitWidth + 24))
                    implicitHeight: winCaption.implicitHeight + 14

                    Text {
                        id: winCaption
                        anchors.centerIn: parent
                        width: Math.max(0, Math.min(implicitWidth, winTarget.width - 40))
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        text: (winTarget.modelData.title || winTarget.modelData["class"] || "Window") + "  ·  " + winTarget.width + "×" + winTarget.height
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overBackground
                    }
                }

                MouseArea {
                    id: winMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            GlobalStates.cancelTabletPick();
                            return;
                        }
                        TabletService.selectWindow(winTarget.modelData);
                        GlobalStates.finishTabletPick();
                    }
                }
            }
        }
    }

    // Live coordinate badge in area mode.
    StyledRect {
        visible: root.mode === "area" && areaMouse.containsMouse
        variant: "popup"
        radius: Styling.radius(-4)
        implicitWidth: badgeText.implicitWidth + 16
        implicitHeight: badgeText.implicitHeight + 8
        x: Math.max(8, Math.min(root.width - implicitWidth - 8, areaMouse.curX + 18))
        y: Math.max(8, Math.min(root.height - implicitHeight - 8, areaMouse.curY + 18))

        Text {
            id: badgeText
            anchors.centerIn: parent
            font.family: Config.theme.monoFont
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overBackground
            text: {
                const gx = Math.round(root.screenOriginX + areaMouse.curX);
                const gy = Math.round(root.screenOriginY + areaMouse.curY);
                if (areaMouse.selecting) {
                    const sx = Math.round(root.screenOriginX + areaMouse.startX);
                    const sy = Math.round(root.screenOriginY + areaMouse.startY);
                    return Math.min(sx, gx) + ", " + Math.min(sy, gy) + "  ·  " + Math.abs(gx - sx) + " × " + Math.abs(gy - sy);
                }
                return gx + ", " + gy;
            }
        }
    }

    // Top hint pill.
    StyledRect {
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 44
        variant: "popup"
        radius: Styling.radius(0)
        implicitWidth: hintText.implicitWidth + 28
        implicitHeight: hintText.implicitHeight + 16

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }

        Text {
            id: hintText
            anchors.centerIn: parent
            text: {
                if (root.mode === "window")
                    return "Click a window to bind tablet area — Esc or right-click to cancel";
                if (root.mode === "screen")
                    return "Click a monitor to map tablet to full screen — Esc or right-click to cancel";
                return "Drag to select tablet drawing area — Esc or right-click to cancel";
            }
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            color: Colors.overBackground
        }
    }

    // Bottom mode selector pill.
    StyledRect {
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 44
        variant: "popup"
        radius: Styling.radius(4)
        implicitWidth: modeRow.implicitWidth + 16
        implicitHeight: modeRow.implicitHeight + 12

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }

        Row {
            id: modeRow
            anchors.centerIn: parent
            spacing: 6

            Repeater {
                model: [
                    { id: "area", icon: Icons.regionScreenshot, label: "Area" },
                    { id: "window", icon: Icons.windowScreenshot, label: "Window" },
                    { id: "screen", icon: Icons.fullScreenshot, label: "Screen" }
                ]
                delegate: StyledRect {
                    id: modePill
                    required property var modelData
                    property bool hovered: false
                    readonly property bool selected: root.mode === modelData.id
                    variant: selected ? "primary" : (hovered ? "focus" : "common")
                    radius: Styling.radius(-2)
                    width: pillRow.implicitWidth + 20
                    height: 36

                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: modePill.modelData.icon
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: modePill.item
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: modePill.modelData.label
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: modePill.selected ? Font.Bold : Font.Normal
                            color: modePill.item
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: modePill.hovered = true
                        onExited: modePill.hovered = false
                        onClicked: GlobalStates.tabletPickMode = modePill.modelData.id
                    }
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible)
            Compositor.scheduleRefresh();
        else
            areaMouse.selecting = false;
    }

    Shortcut {
        sequence: "Escape"
        enabled: GlobalStates.tabletPickActive
        onActivated: {
            areaMouse.selecting = false;
            GlobalStates.cancelTabletPick();
        }
    }
}
