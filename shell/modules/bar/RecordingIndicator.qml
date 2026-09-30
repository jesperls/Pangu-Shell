import QtQuick
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.config

Item {
    id: root

    property real startRadius: 0
    property real endRadius: 0
    property bool vertical: false
    property bool enableShadow: true
    property bool flatStyle: false

    property bool recording: ScreenRecorder.isRecording

    visible: recording || ReplayService.active
    implicitWidth: vertical ? 36 : Math.max(36, content.implicitWidth + 20)
    implicitHeight: 36

    StyledRect {
        anchors.fill: parent
        variant: root.flatStyle ? "transparent" : "bg"
        enableShadow: !root.flatStyle && root.enableShadow && Config.showBackground
        topLeftRadius: root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.endRadius
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Rectangle {
            id: dot
            width: 10
            height: 10
            radius: 5
            anchors.verticalCenter: parent.verticalCenter
            color: root.recording ? Colors.error : Colors.tertiary

            property int pulseDuration: root.recording ? 800 : 2000

            SequentialAnimation on opacity {
                running: root.visible && Styling.animDuration > 0
                loops: Animation.Infinite
                NumberAnimation {
                    from: 1
                    to: 0.3
                    duration: dot.pulseDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: 0.3
                    to: 1
                    duration: dot.pulseDuration
                    easing.type: Easing.InOutSine
                }
            }
        }

        Text {
            visible: !root.vertical && root.recording
            anchors.verticalCenter: parent.verticalCenter
            text: ScreenRecorder.duration
            color: Colors.overBackground
            font.family: Config.theme.monoFont
            font.pixelSize: Styling.fontSize(-1)
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.recording ? ScreenRecorder.toggleRecording() : ReplayService.saveClip()
    }
}
