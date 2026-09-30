import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.theme

Button {
    id: root

    implicitHeight: 32
    implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
    leftPadding: 12
    rightPadding: 12
    hoverEnabled: true
    opacity: enabled ? 1 : 0.45

    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked

    signal tabPressed
    signal shiftTabPressed
    signal escapePressed

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Tab) {
            if (event.modifiers & Qt.ShiftModifier) root.shiftTabPressed();
            else root.tabPressed();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            root.escapePressed();
            event.accepted = true;
        }
    }

    background: StyledRect {
        id: surface
        variant: root.checked ? "primary" : root.hovered ? "focus" : "common"
        radius: Styling.radius(0)
        Rectangle {
            anchors.fill: parent
            radius: surface.radius
            color: "transparent"
            border.width: root.visualFocus ? 2 : 0
            border.color: Colors.primary
        }
    }

    contentItem: RowLayout {
        spacing: 6
        Text {
            text: root.checked ? Icons.accept : ""
            Layout.preferredWidth: 14
            color: surface.item
            font.family: Icons.font
            font.pixelSize: 14
        }
        Text {
            text: root.text
            color: surface.item
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
    }
}
