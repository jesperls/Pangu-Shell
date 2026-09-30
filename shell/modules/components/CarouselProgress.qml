import QtQuick
import qs.modules.theme

WavyLine {
    id: root

    property real dotSize: 4
    property real spacing: 6
    property real targetSpacing: 6
    property bool active: true

    animationsEnabled: root.active

    lineWidth: dotSize
    
}
