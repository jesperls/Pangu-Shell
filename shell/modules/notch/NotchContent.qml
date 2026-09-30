import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.widgets.defaultview
import qs.modules.widgets.dashboard
import qs.modules.widgets.powermenu
import qs.modules.widgets.tools
import qs.modules.services
import qs.modules.components
import qs.modules.widgets.launcher
import qs.modules.bar.workspaces
import qs.config
import "./NotchNotificationView.qml"

Item {
    id: root

    required property ShellScreen screen
    readonly property string screenName: screen?.name ?? ""

    readonly property var screenVisibilities: Visibilities.getForScreen(screenName)

    readonly property var compositorMonitor: Compositor.monitorFor(screen)
    readonly property var toplevels: (!compositorMonitor || !compositorMonitor.activeWorkspace || !Compositor.clients.values) ? [] : Compositor.clients.values.filter(c => c.workspace.id === compositorMonitor.activeWorkspace.id)

    readonly property bool hasWindows: toplevels.length > 0

    readonly property string barPosition: (Config.bar && Config.bar.position !== undefined) ? Config.bar.position : "top"
    readonly property string notchPosition: Config.notchPosition !== undefined ? Config.notchPosition : "top"

    readonly property var barPanelRef: Visibilities.barPanels[screenName]

    readonly property bool barPinned: {
        if (barPanelRef && typeof barPanelRef.pinned !== 'undefined') {
            return barPanelRef.pinned;
        }
        return (Config.bar && Config.bar.pinnedOnStartup !== undefined) ? Config.bar.pinnedOnStartup : true;
    }
    
    readonly property bool barHoverActive: {
        if (barPosition !== notchPosition)
            return false;
        if (barPanelRef && typeof barPanelRef.hoverActive !== 'undefined') {
            return barPanelRef.hoverActive;
        }
        return false;
    }

    readonly property bool activeWindowFullscreen: {
        if (barPanelRef && typeof barPanelRef.hasFullscreenWindow !== 'undefined') {
            return barPanelRef.hasFullscreenWindow;
        }
        const toplevel = ToplevelManager.activeToplevel;
        if (!toplevel || !toplevel.activated)
            return false;
        return toplevel.fullscreen === true;
    }

    readonly property bool shouldAutoHide: {
        if (barPosition !== notchPosition) {
            if ((Config.notch && Config.notch.keepHidden !== undefined) ? Config.notch.keepHidden : false) return true;
            return hasWindows || activeWindowFullscreen;
        }
        return !barPinned || activeWindowFullscreen;
    }


    readonly property bool screenNotchOpen: Visibilities.isNotchOpen(screenVisibilities)
    readonly property bool hasActiveNotifications: Notifications.popupList.length > 0

    property bool hoverActive: false

    readonly property bool isMouseOverNotch: notchMouseAreaHover.hovered || notchRegionHover.hovered

    readonly property bool reveal: {
        if (screenNotchOpen) return true;

        if (activeWindowFullscreen && !(Config.bar && Config.bar.availableOnFullscreen !== undefined ? Config.bar.availableOnFullscreen : false)) {
            return false;
        }

        if ((Config.notch && Config.notch.keepHidden !== undefined) ? Config.notch.keepHidden : false) {
            return (hasActiveNotifications || hoverActive || barHoverActive);
        }

        if (!shouldAutoHide) return true;
        
        if (hasActiveNotifications || hoverActive || barHoverActive) {
            return true;
        }
        
        return false;
    }

    Timer {
        id: hideDelayTimer
        interval: (Config.notch && Config.notch.hideDelay !== undefined ? Config.notch.hideDelay : 1000)
        repeat: false
        onTriggered: {
            if (!root.isMouseOverNotch) {
                root.hoverActive = false;
            }
        }
    }

    onIsMouseOverNotchChanged: {
        if (isMouseOverNotch) {
            hideDelayTimer.stop();
            hoverActive = true;
        } else {
            hideDelayTimer.restart();
        }
    }

    readonly property Item notchHitbox: root.reveal ? notchRegionContainer : notchHoverRegion

    readonly property var centerGap: (Config.bar && Config.bar.splitOnCenteredLayout !== undefined ? Config.bar.splitOnCenteredLayout : true) ? Compositor.gapFor(screenName) : null
    readonly property bool splitActive: centerGap !== null && width > 0
    property real notchCenterFrac: {
        if (!splitActive)
            return 0.5;
        const gapStart = Math.max(0, Math.min(width, centerGap.x));
        const gapEnd = Math.max(0, Math.min(width, centerGap.x + centerGap.width));
        const side = (Config.notch && Config.notch.splitSide !== undefined ? Config.notch.splitSide : "left");
        return (side === "right" ? (gapEnd + width) / 2 : gapStart / 2) / width;
    }

    Behavior on notchCenterFrac {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration / 2
            easing.type: Easing.OutCubic
        }
    }

    readonly property real notchCenterX: notchCenterFrac * width

    Component {
        id: defaultContentComponent
        DefaultView {}
    }

    Loader {
        id: persistentLauncherViewLoader
        active: false
        sourceComponent: Component { LauncherView { visible: false } }
    }

    Loader {
        id: persistentDashboardViewLoader
        active: false
        sourceComponent: Component { DashboardView { visible: false; screenName: root.screenName } }
    }

    Loader {
        id: persistentPowerMenuViewLoader
        active: false
        sourceComponent: Component { PowerMenuView { visible: false } }
    }

    Loader {
        id: persistentToolsMenuViewLoader
        active: false
        sourceComponent: Component { ToolsMenuView { visible: false } }
    }

    Item {
        id: notchHoverRegion

        width: notchRegionContainer.width + 20
        height: root.reveal ? notchRegionContainer.height : Math.max((Config.notch && Config.notch.hoverRegionHeight !== undefined) ? Config.notch.hoverRegionHeight : 8, 8)

        x: root.notchCenterX - width / 2
        y: root.notchPosition === "top" ? 0 : parent.height - height

        Behavior on height {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration / 4
                easing.type: Easing.OutCubic
            }
        }

        HoverHandler {
            id: notchMouseAreaHover
            enabled: true
        }
    }

    Item {
        id: notchRegionContainer
        
        width: Math.max(notchAnimationContainer.width, notificationPopupContainer.visible ? notificationPopupContainer.width : 0)
        height: notchAnimationContainer.height + (notificationPopupContainer.visible ? notificationPopupContainer.height + notificationPopupContainer.anchors.topMargin : 0)

        x: root.notchCenterX - width / 2
        y: root.notchPosition === "top" ? 0 : parent.height - height

        HoverHandler {
            id: notchRegionHover
            enabled: true
        }

        Item {
            id: notchAnimationContainer
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: root.notchPosition === "top" ? parent.top : undefined
            anchors.bottom: root.notchPosition === "bottom" ? parent.bottom : undefined

            width: notchContainer.width
            height: notchContainer.height + (root.notchPosition === "top" ? notchContainer.anchors.topMargin : notchContainer.anchors.bottomMargin)

            opacity: root.reveal ? 1 : 0
            Behavior on opacity {
                enabled: Styling.animDuration > 0
                NumberAnimation {
                    duration: Styling.animDuration / 2
                    easing.type: Easing.OutCubic
                }
            }

            transform: Translate {
                y: {
                    if (root.reveal) return 0;
                    if (root.notchPosition === "top")
                        return -(Math.max(notchContainer.height, 50) + 16);
                    else
                        return (Math.max(notchContainer.height, 50) + 16);
                }
                Behavior on y {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Notch {
                id: notchContainer
                parentHovered: root.isMouseOverNotch
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: root.notchPosition === "top" ? parent.top : undefined
                anchors.bottom: root.notchPosition === "bottom" ? parent.bottom : undefined

                readonly property int frameOffset: (Config.bar && Config.bar.frameEnabled && !root.activeWindowFullscreen) ? ((Config.bar.frameThickness !== undefined) ? Config.bar.frameThickness : 6) : 0

                anchors.topMargin: (root.notchPosition === "top" ? (Config.notchTheme === "default" ? 0 : (Config.notchTheme === "island" ? 4 : 0)) : 0) + (root.notchPosition === "top" ? frameOffset : 0)
                anchors.bottomMargin: (root.notchPosition === "bottom" ? (Config.notchTheme === "default" ? 0 : (Config.notchTheme === "island" ? 4 : 0)) : 0) + (root.notchPosition === "bottom" ? frameOffset : 0)

                defaultViewComponent: defaultContentComponent
                visibilities: root.screenVisibilities

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape && root.screenNotchOpen) {
                        Visibilities.setActiveModule("");
                        event.accepted = true;
                    }
                }
            }
        }

        StyledRect {
            id: notificationPopupContainer
            variant: "bg"
            anchors.top: root.notchPosition === "top" ? notchAnimationContainer.bottom : undefined
            anchors.bottom: root.notchPosition === "bottom" ? notchAnimationContainer.top : undefined
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: root.notchPosition === "top" ? 4 : 0
            anchors.bottomMargin: root.notchPosition === "bottom" ? 4 : 0
            
            width: Math.round(popupHovered ? 420 + 48 : 320 + 48)
            height: shouldShowNotificationPopup ? (notificationPopup.implicitHeight + 32) : 0
            clip: false
            visible: height > 0
            z: 999
            radius: Styling.radius(20)

            opacity: root.reveal ? 1 : 0
            Behavior on opacity {
                enabled: Styling.animDuration > 0
                NumberAnimation {
                    duration: Styling.animDuration / 2
                    easing.type: Easing.OutCubic
                }
            }

            transform: Translate {
                y: {
                    if (root.reveal) return 0;
                    if (root.notchPosition === "top")
                        return -(notchContainer.height + 16);
                    else
                        return (notchContainer.height + 16);
                }
                Behavior on y {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }
            }

            layer.enabled: true
            layer.effect: Shadow {}

            property bool popupHovered: false

            readonly property bool shouldShowNotificationPopup: {
                if (!root.hasActiveNotifications || !root.screenNotchOpen)
                    return false;

                if (screenVisibilities?.dashboard) {
                    return !(GlobalStates.dashboardCurrentTab === 0 && GlobalStates.widgetsTabCurrentIndex === 0);
                }

                return true;
            }

            Behavior on width {
                enabled: Styling.animDuration > 0
                NumberAnimation {
                    duration: Styling.animDuration
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }

            Behavior on height {
                enabled: Styling.animDuration > 0
                NumberAnimation {
                    duration: Styling.animDuration
                    easing.type: Easing.OutQuart
                }
            }

            HoverHandler {
                id: popupHoverHandler
                enabled: notificationPopupContainer.shouldShowNotificationPopup

                onHoveredChanged: {
                    notificationPopupContainer.popupHovered = hovered;
                }
            }

            NotchNotificationView {
                id: notificationPopup
                anchors.fill: parent
                anchors.margins: 16
                visible: notificationPopupContainer.shouldShowNotificationPopup
                opacity: visible ? 1 : 0
                notchHovered: notificationPopupContainer.popupHovered

                Behavior on opacity {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
            }
        }
    }

    Connections {
        target: screenVisibilities

        function onLauncherChanged() {
            if (screenVisibilities?.launcher) {
                persistentLauncherViewLoader.active = true;
                Qt.callLater(() => {
                    if (screenVisibilities?.launcher && persistentLauncherViewLoader.item) {
                        notchContainer.stackView.push(persistentLauncherViewLoader.item);
                        Qt.callLater(() => {
                            if (screenVisibilities?.launcher && notchContainer.stackView.currentItem) {
                                notchContainer.stackView.currentItem.forceActiveFocus();
                            }
                        });
                    }
                });
            } else {
                if (notchContainer.stackView.depth > 1) {
                    notchContainer.stackView.pop();
                }
            }
        }

        function onDashboardChanged() {
            if (screenVisibilities?.dashboard) {
                persistentDashboardViewLoader.active = true;
                Qt.callLater(() => {
                    if (screenVisibilities?.dashboard && persistentDashboardViewLoader.item) {
                        notchContainer.stackView.push(persistentDashboardViewLoader.item);
                        Qt.callLater(() => {
                            if (screenVisibilities?.dashboard && notchContainer.stackView.currentItem) {
                                notchContainer.stackView.currentItem.forceActiveFocus();
                            }
                        });
                    }
                });
            } else {
                if (notchContainer.stackView.depth > 1) {
                    notchContainer.stackView.pop();
                }
            }
        }

        function onPowermenuChanged() {
            if (screenVisibilities?.powermenu) {
                persistentPowerMenuViewLoader.active = true;
                Qt.callLater(() => {
                    if (screenVisibilities?.powermenu && persistentPowerMenuViewLoader.item) {
                        notchContainer.stackView.push(persistentPowerMenuViewLoader.item);
                        Qt.callLater(() => {
                            if (screenVisibilities?.powermenu && notchContainer.stackView.currentItem) {
                                notchContainer.stackView.currentItem.forceActiveFocus();
                            }
                        });
                    }
                });
            } else {
                if (notchContainer.stackView.depth > 1) {
                    notchContainer.stackView.pop();
                }
            }
        }

        function onToolsChanged() {
            if (screenVisibilities?.tools) {
                persistentToolsMenuViewLoader.active = true;
                Qt.callLater(() => {
                    if (screenVisibilities?.tools && persistentToolsMenuViewLoader.item) {
                        notchContainer.stackView.push(persistentToolsMenuViewLoader.item);
                        Qt.callLater(() => {
                            if (screenVisibilities?.tools && notchContainer.stackView.currentItem) {
                                notchContainer.stackView.currentItem.forceActiveFocus();
                            }
                        });
                    }
                });
            } else {
                if (notchContainer.stackView.depth > 1) {
                    notchContainer.stackView.pop();
                }
            }
        }
    }

    property alias notchContainerRef: notchContainer
}
