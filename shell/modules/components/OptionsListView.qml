import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.config

ListView {
    id: optionsListView

    property bool isScrolling: dragging || flicking
    property int selectedIndex: -1
    signal indexHovered(int index)

    clip: true
    interactive: false
    boundsBehavior: Flickable.StopAtBounds

    currentIndex: optionsListView.selectedIndex
    highlightFollowsCurrentItem: true
    highlightRangeMode: ListView.ApplyRange
    preferredHighlightBegin: 0
    preferredHighlightEnd: height

    highlight: StyledRect {
        variant: {
            if (optionsListView.currentIndex >= 0 && optionsListView.currentIndex < optionsListView.count) {
                var item = optionsListView.model[optionsListView.currentIndex];
                if (item && item.highlightColor) {
                    if (item.highlightColor === Colors.error)
                        return "error";
                    if (item.highlightColor === Colors.secondary)
                        return "secondary";
                    return "primary";
                }
            }
            return "primary";
        }
        radius: Styling.radius(0)
        visible: optionsListView.currentIndex >= 0
        z: -1

        Behavior on opacity {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration / 2
                easing.type: Easing.OutQuart
            }
        }
    }

    highlightMoveDuration: Styling.animDuration > 0 ? Styling.animDuration / 2 : 0
    highlightMoveVelocity: -1
    highlightResizeDuration: Styling.animDuration / 2
    highlightResizeVelocity: -1

    delegate: Item {
        required property var modelData
        required property int index

        property alias itemData: delegateData.modelData

        QtObject {
            id: delegateData
            property var modelData: parent ? parent.modelData : null
        }

        width: optionsListView.width
        height: 36

        Rectangle {
            anchors.fill: parent
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                Text {
                    text: modelData && modelData.icon ? modelData.icon : ""
                    font.family: Icons.font
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    textFormat: Text.RichText
                    color: {
                        if (optionsListView.currentIndex === index && modelData && modelData.textColor) {
                            return modelData.textColor;
                        }
                        return Colors.overSurface;
                    }

                    Behavior on color {
                        enabled: Styling.animDuration > 0
                        ColorAnimation {
                            duration: Styling.animDuration / 2
                            easing.type: Easing.OutQuart
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: modelData && modelData.text ? modelData.text : ""
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    font.weight: optionsListView.currentIndex === index ? Font.Bold : Font.Normal
                    color: {
                        if (optionsListView.currentIndex === index && modelData && modelData.textColor) {
                            return modelData.textColor;
                        }
                        return Colors.overSurface;
                    }
                    elide: Text.ElideRight
                    maximumLineCount: 1

                    Behavior on color {
                        enabled: Styling.animDuration > 0
                        ColorAnimation {
                            duration: Styling.animDuration / 2
                            easing.type: Easing.OutQuart
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: !optionsListView.isScrolling
                cursorShape: Qt.PointingHandCursor

                onEntered: {
                    if (optionsListView.isScrolling)
                        return;
                    optionsListView.indexHovered(index);
                }

                onClicked: {
                    if (optionsListView.isScrolling)
                        return;
                    if (modelData && modelData.action) {
                        modelData.action();
                    }
                }
            }
        }
    }
}
