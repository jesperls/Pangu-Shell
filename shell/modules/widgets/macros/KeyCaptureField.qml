import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.config

FocusScope {
    id: root

    property string value: ""
    property bool recording: false
    property string preview: ""
    signal valueEdited(string value)

    implicitHeight: 36

    function startRecording() {
        root.recording = true;
        root.preview = "";
        root.forceActiveFocus();
    }

    StyledRect {
        anchors.fill: parent
        variant: root.activeFocus ? "focus" : "common"
        radius: Styling.radius(-2)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 6
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: {
                    if (root.recording)
                        return root.preview.length > 0 ? root.preview : "Press a key combo…";
                    return root.value.length > 0 ? root.value : "Not set";
                }
                color: root.recording ? Colors.primary : (root.value.length > 0 ? Colors.overBackground : Colors.outline)
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                elide: Text.ElideRight
            }

            MacroIconButton {
                size: 26
                iconSize: 13
                icon: root.recording ? Icons.stop : Icons.circle
                tone: root.recording ? "danger" : "ghost"
                tooltip: root.recording ? "Stop recording" : "Record a key"
                onClicked: {
                    if (root.recording) {
                        root.recording = false;
                        root.preview = "";
                    } else {
                        root.startRecording();
                    }
                }
            }
        }
    }

    Keys.onPressed: event => {
        if (!root.recording)
            return;
        event.accepted = true;
        if (event.isAutoRepeat)
            return;
        if (event.key === Qt.Key_Escape) {
            root.recording = false;
            root.preview = "";
            return;
        }
        if (MacroKeys.isModifier(event.key)) {
            const names = MacroKeys.modifierNames(event.modifiers);
            root.preview = names.length > 0 ? names.join(" + ") + " + …" : "";
            return;
        }
        const combo = MacroKeys.comboFromEvent(event);
        if (!combo) {
            root.preview = "Unsupported key";
            return;
        }
        root.recording = false;
        root.preview = "";
        root.value = combo;
        root.valueEdited(combo);
    }
}
