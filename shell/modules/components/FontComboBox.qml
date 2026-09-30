pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.config

Item {
    id: root

    property string selectedFont: ""
    signal fontSelected(string fontFamily)

    readonly property var fontModel: Qt.fontFamilies()
    property bool listExpanded: false
    property int highlightedIndex: -1

    implicitHeight: 32

    function findFontIndex(font) {
        for (let i = 0; i < fontModel.length; i++) {
            if (fontModel[i] === font)
                return i;
        }
        return -1;
    }

    Component.onCompleted: highlightedIndex = findFontIndex(selectedFont)

    onSelectedFontChanged: {
        const idx = findFontIndex(selectedFont);
        if (idx >= 0)
            highlightedIndex = idx;
    }

    Button {
        id: button
        anchors.fill: parent

        background: Rectangle {
            color: "transparent"
        }

        contentItem: RowLayout {
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: root.selectedFont
                font.family: root.selectedFont
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overBackground
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                text: Icons.caretDown
                font.family: Icons.font
                font.pixelSize: 12
                color: Colors.overSurfaceVariant
            }
        }

        onClicked: {
            root.listExpanded = !root.listExpanded;
            if (root.listExpanded) {
                root.highlightedIndex = root.findFontIndex(root.selectedFont);
                positionTimer.restart();
            }
        }
    }

    Timer {
        id: positionTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (root.highlightedIndex >= 0 && root.highlightedIndex < fontListView.count) {
                fontListView.positionViewAtIndex(root.highlightedIndex, ListView.Center);
            }
        }
    }

    onListExpandedChanged: {
        if (listExpanded) {
            popup.open();
        } else {
            popup.close();
        }
    }

    Popup {
        id: popup
        parent: root
        x: 0
        y: root.height + 4
        width: root.width
        height: Math.min(fontListView.contentHeight + 8, 320)
        padding: 4
        modal: false
        focus: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        onClosed: {
            if (root.listExpanded) {
                root.listExpanded = false;
            }
        }

        background: StyledRect {
            variant: "popup"
            radius: Styling.radius(-4)
        }

        contentItem: ListView {
            id: fontListView
            anchors.fill: parent
            clip: true
            model: root.fontModel
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds

            delegate: Button {
                required property var modelData
                required property int index

                width: fontListView.width
                height: 36
                text: modelData

                onClicked: {
                    root.highlightedIndex = index;
                    root.listExpanded = false;
                    root.fontSelected(modelData);
                }

                background: StyledRect {
                    variant: root.highlightedIndex === index ? "focus" : "transparent"
                    radius: Styling.radius(-4)
                }

                contentItem: Text {
                    text: parent.text
                    font.family: parent.text
                    font.pixelSize: Styling.fontSize(0)
                    color: root.highlightedIndex === index ? Styling.srItem("overprimary") : Colors.overBackground
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 12
                    elide: Text.ElideRight

                    Behavior on color {
                        enabled: Styling.animDuration > 0
                        ColorAnimation {
                            duration: Styling.animDuration / 2
                            easing.type: Easing.OutQuart
                        }
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                width: 6
            }
        }
    }
}
