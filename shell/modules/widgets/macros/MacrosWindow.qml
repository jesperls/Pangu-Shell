import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.globals
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config
import "../../services/macro_utils.js" as MacroUtils

FloatingWindow {
    id: root

    implicitWidth: 1180
    implicitHeight: 720
    title: "Pangu Macros & Hotkeys"
    color: "transparent"

    property bool initialized: false
    property var clientsBeforeMapping: []

    visible: initialized && GlobalStates.macrosWindowVisible

    property string selectedId: ""
    property var draft: MacroUtils.blankMacro("")
    property bool hasSelection: false
    property string searchText: ""
    property bool recording: false
    property bool confirmingDelete: false
    property var filtered: []

    readonly property var macroList: Config.macros.macros || []
    readonly property var triggerTypeDefs: [
        { type: "none", label: "Manual", icon: Icons.handGrab },
        { type: "hotkey", label: "Hotkey", icon: Icons.keyboard },
        { type: "timer", label: "Timer", icon: Icons.timer },
        { type: "app", label: "App", icon: Icons.apps },
        { type: "sequence", label: "Sequence", icon: Icons.list },
        { type: "startup", label: "Startup", icon: Icons.power }
    ]

    function refreshFilter() {
        const query = searchText.trim().toLowerCase();
        root.filtered = query.length === 0
            ? root.macroList.slice()
            : root.macroList.filter(macro => String(macro.name || "").toLowerCase().indexOf(query) !== -1);
    }

    function selectMacro(id) {
        const macro = id ? MacroService.findMacro(id) : null;
        root.selectedId = macro ? id : "";
        root.hasSelection = macro !== null;
        root.draft = macro ? MacroUtils.normalizeMacro(macro) : MacroUtils.blankMacro("");
        root.recording = false;
        root.confirmingDelete = false;
    }

    function mutate(fn) {
        if (!root.hasSelection)
            return;
        const next = MacroUtils.normalizeMacro(root.draft);
        fn(next);
        root.draft = next;
        MacroService.replaceMacro(next);
    }

    function toggleEnabled(macro) {
        const next = MacroUtils.normalizeMacro(macro);
        next.enabled = !next.enabled;
        MacroService.replaceMacro(next);
        if (root.selectedId === next.id && root.hasSelection)
            root.draft = next;
    }

    function toggleMaster() {
        Config.macros.enabled = !Config.macros.enabled;
    }

    function close() {
        root.recording = false;
        root.confirmingDelete = false;
        GlobalStates.macrosWindowVisible = false;
    }

    function screenByName(name) {
        if (!name)
            return null;
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === name)
                return Quickshell.screens[i];
        }
        return null;
    }

    function preparePlacement() {
        clientsBeforeMapping = Compositor.clients.values.map(client => client.nativeToplevel);
        const targetScreen = screenByName(GlobalStates.macrosTargetScreenName || Compositor.focusedMonitor?.name || "");
        if (targetScreen)
            root.screen = targetScreen;
        placementTimer.attempts = 0;
        placementTimer.restart();
    }

    function placeOnTargetWorkspace() {
        const targetWorkspace = GlobalStates.macrosTargetWorkspaceId || Compositor.focusedMonitor?.activeWorkspace?.id || Compositor.focusedWorkspace?.id || 0;
        if (!targetWorkspace)
            return false;
        const clients = Compositor.clients.values || [];
        for (let i = 0; i < clients.length; i++) {
            const client = clients[i];
            if (client.title === root.title && !clientsBeforeMapping.includes(client.nativeToplevel)) {
                if (client.workspace?.id !== targetWorkspace)
                    Compositor.dispatch(`movetoworkspacesilent ${targetWorkspace}, address:${client.address}`);
                Compositor.dispatch(`focuswindow address:${client.address}`);
                searchInput.focusInput();
                return true;
            }
        }
        return false;
    }

    Timer {
        id: placementTimer
        interval: 100
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts++;
            if (!root.visible || root.placeOnTargetWorkspace() || attempts >= 20)
                stop();
        }
    }

    function applyRecordingKey(event) {
        if (event.isAutoRepeat || MacroKeys.isModifier(event.key))
            return;
        if (event.key === Qt.Key_Escape) {
            root.recording = false;
            return;
        }
        const combo = MacroKeys.comboFromEvent(event);
        if (!combo)
            return;
        root.mutate(next => next.steps.push({ type: "key", keys: combo }));
    }

    onMacroListChanged: {
        root.refreshFilter();
        if (root.selectedId && !MacroService.findMacro(root.selectedId))
            root.selectMacro("");
    }
    onSearchTextChanged: refreshFilter()
    onVisibleChanged: {
        if (visible) {
            refreshFilter();
            if (root.selectedId && MacroService.findMacro(root.selectedId))
                root.selectMacro(root.selectedId);
        } else {
            root.recording = false;
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: GlobalStates.macrosWindowVisible && !GlobalStates.mousePickActive
        context: Qt.WindowShortcut
        onActivated: {
            if (root.recording)
                root.recording = false;
            else
                root.close();
        }
    }

    StyledRect {
        anchors.fill: parent
        variant: "bg"
        radius: 0

        Item {
            id: focusCatcher
            anchors.fill: parent
            focus: root.recording

            Keys.onPressed: event => {
                if (!root.recording)
                    return;
                event.accepted = true;
                root.applyRecordingKey(event);
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: Icons.keyboard
                    font.family: Icons.font
                    font.pixelSize: 24
                    color: Styling.srItem("overprimary")
                }

                Text {
                    text: qsTr("Macros & Hotkeys")
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize + 6
                    font.bold: true
                    color: Colors.overBackground
                }

                StyledRect {
                    visible: MacroService.playing || MacroService.activeId !== ""
                    variant: "primary"
                    radius: Styling.radius(-4)
                    implicitWidth: playingRow.implicitWidth + 16
                    implicitHeight: 32

                    RowLayout {
                        id: playingRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: Icons.stop
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: Styling.srItem("overprimary")
                        }

                        Text {
                            text: {
                                const name = MacroService.activeName || MacroService.activeId;
                                return MacroService.queuedCount > 0 ? name + "  +" + MacroService.queuedCount + " queued" : name;
                            }
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Styling.srItem("overprimary")
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MacroService.stop()
                    }
                }

                MacroIconButton {
                    visible: MacroService.playing || MacroService.activeId !== ""
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    size: 32
                    iconSize: 14
                    icon: Icons.stop
                    tone: "danger"
                    tooltip: "Stop all macros"
                    onClicked: MacroService.stop()
                }

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    implicitWidth: 120
                    implicitHeight: 32
                    radius: Styling.radius(-4)
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        spacing: 6

                        Text {
                            text: Config.macros.enabled ? Icons.power : Icons.powerSave
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: Config.macros.enabled ? Colors.primary : Colors.overSurfaceVariant
                        }

                        Text {
                            text: Config.macros.enabled ? "All enabled" : "All paused"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overSurfaceVariant
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleMaster()
                    }
                }

                SearchInput {
                    id: searchInput
                    Layout.preferredWidth: 240
                    Layout.preferredHeight: 40
                    variant: "common"
                    placeholderText: qsTr("Search macros…")
                    clearOnEscape: false
                    onSearchTextChanged: text => root.searchText = text
                    onEscapePressed: root.close()
                }

                MacroIconButton {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    size: 36
                    iconSize: 18
                    icon: Icons.plus
                    tooltip: "New macro"
                    onClicked: root.selectMacro(MacroService.addMacro())
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                StyledRect {
                    variant: "common"
                    Layout.preferredWidth: 300
                    Layout.fillHeight: true
                    radius: Styling.radius(0)

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 6
                        clip: true
                        contentWidth: width
                        contentHeight: listColumn.height
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: listColumn
                            width: parent.width
                            spacing: 4

                            Repeater {
                                model: root.filtered

                                Rectangle {
                                    id: macroRow
                                    required property var modelData
                                    width: listColumn.width
                                    height: 56
                                    radius: Styling.radius(-4)
                                    color: root.selectedId === modelData.id ? Styling.srItem("primary") : "transparent"
                                    opacity: modelData.enabled === false ? 0.55 : 1.0

                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectMacro(macroRow.modelData.id)
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 6
                                        spacing: 8

                                        Text {
                                            text: {
                                                const trigger = MacroUtils.describeTrigger(MacroUtils.normalizeTrigger(modelData.trigger));
                                                return trigger === "Manual" ? Icons.handGrab : Icons.lightning;
                                            }
                                            font.family: Icons.font
                                            font.pixelSize: 16
                                            color: root.selectedId === modelData.id ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
                                        }

                                        Column {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                width: parent.width
                                                text: modelData.name
                                                font.family: Config.theme.font
                                                font.pixelSize: Styling.fontSize(0)
                                                font.bold: root.selectedId === modelData.id
                                                color: root.selectedId === modelData.id ? Styling.srItem("overprimary") : Colors.overBackground
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                width: parent.width
                                                text: MacroUtils.describeTrigger(MacroUtils.normalizeTrigger(modelData.trigger))
                                                    + " · " + modelData.steps.length + " steps"
                                                font.family: Config.theme.font
                                                font.pixelSize: Styling.fontSize(-2)
                                                color: root.selectedId === modelData.id ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MacroIconButton {
                                            size: 28
                                            iconSize: 14
                                            icon: modelData.enabled === false ? Icons.powerSave : Icons.power
                                            tooltip: modelData.enabled === false ? "Enable macro" : "Disable macro"
                                            onClicked: root.toggleEnabled(modelData)
                                        }

                                        MacroIconButton {
                                            size: 28
                                            iconSize: 14
                                            icon: MacroService.playing && MacroService.activeId === modelData.id ? Icons.stop : Icons.play
                                            tooltip: MacroService.playing && MacroService.activeId === modelData.id ? "Stop" : "Run"
                                            tone: MacroService.playing && MacroService.activeId === modelData.id ? "danger" : "ghost"
                                            onClicked: MacroService.run(modelData.id)
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: root.filtered.length === 0
                                width: listColumn.width
                                topPadding: 24
                                text: root.macroList.length === 0 ? "No macros yet — press + to create one." : "No macros match your search."
                                wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignHCenter
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overSurfaceVariant
                            }
                        }
                    }
                }

                Item {
                    id: editorArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Text {
                        anchors.centerIn: parent
                        visible: !root.hasSelection
                        text: "Select a macro on the left, or create a new one."
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        color: Colors.overSurfaceVariant
                    }

                    ScrollView {
                        id: editorScroll
                        anchors.fill: parent
                        visible: root.hasSelection
                        clip: true

                        ColumnLayout {
                            width: editorScroll.availableWidth
                            spacing: 14

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                MacroTextField {
                                    Layout.fillWidth: true
                                    value: root.draft.name
                                    placeholder: "Macro name"
                                    onTextEdited: value => root.mutate(next => next.name = value)
                                }

                                Rectangle {
                                    implicitWidth: 96
                                    implicitHeight: 36
                                    radius: Styling.radius(-4)
                                    border.width: 2
                                    border.color: root.draft.enabled ? Colors.primary : Colors.outline
                                    color: "transparent"

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Text {
                                            text: root.draft.enabled ? Icons.power : Icons.powerSave
                                            font.family: Icons.font
                                            font.pixelSize: 14
                                            color: root.draft.enabled ? Colors.primary : Colors.overSurfaceVariant
                                        }

                                        Text {
                                            text: root.draft.enabled ? "Enabled" : "Disabled"
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-2)
                                            color: Colors.overBackground
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.mutate(next => next.enabled = !next.enabled)
                                    }
                                }
                            }

                            Text {
                                text: qsTr("Trigger")
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(1)
                                font.bold: true
                                color: Colors.overBackground
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: root.triggerTypeDefs

                                    MacroButton {
                                        required property var modelData
                                        icon: modelData.icon
                                        text: modelData.label
                                        tone: root.draft.trigger.type === modelData.type ? "primary" : "common"
                                        onClicked: root.mutate(next => next.trigger = MacroUtils.blankTriggerFor(modelData.type))
                                    }
                                }
                            }

                            KeyCaptureField {
                                Layout.fillWidth: true
                                visible: root.draft.trigger.type === "hotkey"
                                value: root.draft.trigger.keys || ""
                                onValueEdited: value => root.mutate(next => next.trigger.keys = value)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.draft.trigger.type === "timer"
                                spacing: 12

                                SettingsNumberInputRow {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 200
                                    label: "Interval"
                                    suffix: "s"
                                    value: root.draft.trigger.seconds || 60
                                    minValue: 1
                                    maxValue: 86400
                                    onValueEdited: value => root.mutate(next => next.trigger.seconds = value)
                                }

                                SettingsToggleRow {
                                    Layout.preferredWidth: 160
                                    Layout.maximumWidth: 160
                                    label: qsTr("Repeat")
                                    checked: root.draft.trigger.repeat !== false
                                    onToggled: value => root.mutate(next => next.trigger.repeat = value)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.draft.trigger.type === "app"
                                spacing: 12

                                MacroAppPicker {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 240
                                    value: root.draft.trigger.match || ""
                                    onSelected: value => root.mutate(next => next.trigger.match = value)
                                }

                                SettingsToggleRow {
                                    Layout.preferredWidth: 160
                                    Layout.maximumWidth: 160
                                    label: qsTr("On focus")
                                    checked: root.draft.trigger.onFocus === true
                                    onToggled: value => root.mutate(next => next.trigger.onFocus = value)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.draft.trigger.type === "sequence"
                                spacing: 6

                                Repeater {
                                    model: root.draft.trigger.keys || []

                                    RowLayout {
                                        required property int index
                                        Layout.fillWidth: true
                                        spacing: 6

                                        KeyCaptureField {
                                            Layout.fillWidth: true
                                            value: root.draft.trigger.keys[index] || ""
                                            onValueEdited: value => root.mutate(next => next.trigger.keys[index] = value)
                                        }

                                        MacroIconButton {
                                            size: 28
                                            iconSize: 13
                                            icon: Icons.trash
                                            tone: "danger"
                                            tooltip: "Remove"
                                            onClicked: root.mutate(next => next.trigger.keys.splice(index, 1))
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    MacroButton {
                                        icon: Icons.plus
                                        text: qsTr("Add step key")
                                        onClicked: root.mutate(next => next.trigger.keys.push(""))
                                    }

                                    SettingsNumberInputRow {
                                        Layout.fillWidth: true
                                        label: "Window"
                                        suffix: "ms"
                                        value: root.draft.trigger.timeoutMs || 1500
                                        minValue: 200
                                        maxValue: 10000
                                        onValueEdited: value => root.mutate(next => next.trigger.timeoutMs = value)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Press the step keys in order, each within the window, to run the macro. The keys still reach the focused app.")
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.overSurfaceVariant
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Text {
                                text: qsTr("Repeat")
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(1)
                                font.bold: true
                                color: Colors.overBackground
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Repeater {
                                    model: [
                                        { mode: "none", label: "Once" },
                                        { mode: "count", label: "Count" },
                                        { mode: "infinite", label: "Loop" }
                                    ]

                                    MacroButton {
                                        required property var modelData
                                        text: modelData.label
                                        tone: root.draft.loop.mode === modelData.mode ? "primary" : "common"
                                        onClicked: root.mutate(next => next.loop.mode = modelData.mode)
                                    }
                                }

                                SettingsNumberInputRow {
                                    Layout.fillWidth: true
                                    visible: root.draft.loop.mode === "count"
                                    label: "Times"
                                    value: root.draft.loop.count
                                    minValue: 1
                                    maxValue: 9999
                                    onValueEdited: value => root.mutate(next => next.loop.count = value)
                                }

                                SettingsNumberInputRow {
                                    Layout.fillWidth: true
                                    label: "Gap"
                                    suffix: "ms"
                                    value: root.draft.loop.delayMs
                                    minValue: 0
                                    maxValue: 600000
                                    onValueEdited: value => root.mutate(next => next.loop.delayMs = value)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: qsTr("Steps")
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(1)
                                    font.bold: true
                                    color: Colors.overBackground
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                MacroButton {
                                    icon: root.recording ? Icons.stop : Icons.recordScreen
                                    text: root.recording ? qsTr("Stop recording") : qsTr("Record keys")
                                    tone: root.recording ? "danger" : "common"
                                    onClicked: {
                                        root.recording = !root.recording;
                                        root.confirmingDelete = false;
                                        if (root.recording)
                                            focusCatcher.forceActiveFocus();
                                    }
                                }

                                MacroButton {
                                    icon: Icons.plus
                                    text: qsTr("Add step")
                                    onClicked: root.mutate(next => next.steps.push(MacroUtils.blankStep("key")))
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: root.recording
                                text: "Recording — each key you press is appended as a step. Esc stops."
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.error
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: root.draft.steps

                                    MacroStepRow {
                                        required property int index
                                        required property var modelData
                                        Layout.fillWidth: true
                                        step: modelData
                                        stepIndex: index
                                        count: root.draft.steps.length
                                        active: MacroService.playing && MacroService.activeId === root.draft.id && MacroService.activeStep === index
                                        onStepEdited: step => root.mutate(next => next.steps[index] = MacroUtils.normalizeStep(step))
                                        onMoveRequested: (from, delta) => root.mutate(next => {
                                            const to = from + delta;
                                            if (to < 0 || to >= next.steps.length)
                                                return;
                                            const tmp = next.steps[from];
                                            next.steps[from] = next.steps[to];
                                            next.steps[to] = tmp;
                                        })
                                        onRemoveRequested: i => root.mutate(next => next.steps.splice(i, 1))
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: root.draft.steps.length === 0
                                    text: "No steps yet. Add one, or record key presses."
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.overSurfaceVariant
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                spacing: 10

                                MacroButton {
                                    icon: Icons.play
                                    text: qsTr("Run")
                                    tone: "primary"
                                    enabled: root.draft.steps.length > 0
                                    onClicked: MacroService.run(root.draft.id)
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                MacroButton {
                                    icon: Icons.trash
                                    text: root.confirmingDelete ? qsTr("Confirm delete") : qsTr("Delete")
                                    tone: root.confirmingDelete ? "danger" : "common"
                                    onClicked: {
                                        if (!root.confirmingDelete) {
                                            root.confirmingDelete = true;
                                            return;
                                        }
                                        const id = root.draft.id;
                                        root.selectMacro("");
                                        MacroService.removeMacro(id);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        refreshFilter();
        preparePlacement();
        initialized = true;
    }

    onClosed: GlobalStates.macrosWindowVisible = false
}
