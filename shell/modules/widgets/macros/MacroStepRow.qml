import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.config

Rectangle {
    id: root

    property var step
    property int stepIndex: 0
    property int count: 0
    property bool active: false
    property var stepTypeDefs: [
        { type: "key", icon: Icons.keyboard, label: "Key press" },
        { type: "text", icon: Icons.textT, label: "Type text" },
        { type: "command", icon: Icons.terminal, label: "Command" },
        { type: "launch", icon: Icons.launch, label: "Launch app" },
        { type: "sound", icon: Icons.speaker, label: "Play sound" },
        { type: "delay", icon: Icons.timer, label: "Delay" },
        { type: "click", icon: Icons.cursor, label: "Mouse click" }
    ]

    signal stepEdited(var step)
    signal moveRequested(int index, int delta)
    signal removeRequested(int index)

    property bool picking: false
    readonly property bool hasPosition: typeof step.x === "number" && typeof step.y === "number"

    function withField(step, key, value) {
        const out = {};
        for (const k in step)
            out[k] = step[k];
        out[key] = value;
        return out;
    }

    function withoutFields(step, keys) {
        const out = {};
        for (const k in step)
            if (keys.indexOf(k) === -1)
                out[k] = step[k];
        return out;
    }

    Connections {
        target: GlobalStates
        function onMousePickSeqChanged() {
            if (!root.picking)
                return;
            root.picking = false;
            if (GlobalStates.mousePickValid)
                root.stepEdited(root.withField(root.withField(root.step, "x", GlobalStates.mousePickX), "y", GlobalStates.mousePickY));
        }
    }

    implicitHeight: content.implicitHeight + 12
    color: "transparent"

    StyledRect {
        anchors.fill: parent
        variant: root.active ? "focus" : "common"
        radius: Styling.radius(-2)
        opacity: root.active ? 1.0 : 0.7
    }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 6

        Text {
            text: (root.stepIndex + 1)
            font.family: Config.theme.monoFont
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
            Layout.preferredWidth: 16
        }

        Row {
            spacing: 2

            Repeater {
                model: root.stepTypeDefs

                MacroIconButton {
                    required property var modelData
                    size: 26
                    iconSize: 14
                    icon: modelData.icon
                    tooltip: modelData.label
                    tone: root.step.type === modelData.type ? "primary" : "ghost"
                    onClicked: root.stepEdited(root.withField(root.step, "type", modelData.type))
                }
            }
        }

        KeyCaptureField {
            visible: root.step.type === "key"
            Layout.fillWidth: true
            value: root.step.keys || ""
            onValueEdited: value => root.stepEdited(root.withField(root.step, "keys", value))
        }

        MacroTextField {
            visible: root.step.type === "text"
            Layout.fillWidth: true
            value: root.step.text || ""
            placeholder: "Text to type"
            onTextEdited: value => root.stepEdited(root.withField(root.step, "text", value))
        }

        MacroTextField {
            visible: root.step.type === "command"
            Layout.fillWidth: true
            value: root.step.command || ""
            placeholder: "bash -c command"
            onTextEdited: value => root.stepEdited(root.withField(root.step, "command", value))
        }

        MacroTextField {
            visible: root.step.type === "launch"
            Layout.fillWidth: true
            value: root.step.command || ""
            placeholder: "app or command to launch"
            onTextEdited: value => root.stepEdited(root.withField(root.step, "command", value))
        }

        MacroSoundField {
            visible: root.step.type === "sound"
            Layout.fillWidth: true
            value: root.step.path || ""
            onValueEdited: value => root.stepEdited(root.withField(root.step, "path", value))
        }

        SettingsNumberInputRow {
            visible: root.step.type === "delay"
            Layout.fillWidth: true
            label: "Wait"
            suffix: "ms"
            value: root.step.ms || 0
            minValue: 0
            maxValue: 3600000
            onValueEdited: value => root.stepEdited(root.withField(root.step, "ms", value))
        }

        Row {
            visible: root.step.type === "click"
            spacing: 4

            Repeater {
                model: ["left", "right", "middle"]

                MacroButton {
                    required property string modelData
                    text: modelData
                    implicitHeight: 26
                    tone: root.step.button === modelData ? "primary" : "common"
                    onClicked: root.stepEdited(root.withField(root.step, "button", modelData))
                }
            }

            MacroButton {
                visible: !root.hasPosition
                icon: Icons.cursor
                text: root.picking ? qsTr("Click…") : qsTr("Pick position")
                tone: root.picking ? "primary" : "common"
                implicitHeight: 26
                onClicked: {
                    root.picking = true;
                    GlobalStates.beginMousePick();
                }
            }

            StyledRect {
                visible: root.hasPosition
                variant: "common"
                radius: Styling.radius(-6)
                implicitWidth: positionText.implicitWidth + 16
                implicitHeight: 26

                Text {
                    id: positionText
                    anchors.centerIn: parent
                    text: root.step.x + ", " + root.step.y
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overBackground
                }
            }

            MacroIconButton {
                visible: root.hasPosition
                size: 26
                iconSize: 13
                icon: Icons.cursor
                tooltip: "Pick a new position"
                onClicked: {
                    root.picking = true;
                    GlobalStates.beginMousePick();
                }
            }

            MacroIconButton {
                visible: root.hasPosition
                size: 26
                iconSize: 13
                icon: Icons.trash
                tone: "danger"
                tooltip: "Clear position"
                onClicked: root.stepEdited(root.withoutFields(root.step, ["x", "y"]))
            }
        }

        MacroIconButton {
            icon: Icons.caretUp
            size: 26
            iconSize: 14
            enabled: root.stepIndex > 0
            tooltip: "Move up"
            onClicked: root.moveRequested(root.stepIndex, -1)
        }

        MacroIconButton {
            icon: Icons.caretDown
            size: 26
            iconSize: 14
            enabled: root.stepIndex < root.count - 1
            tooltip: "Move down"
            onClicked: root.moveRequested(root.stepIndex, 1)
        }

        MacroIconButton {
            icon: Icons.trash
            size: 26
            iconSize: 14
            tone: "danger"
            tooltip: "Remove step"
            onClicked: root.removeRequested(root.stepIndex)
        }
    }
}
