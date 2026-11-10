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
    property string filterText: ""
    readonly property var filteredFonts: {
        const q = filterText.trim().toLowerCase();
        if (q === "")
            return fontModel;
        return fontModel.filter(f => f.toLowerCase().includes(q));
    }
    property bool listExpanded: false
    property int highlightedIndex: -1

    implicitHeight: 32

    function findFontIndex(font) {
        const list = root.filteredFonts;
        for (let i = 0; i < list.length; i++) {
            if (list[i] === font)
                return i;
        }
        return list.length > 0 ? 0 : -1;
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
                root.filterText = "";
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
            fontFilterField.forceActiveFocus();
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
        width: Math.max(root.width, 220)
        height: Math.min(fontListView.contentHeight + 48, 340)
        padding: 4
        modal: false
        focus: true
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

        contentItem: ColumnLayout {
            spacing: 4

            StyledRect {
                variant: "pane"
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: Styling.radius(-6)

                TextField {
                    id: fontFilterField
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    placeholderText: "Search fonts..."
                    placeholderTextColor: Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.overBackground
                    background: null
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.filterText

                    onTextEdited: {
                        root.filterText = text;
                        root.highlightedIndex = root.findFontIndex(root.selectedFont);
                    }

                    Keys.onDownPressed: {
                        if (fontListView.count > 0) {
                            root.highlightedIndex = Math.min(fontListView.count - 1, root.highlightedIndex + 1);
                            fontListView.positionViewAtIndex(root.highlightedIndex, ListView.Contain);
                        }
                    }

                    Keys.onUpPressed: {
                        if (fontListView.count > 0) {
                            root.highlightedIndex = Math.max(0, root.highlightedIndex - 1);
                            fontListView.positionViewAtIndex(root.highlightedIndex, ListView.Contain);
                        }
                    }

                    Keys.onReturnPressed: {
                        if (root.highlightedIndex >= 0 && root.highlightedIndex < root.filteredFonts.length) {
                            const chosen = root.filteredFonts[root.highlightedIndex];
                            root.listExpanded = false;
                            root.fontSelected(chosen);
                        }
                    }

                    Keys.onEscapePressed: {
                        if (text.length > 0) {
                            text = "";
                            root.filterText = "";
                            root.highlightedIndex = root.findFontIndex(root.selectedFont);
                        } else {
                            root.listExpanded = false;
                        }
                    }
                }
            }

            ListView {
                id: fontListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.filteredFonts
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
}
