import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

StyledRect {
    id: root
    variant: "pane"
    radius: Styling.radius(4)
    implicitHeight: columnLayout.implicitHeight + 8

    onVisibleChanged: {
        if (visible)
            EasyEffectsService.refresh();
    }

    Component.onCompleted: EasyEffectsService.initialize()

    Behavior on implicitHeight {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration
            easing.type: Easing.OutCubic
        }
    }

    ColumnLayout {
        id: columnLayout
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4

        StyledRect {
            variant: "internalbg"
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: buttonRow.implicitWidth + 8
            implicitHeight: buttonRow.implicitHeight + 8
            radius: Styling.radius(0)

            RowLayout {
                id: buttonRow
                anchors.centerIn: parent
                spacing: 4

                ControlButton {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    iconName: Notifications.silent ? Icons.bellZ : Icons.bell
                    isActive: Notifications.silent
                    tooltipText: Notifications.silent ? "Do Not Disturb: On" : "Do Not Disturb: Off"
                    onClicked: Notifications.silent = !Notifications.silent
                }

                ControlButton {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    iconName: PowerProfile.getProfileIcon(PowerProfile.currentProfile)
                    isActive: PowerProfile.currentProfile !== "balanced"
                    tooltipText: "Power: " + PowerProfile.getProfileDisplayName(PowerProfile.currentProfile)
                    onClicked: {
                        const profiles = PowerProfile.availableProfiles;
                        const next = (profiles.indexOf(PowerProfile.currentProfile) + 1) % profiles.length;
                        PowerProfile.setProfile(profiles[next]);
                    }
                }

                ControlButton {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    iconName: Icons.wallpapers
                    isActive: WallpaperSlideshowService.enabled
                    tooltipText: WallpaperSlideshowService.enabled ? "Slideshow: On" : "Slideshow: Off"
                    onClicked: WallpaperSlideshowService.toggle()
                    onRightClicked: WallpaperSlideshowService.next()
                    onLongPressed: WallpaperSlideshowService.next()
                }

                ControlButton {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    iconName: Icons.circleHalf
                    isActive: AutoThemeService.enabled
                    tooltipText: AutoThemeService.enabled ? "Auto Theme: On" : "Auto Theme: Off"
                    onClicked: AutoThemeService.toggle()
                }

                ControlButton {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    iconName: Icons.faders
                    isActive: EasyEffectsService.available && !EasyEffectsService.bypassed
                    tooltipText: {
                        if (!EasyEffectsService.available)
                            return "EasyEffects: Not running";
                        return EasyEffectsService.bypassed ? "EasyEffects: Bypassed" : "EasyEffects: Active";
                    }
                    onClicked: {
                        if (EasyEffectsService.available)
                            EasyEffectsService.setBypass(!EasyEffectsService.bypassed);
                        else
                            EasyEffectsService.refresh();
                    }
                    onRightClicked: EasyEffectsService.openApp()
                    onLongPressed: EasyEffectsService.openApp()
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Layout.bottomMargin: presetsVisible ? 4 : 0
            spacing: 4
            visible: presetsVisible

            readonly property bool presetsVisible: EasyEffectsService.available && EasyEffectsService.outputPresets.length > 0

            Repeater {
                model: EasyEffectsService.outputPresets

                StyledRect {
                    id: presetPill
                    required property string modelData

                    readonly property bool active: EasyEffectsService.activeOutputPreset === modelData

                    variant: active ? "primary" : (presetMouse.containsMouse ? "focus" : "common")
                    radius: Styling.radius(0)
                    implicitWidth: presetLabel.implicitWidth + 16
                    implicitHeight: 26

                    Text {
                        id: presetLabel
                        anchors.centerIn: parent
                        text: presetPill.modelData
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        font.weight: presetPill.active ? Font.Bold : Font.Normal
                        color: presetPill.active ? Styling.srItem("primary") : Colors.overBackground
                    }

                    MouseArea {
                        id: presetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: EasyEffectsService.loadOutputPreset(presetPill.modelData)
                    }
                }
            }
        }
    }
}
