import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.config
import qs.modules.components
import qs.modules.theme

FocusScope {
    id: root

    required property string wallpaperPath
    property var properties: []
    property var values: ({})
    property var savedValues: ({})
    property bool loading: true
    property bool saving: false
    property string error: ""
    readonly property bool dirty: JSON.stringify(values) !== JSON.stringify(savedValues)
    readonly property bool hasSettings: properties.some(prop => prop.supported)
    signal closed

    function edit(name, value) {
        const next = Object.assign({}, values);
        next[name] = String(value);
        values = next;
        error = "";
    }

    function defaults() {
        const next = {};
        for (const prop of properties) {
            if (prop.supported) next[prop.name] = prop.default;
        }
        values = next;
        error = "";
    }

    function colorChannels(value) {
        return String(value || "0 0 0").split(/\s+/).map(Number);
    }

    function hexColor(value) {
        return "#" + colorChannels(value).map(channel => Math.round(channel * 255).toString(16).padStart(2, "0")).join("");
    }

    function editHex(name, value) {
        if (!/^#[0-9a-f]{6}$/i.test(value)) {
            error = "Enter a color as #RRGGBB.";
            return;
        }
        edit(name, [1, 3, 5].map(start => parseInt(value.slice(start, start + 2), 16) / 255).join(" "));
    }

    function apply() {
        forceActiveFocus(); // Finish text edits before collecting the draft.
        if (error || !dirty || saving) return;
        saving = true;
        saveProcess.command = ["python3", Paths.script("wallpaper_properties.py"), "save", wallpaperPath, JSON.stringify(values)];
        saveProcess.running = true;
    }

    Component.onCompleted: {
        forceActiveFocus();
        loadProcess.running = true;
    }
    Keys.onEscapePressed: event => {
        if (!saving) root.closed();
        event.accepted = true;
    }

    Process {
        id: loadProcess
        command: ["python3", Paths.script("wallpaper_properties.py"), "load", root.wallpaperPath]
        stdout: StdioCollector { id: loadOutput }
        stderr: StdioCollector { id: loadError }
        onExited: code => {
            root.loading = false;
            if (code !== 0) {
                root.error = loadError.text.trim() || "Could not load wallpaper settings.";
                return;
            }
            try {
                const data = JSON.parse(loadOutput.text);
                root.properties = data.properties;
                root.savedValues = data.values;
                root.values = Object.assign({}, data.values);
            } catch (error) {
                root.error = "Could not read wallpaper settings.";
            }
        }
    }

    Process {
        id: saveProcess
        stderr: StdioCollector { id: saveError }
        onExited: code => {
            root.saving = false;
            if (code !== 0) {
                root.error = saveError.text.trim() || "Could not save wallpaper settings.";
                return;
            }
            root.savedValues = Object.assign({}, root.values);
            WallpaperService.engineSettingsChanged(root.wallpaperPath);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            ActionButton {
                text: "Back"
                enabled: !root.saving
                onClicked: root.closed()
            }
            Text {
                Layout.fillWidth: true
                text: WallpaperService.getDisplayName(root.wallpaperPath)
                color: Colors.overBackground
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(1)
                font.bold: true
                elide: Text.ElideRight
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Wallpaper settings · shared by all screens using this wallpaper"
            color: Colors.overSurfaceVariant
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            wrapMode: Text.Wrap
        }

        Text {
            Layout.fillWidth: true
            visible: root.loading || !!root.error || !root.hasSettings
            text: root.loading ? "Loading settings…" : root.error || "This wallpaper has no supported built-in settings."
            color: root.error ? Colors.red : Colors.overSurfaceVariant
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            wrapMode: Text.Wrap
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: parent.width
                enabled: !root.loading && !root.saving
                spacing: 12

                Repeater {
                    model: root.properties
                    delegate: ColumnLayout {
                        id: row
                        required property var modelData
                        readonly property var definition: modelData
                        readonly property string value: root.values[definition.name] ?? ""
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: row.definition.label
                            textFormat: Text.PlainText
                            color: Colors.overBackground
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            wrapMode: Text.Wrap
                        }

                        Loader {
                            Layout.fillWidth: true
                            active: row.definition.supported
                            sourceComponent: {
                                switch (row.definition.type) {
                                case "boolean": return booleanControl;
                                case "slider": return sliderControl;
                                case "combolist": return choiceControl;
                                case "color": return colorControl;
                                case "textinput":
                                case "file":
                                case "directory": return textControl;
                                }
                                return null;
                            }
                        }

                        Text {
                            visible: !row.definition.supported && !["text", "group"].includes(row.definition.type)
                            text: "Unsupported setting: " + row.definition.type
                            color: Colors.overSurfaceVariant
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                        }

                        Component {
                            id: booleanControl
                            ControlChip {
                                objectName: "setting-" + row.definition.name
                                text: checked ? "Enabled" : "Disabled"
                                checked: row.value === "1"
                                Accessible.name: row.definition.label
                                onClicked: root.edit(row.definition.name, checked ? "0" : "1")
                                onEscapePressed: root.closed()
                            }
                        }

                        Component {
                            id: sliderControl
                            RowLayout {
                                ValueSlider {
                                    objectName: "setting-" + row.definition.name
                                    Layout.fillWidth: true
                                    from: row.definition.min
                                    to: row.definition.max
                                    stepSize: row.definition.step
                                    value: Number(row.value)
                                    Accessible.name: row.definition.label
                                    onMoved: root.edit(row.definition.name, Number(value.toPrecision(12)))
                                }
                                Text {
                                    Layout.preferredWidth: 70
                                    text: row.value
                                    color: Colors.overBackground
                                    font.family: Config.theme.monoFont
                                    font.pixelSize: Styling.fontSize(0)
                                }
                            }
                        }

                        Component {
                            id: choiceControl
                            ComboBox {
                                objectName: "setting-" + row.definition.name
                                model: row.definition.options
                                textRole: "label"
                                valueRole: "value"
                                currentIndex: row.definition.options.findIndex(option => option.value === row.value)
                                Accessible.name: row.definition.label
                                onActivated: root.edit(row.definition.name, currentValue)
                                contentItem: Text {
                                    text: parent.displayText
                                    color: Colors.overBackground
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(0)
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    leftPadding: 8
                                    rightPadding: 24
                                }
                                background: StyledRect { variant: "common"; radius: Styling.radius(0) }
                            }
                        }

                        Component {
                            id: textControl
                            TextField {
                                objectName: "setting-" + row.definition.name
                                text: row.value
                                color: Colors.overBackground
                                font.family: Config.theme.font
                                selectByMouse: true
                                placeholderText: row.definition.type === "file" ? "File path" : row.definition.type === "directory" ? "Folder path" : "Text"
                                Accessible.name: row.definition.label
                                onTextEdited: root.edit(row.definition.name, text)
                                background: StyledRect { variant: "common"; radius: Styling.radius(0) }
                            }
                        }

                        Component {
                            id: colorControl
                            ColumnLayout {
                                RowLayout {
                                    Rectangle {
                                        width: 32; height: 32
                                        radius: Styling.radius(-2)
                                        color: root.hexColor(row.value)
                                        border.width: 1
                                        border.color: Colors.outline
                                    }
                                    TextField {
                                        objectName: "setting-" + row.definition.name
                                        Layout.fillWidth: true
                                        text: root.hexColor(row.value)
                                        color: Colors.overBackground
                                        font.family: Config.theme.monoFont
                                        selectByMouse: true
                                        Accessible.name: row.definition.label + " hex color"
                                        onEditingFinished: root.editHex(row.definition.name, text)
                                        background: StyledRect { variant: "common"; radius: Styling.radius(0) }
                                    }
                                }
                                Repeater {
                                    model: ["Red", "Green", "Blue"]
                                    delegate: RowLayout {
                                        id: channel
                                        required property int index
                                        required property string modelData
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.preferredWidth: 50
                                            text: channel.modelData
                                            color: Colors.overSurfaceVariant
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-1)
                                        }
                                        ValueSlider {
                                            Layout.fillWidth: true
                                            from: 0; to: 1; stepSize: 1 / 255
                                            value: root.colorChannels(row.value)[channel.index]
                                            Accessible.name: row.definition.label + " " + channel.modelData
                                            onMoved: {
                                                const channels = root.colorChannels(row.value);
                                                channels[channel.index] = value;
                                                root.edit(row.definition.name, channels.join(" "));
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            ActionButton {
                text: "Defaults"
                enabled: root.hasSettings && !root.loading && !root.saving
                onClicked: { root.forceActiveFocus(); root.defaults(); }
            }
            Item { Layout.fillWidth: true }
            ActionButton {
                text: "Discard"
                enabled: !root.saving
                onClicked: root.closed()
            }
            ActionButton {
                text: root.saving ? "Saving…" : "Apply"
                enabled: root.dirty && !root.loading && !root.saving
                primary: true
                onClicked: root.apply()
            }
        }
    }

    component ActionButton: Button {
        id: button
        property bool primary: false
        implicitHeight: 36
        horizontalPadding: 14
        opacity: enabled ? 1 : 0.45
        contentItem: Text {
            text: button.text
            color: button.primary ? Colors.overPrimary : Colors.overBackground
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: StyledRect {
            variant: button.primary ? "primary" : button.hovered ? "focus" : "common"
            radius: Styling.radius(0)
            border.width: button.visualFocus ? 2 : 0
            border.color: Colors.primary
        }
    }

    component ValueSlider: Slider {
        id: slider
        implicitHeight: 32
        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: 4
            radius: 2
            color: Colors.surfaceBright
            Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 2; color: Colors.primary }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: 14; height: 14; radius: 7
            color: Colors.primary
            border.width: slider.visualFocus ? 2 : 0
            border.color: Colors.overBackground
        }
    }
}
