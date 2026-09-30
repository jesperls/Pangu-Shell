pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.modules.globals
import qs.config

PanelWindow {
    id: root

    property ShellScreen targetScreen
    screen: targetScreen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "pangu:osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    readonly property bool onTop: (Config.osd && Config.osd.position === "top")

    anchors.top: onTop
    anchors.bottom: !onTop
    anchors.left: true
    anchors.right: true

    WlrLayershell.margins.top: onTop ? 60 : 0
    WlrLayershell.margins.bottom: onTop ? 0 : 100

    color: "transparent"

    visible: GlobalStates.osdVisible && (Quickshell.screens.length === 1 || (Compositor.focusedMonitor && Compositor.focusedMonitor.name === targetScreen.name))

    property real osdValue: 0
    property bool osdMuted: false
    property bool shown: GlobalStates.osdVisible

    Item {
        anchors.fill: parent

        StyledRect {
            id: osdRect
            variant: "popup"
            enableShadow: true
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: root.onTop ? parent.top : undefined
            anchors.bottom: root.onTop ? undefined : parent.bottom
            implicitWidth: (Config.osd && Config.osd.width !== undefined ? Config.osd.width : 260)
            implicitHeight: 68
            radius: Styling.radius(12)

            scale: root.shown ? 1 : 0.92
            opacity: root.shown ? 1 : 0

            transformOrigin: root.onTop ? Item.Top : Item.Bottom

            Behavior on scale {
                enabled: Styling.animDuration > 0
                NumberAnimation {
                    duration: Styling.animDuration / 2
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }

            Behavior on opacity {
                enabled: Styling.animDuration > 0
                NumberAnimation {
                    duration: Styling.animDuration / 2
                    easing.type: Easing.OutCubic
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 24
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                spacing: 14

                StyledRect {
                    id: iconChip
                    visible: (Config.osd && Config.osd.iconStyle !== "plain")
                    variant: "primary"
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 22
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: chipIcon
                        anchors.centerIn: parent
                        text: {
                            if (GlobalStates.osdIndicator === "volume") {
                                return Audio.volumeIcon(root.osdValue, root.osdMuted);
                            } else if (GlobalStates.osdIndicator === "mic") {
                                return root.osdMuted ? Icons.micSlash : Icons.mic;
                            } else {
                                return Icons.sun;
                            }
                        }
                        font.family: Icons.font
                        font.pixelSize: 22
                        color: iconChip.item
                    }
                }

                Text {
                    id: plainIcon
                    visible: !iconChip.visible
                    text: {
                        if (GlobalStates.osdIndicator === "volume") {
                            return Audio.volumeIcon(root.osdValue, root.osdMuted);
                        } else if (GlobalStates.osdIndicator === "mic") {
                            return root.osdMuted ? Icons.micSlash : Icons.mic;
                        } else {
                            return Icons.sun;
                        }
                    }
                    font.family: Icons.font
                    font.pixelSize: 24
                    color: Colors.overBackground
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: {
                                if (GlobalStates.osdIndicator === "volume")
                                    return "Volume";
                                if (GlobalStates.osdIndicator === "mic")
                                    return "Microphone";
                                if (GlobalStates.osdIndicator === "brightness")
                                    return "Brightness";
                                return "";
                            }
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.DemiBold
                            color: Colors.overBackground
                            Layout.alignment: Qt.AlignBottom
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Text {
                            id: percentText
                            text: Math.round(root.osdValue * 100) + "%"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.Bold
                            color: Styling.srItem("overprimary")
                            visible: (Config.osd && Config.osd.showPercentage !== false)
                            Layout.alignment: Qt.AlignBottom

                            scale: root.percentPulse
                            Behavior on scale {
                                enabled: Styling.animDuration > 0
                                NumberAnimation {
                                    duration: Styling.animDuration / 2
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.2
                                }
                            }
                        }
                    }

                    StyledSlider {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 10
                        value: root.osdValue
                        wavy: false
                        enabled: false
                        thickness: 4
                        handleSpacing: 0
                        gradientProgress: true
                        progressColor: root.osdMuted ? Colors.outline : Colors.primary
                        progressColor2: root.osdMuted ? Colors.outline : Colors.tertiary
                        backgroundColor: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.16)
                        visible: (Config.osd && Config.osd.showSlider !== false)
                    }
                }
            }
        }
    }

    property real percentPulse: 1.0

    onOsdValueChanged: {
        percentPulse = 1.25;
        percentPulseAnim.restart();
    }

    NumberAnimation {
        id: percentPulseAnim
        target: root
        property: "percentPulse"
        to: 1.0
        duration: 220
        easing.type: Easing.OutBack
    }

    MouseArea {
        anchors.fill: parent
        onEntered: hideTimer.restart()
        hoverEnabled: true
    }

    Timer {
        id: hideTimer
        interval: 2500
        onTriggered: GlobalStates.osdVisible = false
    }

    Connections {
        target: GlobalStates
        function onOsdVisibleChanged() {
            if (GlobalStates.osdVisible) {
                hideTimer.restart();
            }
        }
    }

    Connections {
        target: Audio
        function onVolumeChanged(volume, muted, node) {
            root.osdValue = volume;
            root.osdMuted = muted;
            GlobalStates.osdIndicator = "volume";
            GlobalStates.osdVisible = true;
            hideTimer.restart();
        }
        function onMicVolumeChanged(volume, muted, node) {
            root.osdValue = volume;
            root.osdMuted = muted;
            GlobalStates.osdIndicator = "mic";
            GlobalStates.osdVisible = true;
            hideTimer.restart();
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged(value, screen) {
            if (!screen || !root.targetScreen || screen.name === root.targetScreen.name || Brightness.syncBrightness) {
                root.osdValue = value;
                root.osdMuted = false;
                GlobalStates.osdIndicator = "brightness";
                GlobalStates.osdVisible = true;
                hideTimer.restart();
            }
        }
    }
}
