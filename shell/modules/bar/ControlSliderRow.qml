pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.config

Item {
    id: root

    signal valueChanged(real newValue)
    signal iconClicked

    property string icon: ""
    property real sliderValue: 0
    property real _dragValue: 0
    readonly property real effectiveValue: mouseArea.pressed ? _dragValue : sliderValue
    property color progressColor: Styling.srItem("overprimary")
    property bool wavy: false
    property real wavyAmplitude: 0.8
    property real wavyFrequency: 8
    property real iconRotation: 0
    property real iconScale: 1

    property real _animatedWavyAmplitude: wavyAmplitude
    property real _animatedWavyFrequency: wavyFrequency
    property real _animatedIconRotation: iconRotation
    property real _animatedIconScale: iconScale

    Behavior on _animatedWavyAmplitude {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration
            easing.type: Easing.OutQuart
        }
    }
    Behavior on _animatedWavyFrequency {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration
            easing.type: Easing.OutQuart
        }
    }
    Behavior on _animatedIconRotation {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }
    Behavior on _animatedIconScale {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    onWavyAmplitudeChanged: _animatedWavyAmplitude = wavyAmplitude
    onWavyFrequencyChanged: _animatedWavyFrequency = wavyFrequency
    onIconRotationChanged: _animatedIconRotation = iconRotation
    onIconScaleChanged: _animatedIconScale = iconScale

    implicitHeight: 36
    implicitWidth: 200

    RowLayout {
        anchors.fill: parent
        spacing: 8

        Item {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            Layout.alignment: Qt.AlignVCenter

            Text {
                id: iconText
                anchors.centerIn: parent
                text: root.icon
                font.family: Icons.font
                font.pixelSize: 18
                color: iconMouseArea.containsMouse ? Styling.srItem("overprimary") : Colors.overBackground
                rotation: root._animatedIconRotation
                scale: root._animatedIconScale

                Behavior on color {
                    enabled: Styling.animDuration > 0
                    ColorAnimation {
                        duration: Styling.animDuration / 2
                    }
                }
            }

            MouseArea {
                id: iconMouseArea
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.iconClicked()
            }
        }

        Item {
            id: sliderContainer
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter

            property real animatedProgress: Math.max(0, Math.min(1, root.effectiveValue))

            Behavior on animatedProgress {
                enabled: Styling.animDuration > 0 && !mouseArea.pressed
                NumberAnimation {
                    duration: Styling.animDuration
                    easing.type: Easing.OutQuart
                }
            }

            Rectangle {
                anchors.left: dragHandle.right
                anchors.leftMargin: 4
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 4
                radius: Styling.radius(0) / 4
                color: Colors.surfaceBright
            }

            Loader {
                active: root.wavy
                anchors.left: parent.left
                anchors.right: dragHandle.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                height: 32
                z: 1
                sourceComponent: CarouselProgress {
                    anchors.fill: parent
                    frequency: root._animatedWavyFrequency
                    color: root.progressColor
                    amplitudeMultiplier: root._animatedWavyAmplitude
                    lineWidth: 4
                    fullLength: sliderContainer.width
                    active: true
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: dragHandle.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                height: 4
                radius: Styling.radius(0) / 4
                color: root.progressColor
                visible: !root.wavy
                z: 1
            }

            Rectangle {
                id: dragHandle
                anchors.verticalCenter: parent.verticalCenter
                x: sliderContainer.width * sliderContainer.animatedProgress - width / 2
                width: mouseArea.pressed ? 2 : 4
                height: mouseArea.pressed ? 20 : 16
                radius: Styling.radius(0)
                color: Colors.overBackground
                z: 2

                Behavior on width {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on height {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
            }

            StyledToolTip {
                delay: 0
                tooltipText: `${Math.round(root.effectiveValue * 100)}%`
                show: mouseArea.pressed
                x: dragHandle.x + dragHandle.width / 2 - width / 2
                y: dragHandle.y - height - 5
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                preventStealing: true

                function calculateValue(mouseX: real): real {
                    if (sliderContainer.width <= 0)
                        return root.sliderValue;
                    return Math.max(0, Math.min(1, mouseX / sliderContainer.width));
                }

                onPressed: mouse => {
                    root._dragValue = calculateValue(mouse.x);
                    root.valueChanged(root._dragValue);
                }

                onPositionChanged: mouse => {
                    if (pressed) {
                        root._dragValue = calculateValue(mouse.x);
                        root.valueChanged(root._dragValue);
                    }
                }

                onWheel: wheel => {
                    const step = 0.05;
                    const next = wheel.angleDelta.y > 0 ? Math.min(1, root.sliderValue + step) : Math.max(0, root.sliderValue - step);
                    root.valueChanged(next);
                }
            }
        }
    }
}
