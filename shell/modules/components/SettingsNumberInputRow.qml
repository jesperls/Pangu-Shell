import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.config

RowLayout {
    id: numberInputRowRoot
    property string label: ""
    property real value: 0
    property real minValue: 0
    property real maxValue: 100
    property string suffix: ""
    property int decimals: 0
    function formattedValue() { return value.toFixed(decimals); }
    signal valueEdited(real newValue)

    Layout.fillWidth: true
    spacing: 8
    opacity: enabled ? 1.0 : 0.5

    Text {
        text: numberInputRowRoot.label
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(0)
        color: Colors.overBackground
        Layout.fillWidth: true
    }

    StyledRect {
        id: inputBackground
        variant: "common"
        Layout.preferredWidth: 60
        Layout.preferredHeight: 32
        radius: Styling.radius(-2)


        Rectangle {
            id: rejectOverlay
            anchors.fill: parent
            radius: inputBackground.radius
            color: Colors.error
            opacity: 0
        }

        SequentialAnimation {
            id: rejectFlash
            loops: 2
            NumberAnimation {
                target: rejectOverlay
                property: "opacity"
                to: 0.4
                duration: 90
            }
            NumberAnimation {
                target: rejectOverlay
                property: "opacity"
                to: 0
                duration: 140
            }
        }

        TextInput {
            id: numberTextInput
            anchors.fill: parent
            anchors.margins: 8
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            color: Colors.overBackground
            selectByMouse: true
            clip: true
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter
            validator: numberInputRowRoot.decimals > 0 ? fractionalValidator : integerValidator
            property IntValidator integerValidator: IntValidator {
                bottom: numberInputRowRoot.minValue
                top: numberInputRowRoot.maxValue
            }

            property DoubleValidator fractionalValidator: DoubleValidator {
                bottom: numberInputRowRoot.minValue
                top: numberInputRowRoot.maxValue
                decimals: numberInputRowRoot.decimals
                notation: DoubleValidator.StandardNotation
                locale: "C"
            }

            readonly property real configValue: numberInputRowRoot.value
            onConfigValueChanged: {
                if (!activeFocus && text !== numberInputRowRoot.formattedValue()) {
                    text = numberInputRowRoot.formattedValue();
                }
            }
            Component.onCompleted: text = numberInputRowRoot.formattedValue()

            Keys.onReturnPressed: event => {
                if (acceptableInput) {
                    event.accepted = false;
                } else {
                    rejectFlash.restart();
                }
            }
            Keys.onEnterPressed: event => {
                if (acceptableInput) {
                    event.accepted = false;
                } else {
                    rejectFlash.restart();
                }
            }
            onActiveFocusChanged: {
                if (!activeFocus && !acceptableInput) {
                    rejectFlash.restart();
                    text = numberInputRowRoot.formattedValue();
                }
            }

            onEditingFinished: {
                if (!acceptableInput) {
                    rejectFlash.restart();
                    text = numberInputRowRoot.formattedValue();
                    return;
                }
                numberInputRowRoot.valueEdited(Number(text));
            }
        }
    }

    Text {
        text: numberInputRowRoot.suffix
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(0)
        color: Colors.overSurfaceVariant
        visible: suffix !== ""
    }
}

