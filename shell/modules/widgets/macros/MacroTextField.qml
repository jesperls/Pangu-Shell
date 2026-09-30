import QtQuick
import qs.modules.theme
import qs.modules.components
import qs.config

StyledRect {
    id: root

    property string value: ""
    property string placeholder: ""
    property bool readOnly: false
    signal textEdited(string value)

    variant: input.activeFocus ? "focus" : "common"
    implicitHeight: 36
    radius: Styling.radius(-2)

    function _sync() {
        if (!input.activeFocus && input.text !== root.value)
            input.text = root.value;
    }

    onValueChanged: _sync()
    Component.onCompleted: input.text = root.value

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        clip: true
        selectByMouse: true
        readOnly: root.readOnly
        verticalAlignment: TextInput.AlignVCenter
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(0)
        color: Colors.overBackground

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            text: root.placeholder
            color: Colors.outline
            font: input.font
            visible: input.text.length === 0
        }

        onActiveFocusChanged: {
            if (!activeFocus && input.text !== root.value)
                root.textEdited(input.text);
        }
        onAccepted: root.textEdited(input.text)
    }
}
