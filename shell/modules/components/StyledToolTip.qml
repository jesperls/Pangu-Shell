pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.theme
import qs.modules.components

ToolTip {
    id: root
    property string tooltipText: ""
    property string description: ""
    property bool show: false
    property bool _delayedVisible: false

    readonly property string effectiveText: tooltipText.length > 0 ? tooltipText : text

    delay: 500
    timeout: -1

    Timer {
        id: delayTimer
        interval: Math.max(0, root.delay)
        running: root.show && root.effectiveText.length > 0 && root.delay > 0
        onTriggered: root._delayedVisible = true
    }

    onShowChanged: {
        if (!show)
            _delayedVisible = false;
    }

    visible: effectiveText.length > 0 && (delay <= 0 ? show : (show && _delayedVisible))

    background: StyledRect {
        variant: "popup"
        radius: Styling.radius(-8)
    }

    contentItem: ColumnLayout {
        spacing: 0

        Text {
            text: root.effectiveText
            color: Colors.overBackground
            font.pixelSize: Config.theme?.fontSize ?? 13
            font.weight: Font.Bold
            font.family: Config.theme?.font ?? "sans-serif"
        }

        Text {
            text: root.description
            visible: root.description.length > 0
            color: Colors.overBackground
            font.pixelSize: (Config.theme?.fontSize ?? 13) - 2
            font.family: Config.theme?.font ?? "sans-serif"
        }
    }
}
