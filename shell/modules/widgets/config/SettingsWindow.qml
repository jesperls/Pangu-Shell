import QtQuick
import Quickshell
import qs.modules.widgets.dashboard.controls
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.theme

FloatingWindow {
    id: settingsWindow

    implicitWidth: 1000
    implicitHeight: 760
    title: "Pangu Settings"
    property var clientsBeforeMapping: []
    property bool initialized: false
    visible: initialized && GlobalStates.settingsWindowVisible

    color: "transparent"

    function screenByName(name) {
        if (!name) return null;

        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === name) {
                return Quickshell.screens[i];
            }
        }

        return null;
    }

    function preparePlacement() {
        clientsBeforeMapping = (Compositor.clients.values || []).map(client => client.nativeToplevel);
        const targetScreen = screenByName(GlobalStates.settingsTargetScreenName || Compositor.focusedMonitor?.name || "");
        if (targetScreen) {
            settingsWindow.screen = targetScreen;
        }

        placementTimer.attempts = 0;
        placementTimer.restart();
    }

    function placeOnTargetWorkspace() {
        const specialName = Compositor.focusedMonitor?.activeSpecialWorkspace?.name || "";
        const specialTarget = specialName ? (specialName.startsWith("special:") ? specialName : "special:" + specialName) : "";
        const targetWorkspace = specialTarget || GlobalStates.settingsTargetWorkspaceId || Compositor.focusedMonitor?.activeWorkspace?.id || Compositor.focusedWorkspace?.id || 0;
        if (!targetWorkspace) return false;

        const clients = Compositor.clients.values || [];
        for (let i = 0; i < clients.length; i++) {
            const client = clients[i];
            if (client.title === settingsWindow.title && !clientsBeforeMapping.includes(client.nativeToplevel)) {
                const currentWorkspace = specialTarget ? (client.workspace?.name || "") : client.workspace?.id;
                if (currentWorkspace !== targetWorkspace) {
                    Compositor.dispatch(`movetoworkspacesilent ${targetWorkspace}, address:${client.address}`);
                }
                Compositor.dispatch(`focuswindow address:${client.address}`);
                settingsTab.focusSearchInput();
                return true;
            }
        }

        return false;
    }

    Timer {
        id: placementTimer
        interval: 100
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts++;
            if (!settingsWindow.visible || settingsWindow.placeOnTargetWorkspace() || attempts >= 20) {
                stop();
            }
        }
    }

    StyledRect {
        anchors.fill: parent
        variant: "bg"
        radius: 0

        SettingsTab {
            id: settingsTab
            anchors.fill: parent
            anchors.margins: 16
        }
    }

    Component.onCompleted: {
        initialized = true;
        if (GlobalStates.settingsWindowVisible) {
            preparePlacement();
        }
    }

    onVisibleChanged: {
        if (!initialized)
            return;
        if (visible) {
            preparePlacement();
        } else {
            placementTimer.stop();
            GlobalStates.discardThemeChanges();
            GlobalStates.discardShellChanges();
            GlobalStates.discardCompositorChanges();
        }
    }

    onClosed: GlobalStates.settingsWindowVisible = false
}
