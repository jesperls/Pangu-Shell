pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import QtQuick.Effects
import qs.modules.components
import qs.modules.services
import qs.config

Rectangle {
    id: root
    color: "transparent"
    implicitWidth: 400
    implicitHeight: 300

    property string currentSection: "network"
    property int selectedIndex: 0
    property string searchQuery: ""

    onFilteredSectionsChanged: {
        if (searchQuery.trim().length > 0 || selectedIndex >= filteredSections.length)
            selectedIndex = 0;
        Qt.callLater(root.activateSelection);
    }

    onSelectedIndexChanged: Qt.callLater(root.activateSelection)

    function focusSearchInput() {
        searchInput.focusInput();
    }

    SettingsIndex {
        id: searchIndex
    }

    property string pendingSubSection: ""

    function activateSelection() {
        const entry = filteredSections[selectedIndex];
        if (!entry) return;
        pendingSubSection = entry.subSection || "";
        currentSection = entry.section;
        if (panelLoader.status === Loader.Ready && panelLoader.loadedSection === currentSection)
            applySubSection();
        scrollSidebarToSelection();
    }

    function applySubSection() {
        if (panelLoader.item && panelLoader.item.currentSection !== undefined)
            panelLoader.item.currentSection = pendingSubSection;
    }

    function scrollSidebarToSelection() {
        if (sidebarFlickable.height <= 0)
            return;

        const tabHeight = 48;
        const tabSpacing = 0;
        const itemY = root.selectedIndex * (tabHeight + tabSpacing);

        if (itemY < sidebarFlickable.contentY) {
            sidebarFlickable.contentY = itemY;
        } else if (itemY + tabHeight > sidebarFlickable.contentY + sidebarFlickable.height) {
            sidebarFlickable.contentY = itemY + tabHeight - sidebarFlickable.height;
        }
    }

    function fuzzyScore(query, target) {
        if (query.length === 0)
            return 0;
        if (target.length === 0)
            return -1;
        const lowerQuery = query.toLowerCase();
        const lowerTarget = target.toLowerCase();

        if (lowerTarget.includes(lowerQuery))
            return 1000 + (100 - target.length);

        let queryIndex = 0, score = 0, consecutive = 0, maxConsecutive = 0;
        for (let i = 0; i < lowerTarget.length && queryIndex < lowerQuery.length; i++) {
            if (lowerTarget[i] === lowerQuery[queryIndex]) {
                queryIndex++;
                consecutive++;
                maxConsecutive = Math.max(maxConsecutive, consecutive);
                if (i === 0 || " -_".includes(lowerTarget[i - 1]))
                    score += 10;
            } else {
                consecutive = 0;
            }
        }
        return queryIndex === lowerQuery.length ? score + maxConsecutive * 5 : -1;
    }

    readonly property var sectionModel: [
        {
            icon: Icons.wifiHigh,
            label: "Network",
            section: "network",
            isIcon: true
        },
        {
            icon: Icons.bluetooth,
            label: "Bluetooth",
            section: "bluetooth",
            isIcon: true
        },
        {
            icon: Icons.faders,
            label: "Mixer",
            section: "mixer",
            isIcon: true
        },
        {
            icon: Icons.waveform,
            label: "Effects",
            section: "effects",
            isIcon: true
        },
        {
            icon: Icons.paintBrush,
            label: "Theme",
            section: "theme",
            isIcon: true
        },
        {
            icon: Icons.circuitry,
            label: "System",
            section: "system",
            isIcon: true
        },
        {
            icon: Icons.compositor,
            label: "Compositor",
            section: "compositor",
            isIcon: true
        },
        {
            icon: Icons.cube,
            label: "Shell",
            section: "shell",
            isIcon: true
        }
    ]

    readonly property var filteredSections: {
        const query = searchQuery.trim().toLowerCase();
        if (!query)
            return sectionModel;

        const words = query.split(/\s+/);
        return searchIndex.items.map(item => {
            const context = [item.label, item.keywords || "", item.subLabel || ""].join(" ").toLowerCase();
            let score = fuzzyScore(query, item.label);
            for (const word of words) {
                const labelScore = fuzzyScore(word, item.label);
                if (labelScore < 0 && !context.includes(word)) return null;
                score += Math.max(0, labelScore);
            }
            const sectionMeta = sectionModel.find(s => s.section === item.section) || {};
            return {
                label: item.label,
                section: item.section,
                subSection: item.subSection || "",
                subLabel: item.subLabel || "",
                icon: sectionMeta.icon || item.icon,
                isIcon: sectionMeta.isIcon !== undefined ? sectionMeta.isIcon : (item.isIcon !== undefined ? item.isIcon : true),
                score: score
            };
        }).filter(item => item !== null).sort((a, b) => b.score - a.score);
    }

    RowLayout {
        anchors.fill: parent
        spacing: 8

        ColumnLayout {
            Layout.preferredWidth: 200
            Layout.maximumWidth: 200
            Layout.fillHeight: true
            spacing: 4

            SearchInput {
                id: searchInput
                Layout.fillWidth: true
                placeholderText: "Search..."
                clearOnEscape: true

                onSearchTextChanged: text => {
                    root.searchQuery = text;
                }
                onEscapePressed: {
                    searchInput.focus = false;
                    root.forceActiveFocus();
                }

                onAccepted: root.activateSelection()

                onDownPressed: {
                    if (root.selectedIndex < root.filteredSections.length - 1) {
                        root.selectedIndex++;
                    } else {
                        root.selectedIndex = 0;
                    }
                }

                onUpPressed: {
                    if (root.selectedIndex > 0) {
                        root.selectedIndex--;
                    } else {
                        root.selectedIndex = root.filteredSections.length - 1;
                    }
                }
            }

            StyledRect {
                id: sidebarContainer
                variant: "common"
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: sidebarFlickable
                    anchors.fill: parent
                    anchors.margins: 4
                    contentWidth: width
                    contentHeight: sidebar.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Behavior on contentY {
                        enabled: Styling.animDuration > 0 && !sidebarFlickable.moving
                        NumberAnimation {
                            duration: Styling.animDuration / 2
                            easing.type: Easing.OutCubic
                        }
                    }

                    StyledRect {
                        id: tabHighlight
                        variant: "focus"
                        width: parent.width
                        height: 48
                        radius: Styling.radius(-6)
                        z: 0

                        readonly property int tabHeight: 48
                        readonly property int tabSpacing: 0

                        x: 0
                        y: {
                            const idx = root.selectedIndex;
                            return idx >= 0 ? idx * (tabHeight + tabSpacing) : 0;
                        }
                        visible: root.selectedIndex >= 0 && root.selectedIndex < root.filteredSections.length

                        Behavior on y {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Styling.animDuration / 2
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Column {
                        id: sidebar
                        width: parent.width
                        spacing: 0
                        z: 1

                        Repeater {
                            model: root.filteredSections

                            delegate: Button {
                                id: sidebarButton
                                required property var modelData
                                required property int index

                                width: sidebar.width
                                height: 48
                                flat: true
                                hoverEnabled: true

                                property bool isActive: index === root.selectedIndex

                                background: Rectangle {
                                    color: "transparent"
                                }

                                contentItem: Row {
                                    spacing: 8

                                    Text {
                                        id: iconText
                                        text: sidebarButton.modelData.isIcon ? sidebarButton.modelData.icon : ""
                                        font.family: Icons.font
                                        font.pixelSize: 20
                                        color: sidebarButton.isActive ? Styling.srItem("overprimary") : Styling.srItem("common")
                                        anchors.verticalCenter: parent.verticalCenter
                                        leftPadding: 10
                                        visible: sidebarButton.modelData.isIcon && (root.searchQuery.length === 0 || !sidebarButton.modelData.subSection)

                                        Behavior on color {
                                            enabled: Styling.animDuration > 0
                                            ColorAnimation {
                                                duration: Styling.animDuration
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }

                                    Item {
                                        width: 30
                                        height: 20
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !sidebarButton.modelData.isIcon && (root.searchQuery.length === 0 || !sidebarButton.modelData.subSection)

                                        Image {
                                            id: svgIcon
                                            width: 20
                                            height: 20
                                            anchors.centerIn: parent
                                            anchors.horizontalCenterOffset: 5
                                            source: !sidebarButton.modelData.isIcon ? sidebarButton.modelData.icon : ""
                                            sourceSize: Qt.size(width * 2, height * 2)
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            asynchronous: true
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                brightness: 1.0
                                                colorization: 1.0
                                                colorizationColor: sidebarButton.isActive ? Styling.srItem("overprimary") : Styling.srItem("common")
                                            }
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            text: sidebarButton.modelData.label
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(0)
                                            font.weight: sidebarButton.isActive ? Font.Bold : Font.Normal
                                            color: sidebarButton.isActive ? Styling.srItem("overprimary") : Styling.srItem("common")

                                            Behavior on color {
                                                enabled: Styling.animDuration > 0
                                                ColorAnimation {
                                                    duration: Styling.animDuration
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }

                                        Text {
                                            visible: !!sidebarButton.modelData.subLabel
                                            text: sidebarButton.modelData.subLabel || ""
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-2)
                                            color: Colors.overSurfaceVariant
                                        }
                                    }
                                }

                                onClicked: {
                                    root.selectedIndex = index;
                                    root.activateSelection();
                                }
                            }
                        }
                    }

                    WheelHandler {
                        enabled: sidebarFlickable.contentHeight <= sidebarFlickable.height
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => {
                            if (event.angleDelta.y > 0 && root.selectedIndex > 0) {
                                root.selectedIndex--;
                            } else if (event.angleDelta.y < 0 && root.selectedIndex < root.filteredSections.length - 1) {
                                root.selectedIndex++;
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: contentArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            readonly property int maxContentWidth: 480

            readonly property var panelComponents: [
                {
                    component: "WifiPanel.qml",
                    section: "network"
                },
                {
                    component: "BluetoothPanel.qml",
                    section: "bluetooth"
                },
                {
                    component: "AudioMixerPanel.qml",
                    section: "mixer"
                },
                {
                    component: "EasyEffectsPanel.qml",
                    section: "effects"
                },
                {
                    component: "ThemePanel.qml",
                    section: "theme",
                    configPrefixes: ["theme"]
                },
                {
                    component: "SystemPanel.qml",
                    section: "system",
                    configPrefixes: ["system", "prefix", "performance", "weather"]
                },
                {
                    component: "CompositorPanel.qml",
                    section: "compositor",
                    configPrefixes: ["compositor"]
                },
                {
                    component: "ShellPanel.qml",
                    section: "shell",
                    configPrefixes: ["bar", "dashboard", "dock", "launcher", "lockscreen", "notch", "osd", "overview", "workspaces", "system.ocr"]
                }
            ]

            readonly property var currentPanel: panelComponents.find(p => p.section === root.currentSection)
            readonly property var visibleOverrides: {
                const prefixes = currentPanel?.configPrefixes ?? [];
                return Config.nixOverridePaths.filter(path => prefixes.some(prefix =>
                    path === prefix || path.startsWith(prefix + ".")));
            }

            ScrollView {
                id: overrideNotice
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: visible ? Math.min(120, overrideText.implicitHeight + 16) : 0
                visible: root.filteredSections.length > 0 && contentArea.visibleOverrides.length > 0
                clip: true

                Text {
                    id: overrideText
                    width: overrideNotice.availableWidth
                    padding: 8
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    font.family: Config.theme.font
                    color: Colors.overBackground
                    text: "Nix restores these settings when the shell restarts. Changes here are temporary:\n"
                        + contentArea.visibleOverrides.join(", ")
                }
            }

            Text {
                anchors.centerIn: parent
                width: Math.min(parent.width - 32, 400)
                visible: root.filteredSections.length === 0
                text: "No matching settings. Try a shorter search or another word."
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.family: Config.theme.font
                font.pixelSize: Config.theme.fontSize
                color: Colors.overSurfaceVariant
            }

            Loader {
                id: panelLoader
                property string loadedSection: ""
                anchors.top: overrideNotice.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                asynchronous: true
                visible: root.filteredSections.length > 0
                source: contentArea.currentPanel?.component ?? ""

                opacity: status === Loader.Ready ? 1 : 0
                Behavior on opacity {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration
                        easing.type: Easing.OutCubic
                    }
                }

                onLoaded: {
                    if (item) {
                        item.maxContentWidth = contentArea.maxContentWidth;
                        loadedSection = root.currentSection;
                        root.applySubSection();
                    }
                }
            }
        }
    }
}
