import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import qs.modules.services
import qs.modules.theme
import qs.modules.globals
import qs.config

Button {
    id: root

    required property string buttonIcon
    required property string tooltipText
    required property var onToggle
    property bool iconTint: false
    property bool iconFullTint: false
    property int iconSize: 18
    property bool enableShadow: true
    property bool flatStyle: false
    property real radius: 0
    property bool vertical: false  // Set by parent if needed, or inferred? ToggleButton doesn't know orientation usually.
    property real startRadius: radius
    property real endRadius: radius

    readonly property bool isIconPath: {
        const s = root.buttonIcon;
        if (s.length <= 1) return false;
        if (s.startsWith("<")) return false;              // rich-text glyph
        if (s.includes("/") || s.includes("\\")) return true;
        if (/^[a-z][a-z0-9+.-]*:\/\//i.test(s)) return true; // file: http: image://
        return /\.(png|jpe?g|gif|svgz?|webp|bmp|avif|ico|xpm)$/i.test(s);
    }

    readonly property bool isIconName: {
        if (root.isIconPath) return false;
        const s = root.buttonIcon;
        if (s.length <= 1 || s.startsWith("<")) return false;
        if (!/^[\w.-]+$/.test(s)) return false;           // plain icon-theme name
        return Quickshell.iconPath(s, true).length > 0;
    }

    readonly property string resolvedIconSource: {
        if (!root.isIconPath) return "";
        const s = root.buttonIcon;
        if (s === "~") return Quickshell.env("HOME") || "";
        if (s.startsWith("~/")) return (Quickshell.env("HOME") || "") + s.slice(1);
        return s;
    }

    readonly property bool isIconTinted: root.iconTint || root.iconFullTint

    implicitWidth: Math.max(36, root.iconSize + 12)
    implicitHeight: Math.max(36, root.iconSize + 12)

    scale: root.pressed ? 0.97 : (root.hovered ? 1.03 : 1.0)

    Behavior on scale {
        enabled: (Styling.animDuration ?? 0) > 0
        NumberAnimation {
            duration: (Styling.animDuration ?? 0) / 3
            easing.type: Easing.OutCubic
        }
    }

    background: StyledRect {
        id: bg
        variant: root.flatStyle ? "transparent" : "bg"
        enableShadow: !root.flatStyle && root.enableShadow && Config.showBackground

        topLeftRadius: root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.endRadius

        Rectangle {
            anchors.fill: parent
            color: bg.item
            opacity: root.pressed ? 0.5 : (root.hovered ? 0.25 : 0)
            radius: bg.radius

            Behavior on opacity {
                enabled: (Styling.animDuration ?? 0) > 0
                NumberAnimation {
                    duration: (Styling.animDuration ?? 0) / 2
                }
            }
        }
    }

    contentItem: Item {
        Text {
            id: glyphText
            visible: !root.isIconPath && !root.isIconName
            anchors.fill: parent
            text: root.buttonIcon
            textFormat: Text.RichText
            font.family: Icons.font
            font.pixelSize: root.iconSize
            color: root.isIconTinted
                ? (Styling.srItem("overprimary") || Colors.overBackground)
                : (root.pressed ? Colors.background : Colors.overBackground)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            id: iconImageContainer
            visible: root.isIconPath || root.isIconName
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize

            Image {
                id: iconImage
                anchors.fill: parent
                source: root.isIconPath ? root.resolvedIconSource : (root.isIconName ? "image://icon/" + root.buttonIcon : "")
                sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                asynchronous: true
            }

            Tinted {
                anchors.fill: parent
                sourceItem: iconImage
                active: root.iconTint || root.iconFullTint
                fullTint: root.iconFullTint
            }
        }
    }

    onClicked: root.onToggle()

    StyledToolTip {
        show: root.hovered
        tooltipText: root.tooltipText
    }
}
