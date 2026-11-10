pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import qs.modules.theme

ClippingRectangle {
    id: root

    property color stripeColor: Colors.criticalRed
    property int stripeWidth: 8
    property int stripeSpacing: 20
    property int animationDuration: 1000
    property bool animationRunning: true
    property real animationOffset: 0

    color: Colors.shadow

    NumberAnimation on animationOffset {
        from: 0
        to: root.stripeSpacing
        duration: root.animationDuration
        loops: Animation.Infinite
        running: root.animationRunning && root.visible && Styling.animDuration > 0
    }

    Repeater {
        model: Math.ceil((root.width + root.height) / Math.max(1, root.stripeWidth))

        Rectangle {
            required property int index
            width: root.stripeWidth
            height: root.height * 3
            rotation: -45
            color: root.stripeColor
            x: ((index * root.stripeSpacing) - (root.animationOffset % root.stripeSpacing)) - root.stripeSpacing
            y: -root.height
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        color: Colors.shadow
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        color: root.stripeColor
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        color: Colors.shadow
    }
}
