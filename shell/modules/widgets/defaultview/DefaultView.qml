import QtQuick
import Quickshell.Services.Mpris
import qs.modules.theme
import qs.modules.services
import qs.modules.notch
import qs.modules.components
import qs.config

Item {
    id: root
    anchors.top: parent.top
    focus: false

    readonly property int notificationPadding: 16
    readonly property int notificationPaddingBottom: Config.notchTheme === "island" ? 20 : 16
    readonly property int notificationPaddingTop: 8

    readonly property bool hasActiveNotifications: Notifications.popupList.length > 0
    readonly property var activePlayer: MprisController.activePlayer
    property bool notchHovered: false
    property bool parentHoverActive: false
    property bool isNavigating: false

    readonly property string notchPosition: Config.notchPosition ?? "top"
    readonly property bool isBottom: notchPosition === "bottom"

    readonly property bool showUser: Config.notch.showUser ?? true
    readonly property bool showMedia: Config.notch.showMedia ?? true
    readonly property bool showNotifIndicator: Config.notch.showNotificationIndicator ?? true
    readonly property bool showSep1: showUser && showMedia
    readonly property bool showSep2: showMedia && showNotifIndicator
    readonly property int visibleChildCount: (showUser ? 1 : 0) + (showMedia ? 1 : 0) + (showNotifIndicator ? 1 : 0) + (showSep1 ? 1 : 0) + (showSep2 ? 1 : 0)

    HoverHandler {
        id: contentHoverHandler
    }

    readonly property bool expandedState: contentHoverHandler.hovered || notchHovered || parentHoverActive || isNavigating || Visibilities.playerMenuOpen

    property bool mediaHoverExpanded: false

    Timer {
        id: mediaHoverTimer
        interval: Config.notch.hoverExpansionDelay ?? 400
        running: expandedState && activePlayer !== null && !hasActiveNotifications && !mediaHoverExpanded && !(Config.notch.disableHoverExpansion ?? true)
        onTriggered: mediaHoverExpanded = true
    }

    onExpandedStateChanged: {
        if (!expandedState) {
            mediaHoverExpanded = false;
        }
    }

    onActivePlayerChanged: {
        if (!activePlayer) {
            mediaHoverExpanded = false;
        }
    }

    property real mainRowMargin: 16

    Behavior on mainRowMargin {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    readonly property real userW: showUser ? userInfo.width : 0
    readonly property real mediaW: showMedia ? 200 : 0
    readonly property real notifW: showNotifIndicator ? notifIndicator.width : 0
    readonly property real sep1W: showSep1 ? separator1.width : 0
    readonly property real sep2W: showSep2 ? separator2.width : 0
    readonly property int rowSpacingCount: Math.max(0, visibleChildCount - 1)

    readonly property real mainRowContentWidth: userW + sep1W + mediaW + sep2W + notifW + (mainRow.spacing * rowSpacingCount) + mainRowMargin
    readonly property real mainRowHeight: Config.showBackground ? (Config.notchTheme === "island" ? 36 : 44) : (Config.notchTheme === "island" ? 36 : 40)
    readonly property real notificationMinWidth: expandedState ? 420 : 320
    readonly property real notificationContainerHeight: notificationView.implicitHeight + notificationPaddingTop + notificationPaddingBottom

    implicitWidth: Math.round((hasActiveNotifications || mediaHoverExpanded) ? Math.max(notificationMinWidth + (notificationPadding * 2), mainRowContentWidth) : mainRowContentWidth)

    implicitHeight: hasActiveNotifications ? mainRowHeight + notificationContainerHeight : mainRowHeight

    Behavior on implicitWidth {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    Keys.onPressed: event => {
        if (expandedState && activePlayer) {
            if (event.key === Qt.Key_Space) {
                activePlayer.togglePlaying();
                event.accepted = true;
            } else if (event.key === Qt.Key_Left && activePlayer.canSeek) {
                activePlayer.position = Math.max(0, activePlayer.position - 10);
                event.accepted = true;
            } else if (event.key === Qt.Key_Right && activePlayer.canSeek) {
                activePlayer.position = Math.min(activePlayer.length, activePlayer.position + 10);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up && activePlayer.canGoPrevious) {
                activePlayer.previous();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down && activePlayer.canGoNext) {
                activePlayer.next();
                event.accepted = true;
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 0

    }

    Item {
        anchors.fill: parent

        Row {
            id: mainRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: isBottom ? undefined : parent.top
            anchors.bottom: isBottom ? parent.bottom : undefined
            width: parent.width - mainRowMargin
            height: mainRowHeight
            spacing: 4
            z: 2

            UserInfo {
                id: userInfo
                visible: root.showUser
                anchors.verticalCenter: parent.verticalCenter
            }

            Separator {
                id: separator1
                visible: root.showSep1
                vert: true
                anchors.verticalCenter: parent.verticalCenter
            }

            CompactPlayer {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.showMedia
                width: parent.width - root.userW - root.sep1W - root.sep2W - root.notifW - (parent.spacing * root.rowSpacingCount)
                height: 32
                player: activePlayer
                notchHovered: expandedState
            }

            Separator {
                id: separator2
                visible: root.showSep2
                vert: true
                anchors.verticalCenter: parent.verticalCenter
            }

            NotificationIndicator {
                id: notifIndicator
                visible: root.showNotifIndicator
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Item {
            id: notificationContainer
            width: parent.width
            height: hasActiveNotifications ? notificationContainerHeight : 0
            visible: hasActiveNotifications
            
            anchors.top: isBottom ? undefined : mainRow.bottom
            anchors.bottom: isBottom ? mainRow.top : undefined
            
            NotchNotificationView {
                id: notificationView
                anchors.fill: parent
                anchors.topMargin: notificationPaddingTop
                anchors.leftMargin: notificationPadding
                anchors.rightMargin: notificationPadding
                anchors.bottomMargin: notificationPaddingBottom
                visible: hasActiveNotifications
                opacity: visible ? 1 : 0
                notchHovered: expandedState
                onIsNavigatingChanged: root.isNavigating = isNavigating

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
}
