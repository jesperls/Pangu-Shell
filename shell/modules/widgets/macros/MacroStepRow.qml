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
        { type: "click", icon: Icons.cursor, label: "Mouse click" },
        { type: "focus", icon: Icons.popOpen, label: "Focus window" },
        { type: "notify", icon: Icons.bell, label: "Notification" }
    ]

    signal stepEdited(var step)
    signal moveRequested(int index, int delta)
    signal removeRequested(int index)

    property bool picking: false
    readonly property bool hasPosition: typeof step.x === "number" && typeof step.y === "number"
    readonly property string delayMode: step.mode || "fixed"
    readonly property int delayMsVal: typeof step.ms === "number" ? step.ms : 500
    readonly property int delayMaxVal: typeof step.maxMs === "number" ? step.maxMs : Math.max(delayMsVal + 250, 750)
    readonly property int delayStdVal: typeof step.stdDevMs === "number" ? step.stdDevMs : Math.max(15, Math.round(delayMsVal * 0.15))

    component DelayNumberBox: StyledRect {
        id: numBox
        property int value: 0
        property int minValue: 0
        property int maxValue: 3600000
        property string tooltip: ""
        signal valueEdited(int newValue)

        variant: numInput.activeFocus ? "focus" : "common"
        implicitWidth: 66
        implicitHeight: 28
        radius: Styling.radius(-4)

        onValueChanged: {
            if (!numInput.activeFocus && numInput.text !== String(numBox.value))
                numInput.text = String(numBox.value);
        }
        Component.onCompleted: numInput.text = String(numBox.value)

        TextInput {
            id: numInput
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            clip: true
            selectByMouse: true
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter
            font.family: Config.theme.monoFont
            font.pixelSize: Styling.fontSize(-1)
            color: Colors.overBackground
            validator: IntValidator {
                bottom: numBox.minValue
                top: numBox.maxValue
            }
            onActiveFocusChanged: {
                if (!activeFocus && !acceptableInput)
                    text = String(numBox.value);
            }
            onEditingFinished: {
                if (!acceptableInput) {
                    text = String(numBox.value);
                    return;
                }
                const parsed = parseInt(text, 10);
                if (!isNaN(parsed) && parsed !== numBox.value)
                    numBox.valueEdited(parsed);
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: numBox.tooltip !== ""
            StyledToolTip {
                show: parent.containsMouse && !numInput.activeFocus && numBox.tooltip !== ""
                tooltipText: numBox.tooltip
            }
        }
    }

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

        MacroAppPicker {
            visible: root.step.type === "focus"
            Layout.fillWidth: true
            value: root.step.match || ""
            onSelected: value => root.stepEdited(root.withField(root.step, "match", value))
        }

        RowLayout {
            visible: root.step.type === "notify"
            Layout.fillWidth: true
            spacing: 6

            MacroTextField {
                Layout.preferredWidth: 160
                value: root.step.title || ""
                placeholder: "Alert title"
                onTextEdited: value => root.stepEdited(root.withField(root.step, "title", value))
            }

            MacroTextField {
                Layout.fillWidth: true
                value: root.step.body || ""
                placeholder: "Notification body"
                onTextEdited: value => root.stepEdited(root.withField(root.step, "body", value))
            }
        }

        RowLayout {
            visible: root.step.type === "delay"
            Layout.fillWidth: true
            spacing: 6

            Row {
                spacing: 4

                Repeater {
                    model: [
                        { id: "fixed", label: "Fixed" },
                        { id: "range", label: "Range" },
                        { id: "gaussian", label: "Bell" }
                    ]

                    MacroButton {
                        required property var modelData
                        text: modelData.label
                        implicitHeight: 26
                        tone: root.delayMode === modelData.id ? "primary" : "common"
                        onClicked: root.stepEdited(root.withField(root.step, "mode", modelData.id))
                    }
                }
            }

            DelayNumberBox {
                value: root.delayMsVal
                tooltip: root.delayMode === "range"
                    ? "Minimum wait (ms)"
                    : (root.delayMode === "gaussian" ? "Mean wait μ (ms)" : "Exact wait (ms)")
                onValueEdited: val => root.stepEdited(root.withField(root.step, "ms", val))
            }

            Text {
                visible: root.delayMode === "range"
                text: "–"
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overSurfaceVariant
            }

            DelayNumberBox {
                visible: root.delayMode === "range"
                value: root.delayMaxVal
                tooltip: "Maximum wait (ms)"
                onValueEdited: val => root.stepEdited(root.withField(root.step, "maxMs", val))
            }

            Text {
                visible: root.delayMode === "gaussian"
                text: "±"
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overSurfaceVariant
            }

            DelayNumberBox {
                visible: root.delayMode === "gaussian"
                value: root.delayStdVal
                maxValue: 1800000
                tooltip: "Standard deviation σ (ms)"
                onValueEdited: val => root.stepEdited(root.withField(root.step, "stdDevMs", val))
            }

            Text {
                text: "ms"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overSurfaceVariant
            }

            Text {
                visible: root.delayMode === "gaussian" && root.delayStdVal > 0 && root.delayMsVal > 0
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: {
                    const floor = Math.min(10, Math.floor(root.delayMsVal * 0.25));
                    const lo = Math.max(floor, Math.round(root.delayMsVal - 3 * root.delayStdVal));
                    const hi = Math.min(3600000, Math.round(root.delayMsVal + 3 * root.delayStdVal));
                    return "(~" + lo + "–" + hi + " ms)";
                }
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
            }

            Item {
                visible: root.delayMode !== "gaussian" || root.delayStdVal <= 0 || root.delayMsVal <= 0
                Layout.fillWidth: true
            }
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
