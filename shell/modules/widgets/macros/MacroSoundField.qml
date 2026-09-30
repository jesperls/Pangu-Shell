import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.config

Item {
    id: root

    property string value: ""
    signal valueEdited(string value)

    implicitHeight: 36

    Process {
        id: picker
        command: [
            "zenity", "--file-selection", "--title=Select a sound",
            "--file-filter=Audio | *.mp3 *.wav *.ogg *.oga *.opus *.flac *.m4a *.aac"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) {
                    root.value = path;
                    root.valueEdited(path);
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 6

        MacroTextField {
            Layout.fillWidth: true
            value: root.value
            placeholder: "Sound file path"
            onTextEdited: value => {
                root.value = value;
                root.valueEdited(value);
            }
        }

        MacroIconButton {
            size: 36
            iconSize: 15
            icon: Icons.folder
            tooltip: "Choose a sound file"
            onClicked: picker.running = true
        }
    }
}
