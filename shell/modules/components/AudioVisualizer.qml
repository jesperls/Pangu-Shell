pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.theme
import qs.modules.services
import qs.config

Item {
    id: visualizer

    property bool active: true
    property color color: Styling.srItem("overprimary")
    property real barSpacing: 2
    property bool mirrored: false

    property bool holding: false

    function updateHold() {
        const want = visible && enabled && active;
        if (want && !holding) {
            holding = true;
            CavaService.acquire();
        } else if (!want && holding) {
            holding = false;
            CavaService.release();
        }
    }

    onVisibleChanged: updateHold()
    onEnabledChanged: updateHold()
    onActiveChanged: updateHold()
    Component.onCompleted: updateHold()
    Component.onDestruction: {
        if (holding) {
            holding = false;
            CavaService.release();
        }
    }

    Row {
        anchors.fill: parent
        spacing: visualizer.barSpacing

        Repeater {
            model: CavaService.bars

            Rectangle {
                id: bar

                required property int index
                readonly property real value: CavaService.values.length > index ? CavaService.values[index] : 0

                width: Math.max(1, (visualizer.width - (CavaService.bars - 1) * visualizer.barSpacing) / CavaService.bars)
                height: Math.max(2, value * visualizer.height)
                radius: width / 2
                color: visualizer.color
                anchors.verticalCenter: visualizer.mirrored ? parent.verticalCenter : undefined
                anchors.bottom: visualizer.mirrored ? undefined : parent.bottom

                Behavior on height {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: 90
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }
}
