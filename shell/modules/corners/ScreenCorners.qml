import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.services
import qs.modules.theme
import qs.config

Scope {
    id: screenCorners

    required property ShellScreen screen
    property var monitor: null
    property bool activeWindowFullscreen: false

    readonly property bool frameEnabled: Config.bar?.frameEnabled ?? false
    readonly property int cornerSize: Styling.radius(4)
    readonly property bool showCorners: screen !== null && Config.theme.enableCorners && Config.roundness > 0 && !frameEnabled && !activeWindowFullscreen && cornerSize > 0

    function updateFullscreen() {
        const mon = Compositor.monitorFor(screen);
        if (mon) {
            monitor = mon;
        }

        if (!monitor || !monitor.activeWorkspace) {
            activeWindowFullscreen = false;
            return;
        }

        const activeWorkspaceId = monitor.activeWorkspace.id;
        const monId = monitor.id;

        const toplevel = ToplevelManager.activeToplevel;
        if (toplevel && toplevel.fullscreen && Compositor.focusedMonitor && Compositor.focusedMonitor.id === monId) {
            activeWindowFullscreen = true;
            return;
        }

        const wins = Compositor.windowList;
        for (let i = 0; i < wins.length; i++) {
            if (wins[i].monitor === monId && wins[i].fullscreen && wins[i].workspace?.id === activeWorkspaceId) {
                activeWindowFullscreen = true;
                return;
            }
        }
        activeWindowFullscreen = false;
    }

    Connections {
        target: Compositor.monitors
        function onValuesChanged() { screenCorners.updateFullscreen(); }
    }

    Connections {
        target: Compositor
        function onWindowListChanged() { screenCorners.updateFullscreen(); }
    }

    Connections {
        target: Compositor
        function onFocusedMonitorChanged() { screenCorners.updateFullscreen(); }
    }

    Component.onCompleted: updateFullscreen()

    component CornerWindow: PanelWindow {
        required property int cornerType
        required property bool anchorTop
        required property bool anchorLeft

        screen: screenCorners.screen
        visible: screenCorners.showCorners
        implicitWidth: Math.max(1, screenCorners.cornerSize)
        implicitHeight: Math.max(1, screenCorners.cornerSize)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "pangu:screenCorners"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {
            item: null
        }

        anchors {
            top: anchorTop
            bottom: !anchorTop
            left: anchorLeft
            right: !anchorLeft
        }

        RoundCorner {
            anchors.fill: parent
            size: screenCorners.cornerSize
            corner: cornerType
        }
    }

    CornerWindow { cornerType: RoundCorner.CornerEnum.TopLeft; anchorTop: true; anchorLeft: true }
    CornerWindow { cornerType: RoundCorner.CornerEnum.TopRight; anchorTop: true; anchorLeft: false }
    CornerWindow { cornerType: RoundCorner.CornerEnum.BottomLeft; anchorTop: false; anchorLeft: true }
    CornerWindow { cornerType: RoundCorner.CornerEnum.BottomRight; anchorTop: false; anchorLeft: false }
}
