import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.services
import qs.config

PanelWindow {
    id: screenCorners

    property var monitor: null
    property bool activeWindowFullscreen: false

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
            if (wins[i].monitor === monId && wins[i].fullscreen && wins[i].workspace.id === activeWorkspaceId) {
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

    visible: Config.theme.enableCorners && Config.roundness > 0 && !activeWindowFullscreen

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "pangu:screenCorners"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {
        item: null
    }

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    ScreenCornersContent {
        id: cornersContent
        anchors.fill: parent
        hasFullscreenWindow: screenCorners.activeWindowFullscreen
    }
}
