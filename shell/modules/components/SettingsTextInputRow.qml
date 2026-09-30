import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.config

RowLayout {
    id: textInputRowRoot
    property string label: ""
    property string value: ""
    property string placeholder: ""
    property string actionText: ""
    property int inputWidth: -1
    property int inputHeight: 32
    property bool monospace: false
    property int maximumLength: 32767
    property int alignment: TextInput.AlignLeft
    property bool trimValue: false
    property bool allowEmpty: true
    signal valueEdited(string newValue)
    signal actionClicked()

    Layout.fillWidth: true
    spacing: 8

    Text {
        text: textInputRowRoot.label
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(0)
        color: Colors.overBackground
        Layout.preferredWidth: 100
    }

    StyledRect {
        variant: "common"
        Layout.fillWidth: textInputRowRoot.inputWidth < 0
        Layout.preferredWidth: textInputRowRoot.inputWidth
        Layout.preferredHeight: textInputRowRoot.inputHeight
        radius: Styling.radius(-2)

        TextInput {
            id: textInputField
            anchors.fill: parent
            anchors.margins: 8
            font.family: textInputRowRoot.monospace ? Config.theme.monoFont : Config.theme.font
            font.pixelSize: textInputRowRoot.monospace ? Styling.monoFontSize(0) : Styling.fontSize(0)
            color: Colors.overBackground
            selectByMouse: true
            clip: true
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: textInputRowRoot.alignment
            maximumLength: textInputRowRoot.maximumLength

            readonly property string configValue: textInputRowRoot.value
            onConfigValueChanged: {
                if (!activeFocus && text !== configValue) {
                    text = configValue;
                }
            }
            Component.onCompleted: text = configValue

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: textInputRowRoot.placeholder
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overSurfaceVariant
                visible: textInputField.text === ""
            }

            onEditingFinished: {
                const next = textInputRowRoot.trimValue ? text.trim() : text;
                if (textInputRowRoot.allowEmpty || next !== "") textInputRowRoot.valueEdited(next);
            }
        }
    }

    StyledRect {
        id: textActionButton
        variant: textInputRowRoot.actionText === "" ? "common" : "primary"
        Layout.preferredWidth: actionLabel.implicitWidth + 20
        Layout.preferredHeight: 32
        radius: Styling.radius(-2)
        visible: textInputRowRoot.actionText !== ""

        Text {
            id: actionLabel
            anchors.centerIn: parent
            text: textInputRowRoot.actionText
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            font.bold: true
            color: textActionButton.item
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: textInputRowRoot.actionClicked()
        }
    }

    Item {
        Layout.fillWidth: true
        visible: textInputRowRoot.inputWidth >= 0
    }
}
