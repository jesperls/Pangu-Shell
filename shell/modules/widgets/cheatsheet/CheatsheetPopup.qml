import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config

PanelWindow {
    id: root

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "pangu:cheatsheet"
    WlrLayershell.keyboardFocus: GlobalStates.cheatsheetVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: GlobalStates.cheatsheetVisible
    exclusionMode: ExclusionMode.Ignore

    property var groups: []
    property string searchQuery: ""

    readonly property var modNames: [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"]]

    function keyLabel(key) {
        const mouse = {
            "mouse:272": "LMB",
            "mouse:273": "RMB",
            "mouse:274": "MMB",
            "mouse:275": "MB4",
            "mouse:276": "MB5",
            "mouse:277": "MB6",
            "mouse_up": "Scroll Up",
            "mouse_down": "Scroll Down"
        };
        if (mouse[key])
            return mouse[key];
        if (key.startsWith("XF86"))
            return key.slice(4);
        if (key === "Super_L")
            return "Super";
        if (key === "grave")
            return "`";
        if (key === "period")
            return ".";
        if (key === "comma")
            return ",";
        if (key.length === 1)
            return key.toUpperCase();
        return key.charAt(0).toUpperCase() + key.slice(1);
    }

    function bindLabel(b) {
        let parts = [];
        for (const [mask, name] of root.modNames) {
            if (b.modmask & mask)
                parts.push(name);
        }
        parts.push(keyLabel(b.key === "" && b.keycode > 0 ? "code:" + b.keycode : b.key));
        return parts.join(" + ");
    }

    property var allBinds: []

    function refresh() {
        Compositor.request("j/binds", reply => {
            try {
                root.allBinds = JSON.parse(reply);
            } catch (e) {
                root.allBinds = [];
            }
            root.rebuild();
        });
    }

    function rebuild() {
        const byGroup = {};
        const seen = {};
        for (const b of root.allBinds) {
            if (!b.description || b.key === "")
                continue;
            const sep = b.description.indexOf(": ");
            const group = b.submap ? (b.submap.charAt(0).toUpperCase() + b.submap.slice(1) + " mode") : (sep > 0 ? b.description.slice(0, sep) : "Other");
            let label = sep > 0 ? b.description.slice(sep + 2) : b.description;
            label = label.charAt(0).toUpperCase() + label.slice(1);
            const keys = bindLabel(b);
            const dedup = group + "|" + keys + "|" + label;
            if (seen[dedup])
                continue;
            seen[dedup] = true;

            const q = root.searchQuery.toLowerCase();
            if (q !== "" && !(label.toLowerCase().includes(q) || keys.toLowerCase().includes(q) || group.toLowerCase().includes(q)))
                continue;

            if (!byGroup[group])
                byGroup[group] = [];
            byGroup[group].push({
                keys: keys,
                label: label
            });
        }
        const result = [];
        for (const name of Object.keys(byGroup).sort())
            result.push({
                name: name,
                binds: byGroup[name]
            });
        root.groups = result;
    }

    onSearchQueryChanged: rebuild()

    FocusGrab {
        windows: [root]
        active: GlobalStates.cheatsheetVisible

        onCleared: {
            Qt.callLater(() => {
                GlobalStates.cheatsheetVisible = false;
            });
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Colors.scrim
        opacity: GlobalStates.cheatsheetVisible ? 0.5 : 0

        Behavior on opacity {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration
                easing.type: Easing.OutQuart
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: GlobalStates.cheatsheetVisible = false
        }
    }

    StyledRect {
        id: panel
        variant: "bg"
        anchors.centerIn: parent
        width: Math.min(root.width - 120, 1280)
        height: Math.min(root.height - 120, contentColumn.implicitHeight + 48)
        radius: Styling.radius(20)

        layer.enabled: true
        layer.effect: Shadow {}

        opacity: GlobalStates.cheatsheetVisible ? 1 : 0
        scale: GlobalStates.cheatsheetVisible ? 1 : 0.9

        Behavior on opacity {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration
                easing.type: Easing.OutQuart
            }
        }

        Behavior on scale {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }
        }

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: Icons.keyboard
                    font.family: Icons.font
                    font.pixelSize: 22
                    color: Styling.srItem("overprimary")
                }

                Text {
                    text: qsTr("Keybinds")
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize + 6
                    font.bold: true
                    color: Colors.overBackground
                }

                Item {
                    Layout.fillWidth: true
                }

                SearchInput {
                    id: searchInput
                    Layout.preferredWidth: 320
                    Layout.preferredHeight: 40
                    variant: "common"
                    placeholderText: qsTr("Search keybinds...")
                    clearOnEscape: false

                    onSearchTextChanged: text => {
                        root.searchQuery = text;
                    }

                    onEscapePressed: {
                        if (searchInput.text.length > 0) {
                            searchInput.clear();
                            root.searchQuery = "";
                        } else {
                            GlobalStates.cheatsheetVisible = false;
                        }
                    }
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: groupsFlow.implicitHeight
                contentHeight: groupsFlow.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Flow {
                    id: groupsFlow
                    width: parent.width
                    spacing: 16

                    Repeater {
                        model: root.groups

                        Column {
                            id: groupColumn
                            required property var modelData
                            width: (groupsFlow.width - 2 * groupsFlow.spacing) / 3
                            spacing: 6

                            Text {
                                text: groupColumn.modelData.name
                                font.family: Config.theme.font
                                font.pixelSize: Config.theme.fontSize + 2
                                font.bold: true
                                color: Styling.srItem("overprimary")
                            }

                            Repeater {
                                model: groupColumn.modelData.binds

                                RowLayout {
                                    id: bindRow
                                    required property var modelData
                                    width: groupColumn.width
                                    spacing: 8

                                    StyledRect {
                                        variant: "common"
                                        radius: Styling.radius(6)
                                        Layout.preferredWidth: keyText.implicitWidth + 16
                                        Layout.preferredHeight: keyText.implicitHeight + 8

                                        Text {
                                            id: keyText
                                            anchors.centerIn: parent
                                            text: bindRow.modelData.keys
                                            font.family: Config.theme.monoFont
                                            font.pixelSize: Config.theme.fontSize - 2
                                            color: Colors.overBackground
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: bindRow.modelData.label
                                        font.family: Config.theme.font
                                        font.pixelSize: Config.theme.fontSize - 1
                                        color: Colors.overBackground
                                        opacity: 0.85
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    property bool openDone: false

    function open() {
        if (openDone)
            return;
        openDone = true;
        refresh();
        Qt.callLater(() => {
            searchInput.clear();
            root.searchQuery = "";
            searchInput.focusInput();
        });
    }

    onVisibleChanged: {
        if (visible)
            open();
    }

    Component.onCompleted: {
        if (visible)
            open();
    }
}
