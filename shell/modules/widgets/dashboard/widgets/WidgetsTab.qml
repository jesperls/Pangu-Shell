import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.config
import "calendar"

Rectangle {
    color: "transparent"
    implicitWidth: 760
    implicitHeight: 750

    property int leftPanelWidth: 0

    RowLayout {
        anchors.fill: parent
        spacing: 8

        FullPlayer {
            Layout.preferredWidth: 216
            Layout.fillHeight: true
        }

        ClippingRectangle {
            id: widgetsContainer
            Layout.preferredWidth: controlButtonsContainer.implicitWidth
            Layout.fillHeight: true
            radius: Styling.radius(4)
            color: "transparent"

            property bool circularControlDragging: false

            Flickable {
                id: widgetsFlickable
                anchors.fill: parent
                contentWidth: width
                contentHeight: columnLayout.implicitHeight
                clip: true
                interactive: !widgetsContainer.circularControlDragging

                ColumnLayout {
                    id: columnLayout
                    width: parent.width
                    spacing: 8

                    QuickControls {
                        id: controlButtonsContainer
                    }

                    Calendar {
                        Layout.fillWidth: true
                        Layout.preferredHeight: width
                    }

                    MoreControls {
                        Layout.fillWidth: true
                    }
                }
            }
        }

        NotificationHistory {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        ColumnLayout {
            Layout.fillHeight: true
            spacing: 8

            ColumnLayout {
                id: brightnessContainer
                Layout.fillHeight: true
                Layout.minimumHeight: 100
                spacing: 8

                Item {
                    id: iconContainer
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    Layout.alignment: Qt.AlignHCenter

                    property bool showingSyncFeedback: false

                    StyledRect {
                        id: iconRect
                        radius: Styling.radius(4)
                        variant: {
                            if (iconMouseArea.containsMouse && Brightness.syncBrightness)
                                return "primaryfocus";
                            if (Brightness.syncBrightness)
                                return "primary";
                            if (iconMouseArea.containsMouse)
                                return "focus";
                            return "pane";
                        }
                        anchors.fill: parent

                        Text {
                            id: brightnessIcon
                            anchors.centerIn: parent
                            text: iconContainer.showingSyncFeedback ? Icons.sync : Icons.sun
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: Brightness.syncBrightness ? Styling.srItem("primary") : Colors.overBackground
                            rotation: iconContainer.showingSyncFeedback ? syncIconRotation : brightnessIconRotation
                            scale: iconContainer.showingSyncFeedback ? 1 : brightnessIconScale
                            opacity: iconOpacity

                            readonly property real brightnessIconRotation: brightnessSlider.effectiveValue * 180
                            readonly property real brightnessIconScale: 0.8 + brightnessSlider.effectiveValue * 0.2
                            property real iconOpacity: 1
                            property real syncIconRotation: 0

                            Behavior on color {
                                enabled: Styling.animDuration > 0
                                ColorAnimation {
                                    duration: Styling.animDuration / 2
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Behavior on opacity {
                                enabled: Styling.animDuration > 0
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Behavior on rotation {
                                enabled: Styling.animDuration > 0
                                NumberAnimation {
                                    duration: 400
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Behavior on scale {
                                enabled: Styling.animDuration > 0
                                NumberAnimation {
                                    duration: 400
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        MouseArea {
                            id: iconMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Brightness.syncBrightness = !Brightness.syncBrightness;

                                if (Brightness.syncBrightness) {
                                    iconContainer.showingSyncFeedback = true;
                                    brightnessIcon.iconOpacity = 1;
                                    brightnessIcon.syncIconRotation = 0;
                                    brightnessIcon.syncIconRotation = 360;

                                    syncHoldTimer.start();
                                }
                            }
                            onWheel: wheel => {
                                const delta = wheel.angleDelta.y > 0 ? 0.1 : -0.1;
                                brightnessSlider.applyBrightness(brightnessSlider.effectiveValue + delta);
                            }
                        }

                        Timer {
                            id: syncHoldTimer
                            interval: 600
                            onTriggered: {
                                brightnessIcon.iconOpacity = 0;
                                syncFadeOutTimer.start();
                            }
                        }

                        Timer {
                            id: syncFadeOutTimer
                            interval: 150
                            onTriggered: {
                                iconContainer.showingSyncFeedback = false;
                                brightnessIcon.iconOpacity = 1;
                                brightnessIcon.syncIconRotation = 0;
                            }
                        }
                    }
                }

                Item {
                    Layout.preferredWidth: 48
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignHCenter

                    StyledSlider {
                        id: brightnessSlider
                        anchors.fill: parent
                        anchors.margins: 0
                        vertical: true
                        smoothDrag: true
                        value: (currentMonitor && currentMonitor.ready) ? currentMonitor.brightness : 0
                        resizeParent: false
                        wavy: false
                        scroll: true
                        iconClickable: false
                        sliderVisible: true
                        iconPos: "start"
                        icon: ""
                        progressColor: Styling.srItem("overprimary")

                        property var currentMonitor: {
                            if (Brightness.monitors.length > 0) {
                                let focusedName = Compositor.focusedMonitor?.name ?? "";
                                let found = null;
                                for (let i = 0; i < Brightness.monitors.length; i++) {
                                    let mon = Brightness.monitors[i];
                                    if (mon && mon.screen && mon.screen.name === focusedName) {
                                        found = mon;
                                        break;
                                    }
                                }
                                return found || Brightness.monitors[0];
                            }
                            return null;
                        }

                        function applyBrightness(targetValue) {
                            const clamped = Math.max(0, Math.min(1, targetValue));
                            if (Brightness.syncBrightness) {
                                for (let i = 0; i < Brightness.monitors.length; i++) {
                                    let mon = Brightness.monitors[i];
                                    if (mon && mon.ready) {
                                        mon.setBrightness(clamped);
                                    }
                                }
                            } else if (currentMonitor && currentMonitor.ready) {
                                currentMonitor.setBrightness(clamped);
                            }
                        }

                        onMoved: newValue => applyBrightness(newValue)
                    }
                }
            }

            CircularControl {
                id: volumeControl
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                icon: {
                    if (Audio.sink?.audio?.muted)
                        return Icons.speakerSlash;
                    const vol = Audio.sink?.audio?.volume ?? 0;
                    if (vol < 0.01)
                        return Icons.speakerX;
                    if (vol < 0.19)
                        return Icons.speakerNone;
                    if (vol < 0.49)
                        return Icons.speakerLow;
                    return Icons.speakerHigh;
                }
                value: Audio.sink?.audio?.volume ?? 0
                accentColor: Audio.sink?.audio?.muted ? Colors.outline : Styling.srItem("overprimary")
                isToggleable: true
                isToggled: !(Audio.sink?.audio?.muted ?? false)

                onControlValueChanged: newValue => {
                    if (Audio.sink?.audio) {
                        Audio.sink.audio.volume = newValue;
                    }
                }

                onToggled: {
                    if (Audio.sink?.audio) {
                        Audio.sink.audio.muted = !Audio.sink.audio.muted;
                    }
                }
            }

            CircularControl {
                id: micControl
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                icon: Audio.source?.audio?.muted ? Icons.micSlash : Icons.mic
                value: Audio.source?.audio?.volume ?? 0
                accentColor: Audio.source?.audio?.muted ? Colors.outline : Styling.srItem("overprimary")
                isToggleable: true
                isToggled: !(Audio.source?.audio?.muted ?? false)

                onControlValueChanged: newValue => {
                    if (Audio.source?.audio) {
                        Audio.source.audio.volume = newValue;
                    }
                }

                onToggled: {
                    if (Audio.source?.audio) {
                        Audio.source.audio.muted = !Audio.source.audio.muted;
                    }
                }
            }
        }
    }
}
