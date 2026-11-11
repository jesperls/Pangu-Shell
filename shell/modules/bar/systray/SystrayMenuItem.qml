import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.config

Button {
    id: root

    property string textStr: ""

    readonly property string cleanText: {
        let t = textStr;
        if (!t) return "";
        t = String(t);
        if (t.startsWith(":/// ")) {
            t = t.substring(5);
        }
        t = t.replace(/__/g, "\x00").replace(/_/g, "").replace(/\x00/g, "_");
        return t.trim();
    }

    property var iconSource: ""
    property bool isImageIcon: false
    property bool isSeparator: false
    property bool itemEnabled: true
    property bool hasSubmenu: false
    property bool expanded: false
    property int depth: 0
    property int buttonType: 0
    property int checkState: 0

    readonly property string resolvedImageSource: {
        const src = String(iconSource || "");
        if (!src) return "";
        if (isImageIcon || src.indexOf("/") !== -1 || src.indexOf(":") !== -1 || src.indexOf(".") !== -1)
            return src;
        if (src.length === 1 && src.charCodeAt(0) >= 0xe000)
            return "";
        return Quickshell.iconPath(src, true) || "";
    }

    readonly property color fgColor: !root.isSeparator && root.itemEnabled && root.hovered ? bgRect.item : Colors.overBackground

    implicitWidth: 200
    implicitHeight: isSeparator ? 10 : 36
    enabled: !isSeparator && itemEnabled

    padding: 0
    background: StyledRect {
        id: bgRect
        variant: !root.isSeparator && root.itemEnabled && root.hovered ? "focus" : "transparent"
        enableShadow: false
        radius: Styling.radius(0)

        Rectangle {
            visible: root.isSeparator
            height: 1
            color: Colors.surfaceBright
            anchors.centerIn: parent
            width: parent.width - 16
        }
    }

    contentItem: RowLayout {
        spacing: 8
        visible: !root.isSeparator
        opacity: root.itemEnabled ? 1.0 : 0.45

        anchors.fill: parent
        anchors.leftMargin: 8 + root.depth * 12
        anchors.rightMargin: 8

        Item {
            visible: root.buttonType > 0
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16

            Rectangle {
                visible: root.buttonType === 1
                anchors.centerIn: parent
                width: 14
                height: 14
                radius: 3
                color: root.checkState === Qt.Unchecked ? "transparent" : Colors.primary
                border.color: root.checkState === Qt.Unchecked ? Colors.outline : Colors.primary
                border.width: 1.5

                Text {
                    anchors.centerIn: parent
                    visible: root.checkState !== Qt.Unchecked
                    text: root.checkState === Qt.PartiallyChecked ? Icons.minus : Icons.accept
                    font.family: Icons.font
                    color: Colors.overPrimary
                    font.pixelSize: 10
                }
            }

            Rectangle {
                visible: root.buttonType === 2
                anchors.centerIn: parent
                width: 14
                height: 14
                radius: 7
                color: "transparent"
                border.color: root.checkState === Qt.Checked ? Colors.primary : Colors.outline
                border.width: 1.5

                Rectangle {
                    anchors.centerIn: parent
                    visible: root.checkState === Qt.Checked
                    width: 7
                    height: 7
                    radius: 4
                    color: Colors.primary
                }
            }
        }

        Loader {
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            visible: (root.resolvedImageSource !== "" || (String(root.iconSource || "").length === 1)) && root.buttonType === 0
            sourceComponent: root.resolvedImageSource !== "" ? imageIcon : fontIcon

            Component {
                id: fontIcon
                Text {
                    text: String(root.iconSource || "")
                    font.family: Icons.font
                    font.pixelSize: 14
                    color: root.fgColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Component {
                id: imageIcon
                Image {
                    source: root.resolvedImageSource
                    fillMode: Image.PreserveAspectFit
                    mipmap: true
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.cleanText
            textFormat: Text.PlainText
            color: root.fgColor
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            visible: root.hasSubmenu
            text: root.expanded ? Icons.caretDown : Icons.caretRight
            font.family: Icons.font
            color: root.fgColor
            font.pixelSize: 12
            verticalAlignment: Text.AlignVCenter
        }
    }
}
