pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.globals
import qs.config

Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool layerEnabled: true
    property bool flatStyle: false

    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    property bool popupOpen: controlsPopup.isOpen

    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    StyledToolTip {
        show: root.isHovered && !root.popupOpen
        tooltipText: "Audio & Brightness Controls"
    }

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    StyledRect {
        id: buttonBg
        variant: root.popupOpen ? "primary" : (root.flatStyle ? "transparent" : "bg")
        anchors.fill: parent
        enableShadow: !root.flatStyle && root.layerEnabled

        topLeftRadius: root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.endRadius

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.popupOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Styling.animDuration > 0
                NumberAnimation {
                    duration: Styling.animDuration / 2
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: Icons.faders
            font.family: Icons.font
            font.pixelSize: 18
            color: root.popupOpen ? buttonBg.item : Colors.overBackground
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    controlsPopup.close();
                    GlobalStates.openSettingsSection("mixer", "");
                    return;
                } else if (mouse.button === Qt.LeftButton) {
                    controlsPopup.toggle();
                }
            }
        }
    }

    BarPopup {
        id: controlsPopup
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 16

        contentWidth: 220
        contentHeight: slidersColumn.implicitHeight + popupPadding * 2

        ColumnLayout {
            id: slidersColumn
            anchors.fill: parent
            spacing: 12

            ControlSliderRow {
                id: volumeRow
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                Layout.rightMargin: 8

                icon: Audio.volumeIcon(Audio.value, Audio.sink?.audio?.muted ?? false)
                sliderValue: Audio.value / Audio.hardMaxValue
                progressColor: Audio.sink?.audio?.muted ? Colors.outline : Styling.srItem("overprimary")
                wavy: true
                wavyAmplitude: Audio.sink?.audio?.muted ? 0.5 : 1.5 * effectiveValue
                wavyFrequency: Audio.sink?.audio?.muted ? 1.0 : 8.0 * effectiveValue

                onValueChanged: newValue => {
                    Audio.setVolume(newValue * Audio.hardMaxValue);
                }

                onIconClicked: {
                    if (Audio.sink?.audio) {
                        Audio.sink.audio.muted = !Audio.sink.audio.muted;
                    }
                }
            }

            ControlSliderRow {
                id: micRow
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                Layout.rightMargin: 8

                icon: Audio.source?.audio?.muted ? Icons.micSlash : Icons.mic
                sliderValue: Math.min(1, (Number.isFinite(Audio.source?.audio?.volume) ? Audio.source.audio.volume : 0) / Audio.hardMaxValue)
                progressColor: Audio.source?.audio?.muted ? Colors.outline : Styling.srItem("overprimary")
                wavy: true
                wavyAmplitude: Audio.source?.audio?.muted ? 0.5 : 1.5 * effectiveValue
                wavyFrequency: Audio.source?.audio?.muted ? 1.0 : 8.0 * effectiveValue

                onValueChanged: newValue => {
                    Audio.setMicVolume(newValue * Audio.hardMaxValue);
                }

                onIconClicked: {
                    if (Audio.source?.audio) {
                        Audio.source.audio.muted = !Audio.source.audio.muted;
                    }
                }
            }

            ControlSliderRow {
                id: brightnessRow
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                Layout.rightMargin: 8

                property var currentMonitor: Brightness.getMonitorForScreen(root.bar.screen)
                visible: currentMonitor?.ready ?? false

                icon: Icons.sun
                sliderValue: currentMonitor?.brightness ?? 0.5
                progressColor: Styling.srItem("overprimary")
                wavy: true
                wavyAmplitude: 1.5 * effectiveValue
                wavyFrequency: 8.0 * effectiveValue
                iconRotation: effectiveValue * 180
                iconScale: 0.8 + effectiveValue * 0.2

                onValueChanged: newValue => {
                    if (Brightness.syncBrightness) {
                        for (let i = 0; i < Brightness.monitors.length; i++) {
                            let mon = Brightness.monitors[i];
                            if (mon && mon.ready) {
                                mon.setBrightness(newValue);
                            }
                        }
                    } else if (currentMonitor && currentMonitor.ready) {
                        currentMonitor.setBrightness(newValue);
                    }
                }

                onIconClicked: {}
            }
        }
    }
}
