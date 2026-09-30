import QtQuick
import QtQuick.Layouts
import qs.modules.theme

Rectangle {
    property bool vert: false

    color: "transparent"
    gradient: Gradient {
        orientation: vert ? Gradient.Vertical : Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0) }
        GradientStop { position: 0.5; color: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.12) }
        GradientStop { position: 1.0; color: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0) }
    }

    implicitWidth: vert ? 2 : 20
    implicitHeight: vert ? 20 : 2

    Layout.fillWidth: !vert
    Layout.fillHeight: vert
}
