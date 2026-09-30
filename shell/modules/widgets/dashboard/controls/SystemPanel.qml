pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    property string currentSection: ""

    component SectionButton: SettingsSectionButton {
        onActivated: id => root.currentSection = id
    }

    Flickable {
        id: mainFlickable
        anchors.fill: parent
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: mainColumn
            width: mainFlickable.width
            spacing: 8

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: titlebar.height

                PanelTitlebar {
                    id: titlebar
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    title: root.currentSection === "" ? "System" : (root.currentSection === "system" ? "System Resources" : (root.currentSection === "daynight" ? "Day & Night" : (root.currentSection.charAt(0).toUpperCase() + root.currentSection.slice(1))))
                    statusText: ""

                    actions: {
                        if (root.currentSection !== "") {
                            return [
                                {
                                    icon: Icons.arrowLeft,
                                    tooltip: "Back",
                                    onClicked: function () {
                                        root.currentSection = "";
                                    }
                                }
                            ];
                        }
                        return [];
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: contentColumn.implicitHeight

                ColumnLayout {
                    id: contentColumn
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16

                    ColumnLayout {
                        visible: root.currentSection === ""
                        Layout.fillWidth: true
                        spacing: 8

                        SectionButton {
                            text: "Prefixes"
                            sectionId: "prefixes"
                        }
                        SectionButton {
                            text: "Weather"
                            sectionId: "weather"
                        }
                        SectionButton {
                            text: "Performance"
                            sectionId: "performance"
                        }
                        SectionButton {
                            text: "System Resources"
                            sectionId: "system"
                        }
                        SectionButton {
                            text: "Idle"
                            sectionId: "idle"
                        }
                        SectionButton {
                            text: "Recording"
                            sectionId: "recording"
                        }
                        SectionButton {
                            text: "Wallpaper"
                            sectionId: "wallpaper"
                        }
                        SectionButton {
                            text: "Day & Night"
                            sectionId: "daynight"
                        }
                        SectionButton {
                            text: "Notifications"
                            sectionId: "notifications"
                        }
                        SectionButton {
                            text: "Pomodoro"
                            sectionId: "pomodoro"
                        }
                    }

                    ColumnLayout {
                        visible: root.currentSection === "prefixes"
                        property string settingsSection: "prefixes"
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Prefixes"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overSurfaceVariant
                            Layout.bottomMargin: -4
                        }

                        Text {
                            text: "Keyboard shortcuts for quick actions in launcher"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overSurfaceVariant
                            opacity: 0.7
                        }

                        PrefixRow {
                            Layout.fillWidth: true
                            label: "Clipboard"
                            prefixValue: Config.prefix.clipboard
                            onPrefixEdited: newValue => {
                                Config.prefix.clipboard = newValue;
                            }
                        }

                        PrefixRow {
                            Layout.fillWidth: true
                            label: "Emoji"
                            prefixValue: Config.prefix.emoji
                            onPrefixEdited: newValue => {
                                Config.prefix.emoji = newValue;
                            }
                        }

                        PrefixRow {
                            Layout.fillWidth: true
                            label: "Tmux"
                            prefixValue: Config.prefix.tmux
                            onPrefixEdited: newValue => {
                                Config.prefix.tmux = newValue;
                            }
                        }

                        PrefixRow {
                            Layout.fillWidth: true
                            label: "Wallpapers"
                            prefixValue: Config.prefix.wallpapers
                            onPrefixEdited: newValue => {
                                Config.prefix.wallpapers = newValue;
                            }
                        }

                        PrefixRow {
                            Layout.fillWidth: true
                            label: "Notes"
                            prefixValue: Config.prefix.notes
                            onPrefixEdited: newValue => {
                                Config.prefix.notes = newValue;
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.currentSection === "weather"
                        property string settingsSection: "weather"
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Weather"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overSurfaceVariant
                            Layout.bottomMargin: -4
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Location"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                                color: Colors.overBackground
                                Layout.preferredWidth: 100
                            }

                            StyledRect {
                                variant: "common"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                radius: Styling.radius(-2)

                                TextInput {
                                    id: locationInput
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(0)
                                    color: Colors.overBackground
                                    selectByMouse: true
                                    clip: true
                                    verticalAlignment: TextInput.AlignVCenter

                                    readonly property string configValue: Config.weather.location

                                    onConfigValueChanged: {
                                        if (text !== configValue) {
                                            text = configValue;
                                        }
                                    }

                                    Component.onCompleted: text = configValue

                                    onEditingFinished: {
                                        if (text !== Config.weather.location) {
                                            Config.weather.location = text.trim();
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !locationInput.text && !locationInput.activeFocus
                                        text: "e.g. Buenos Aires, Tokyo..."
                                        font: locationInput.font
                                        color: Colors.overSurfaceVariant
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Unit"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                                color: Colors.overBackground
                                Layout.preferredWidth: 100
                            }

                            Row {
                                spacing: 8

                                Repeater {
                                    model: [
                                        {
                                            id: "C",
                                            label: "Celsius"
                                        },
                                        {
                                            id: "F",
                                            label: "Fahrenheit"
                                        }
                                    ]

                                    delegate: StyledRect {
                                        id: unitButton
                                        required property var modelData
                                        required property int index

                                        property bool isSelected: Config.weather.unit === modelData.id
                                        property bool isHovered: false

                                        variant: isSelected ? "primary" : (isHovered ? "focus" : "common")
                                        width: unitLabel.width + 24
                                        height: 36
                                        radius: Styling.radius(-2)

                                        Text {
                                            id: unitLabel
                                            anchors.centerIn: parent
                                            text: unitButton.modelData.label
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(0)
                                            font.weight: unitButton.isSelected ? Font.Bold : Font.Normal
                                            color: unitButton.item
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: unitButton.isHovered = true
                                            onExited: unitButton.isHovered = false
                                            onClicked: Config.weather.unit = unitButton.modelData.id
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.currentSection === "performance"
                        property string settingsSection: "performance"
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Performance"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overSurfaceVariant
                            Layout.bottomMargin: -4
                        }

                        Text {
                            text: "Toggle visual effects to improve performance"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overSurfaceVariant
                            opacity: 0.7
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Blur Transition"
                            description: "Animated blur when opening panels"
                            checked: Config.performance.blurTransition
                            onToggled: checked => {
                                Config.performance.blurTransition = checked;
                            }
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Window Preview"
                            description: "Show window thumbnails in overview"
                            checked: Config.performance.windowPreview
                            onToggled: checked => {
                                Config.performance.windowPreview = checked;
                            }
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Wavy Line"
                            description: "Animated wavy line effect"
                            checked: Config.performance.wavyLine
                            onToggled: checked => {
                                Config.performance.wavyLine = checked;
                            }
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Audio Visualizer"
                            description: "Animated bars in the media player"
                            checked: Config.performance.audioVisualizer
                            onToggled: checked => {
                                Config.performance.audioVisualizer = checked;
                            }
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Persist Dashboard Tabs"
                            description: "Keep dashboard tabs loaded in the background"
                            checked: Config.performance.dashboardPersistTabs
                            onToggled: checked => {
                                Config.performance.dashboardPersistTabs = checked;
                            }
                        }

                        SettingsNumberInputRow {
                            label: "Max Persistent Tabs"
                            value: Config.performance.dashboardMaxPersistentTabs
                            minValue: 1
                            maxValue: 3
                            onValueEdited: newValue => {
                                Config.performance.dashboardMaxPersistentTabs = newValue;
                            }
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Disable Cover Art Rotation"
                            description: "Stop the vinyl disc from spinning"
                            checked: !Config.performance.rotateCoverArt
                            onToggled: checked => {
                                Config.performance.rotateCoverArt = !checked;
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.currentSection === "system"
                        property string settingsSection: "system"
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "System Resources"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overSurfaceVariant
                            Layout.bottomMargin: -4
                        }

                        Text {
                            text: "Configure which disks to monitor"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overSurfaceVariant
                            opacity: 0.7
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                id: disksRepeater
                                model: Config.system.disks

                                delegate: RowLayout {
                                    id: diskRow
                                    required property string modelData
                                    required property int index

                                    Layout.fillWidth: true
                                    spacing: 8

                                    StyledRect {
                                        variant: "common"
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36
                                        radius: Styling.radius(-2)

                                        TextInput {
                                            id: diskInput
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            font.family: Config.theme.monoFont
                                            font.pixelSize: Styling.monoFontSize(0)
                                            color: Colors.overBackground
                                            selectByMouse: true
                                            clip: true
                                            verticalAlignment: TextInput.AlignVCenter
                                            text: diskRow.modelData

                                            onEditingFinished: {
                                                if (text.trim() !== diskRow.modelData) {
                                                    let newDisks = Config.system.disks.slice();
                                                    newDisks[diskRow.index] = text.trim();
                                                    Config.system.disks = newDisks;
                                                }
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: !diskInput.text && !diskInput.activeFocus
                                                text: "e.g. /, /home..."
                                                font: diskInput.font
                                                color: Colors.overSurfaceVariant
                                            }
                                        }
                                    }

                                    StyledRect {
                                        id: removeDiskButton
                                        variant: removeDiskArea.containsMouse ? "focus" : "common"
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 36
                                        radius: Styling.radius(-2)
                                        visible: disksRepeater.count > 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: Icons.trash
                                            font.family: Icons.font
                                            font.pixelSize: 14
                                            color: Colors.error
                                        }

                                        MouseArea {
                                            id: removeDiskArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                let newDisks = Config.system.disks.slice();
                                                newDisks.splice(diskRow.index, 1);
                                                Config.system.disks = newDisks;
                                            }
                                        }

                                        StyledToolTip {
                                            visible: removeDiskArea.containsMouse
                                            tooltipText: "Remove disk"
                                        }
                                    }
                                }
                            }

                            StyledRect {
                                id: addDiskButton
                                variant: addDiskArea.containsMouse ? "primaryfocus" : "primary"
                                Layout.preferredWidth: addDiskContent.width + 24
                                Layout.preferredHeight: 36
                                radius: Styling.radius(-2)

                                Row {
                                    id: addDiskContent
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: Icons.plus
                                        font.family: Icons.font
                                        font.pixelSize: 14
                                        color: addDiskButton.item
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: "Add Disk"
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(0)
                                        color: addDiskButton.item
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: addDiskArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        let newDisks = Config.system.disks.slice();
                                        newDisks.push("/");
                                        Config.system.disks = newDisks;
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.currentSection === "idle"
                        property string settingsSection: "idle"
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Idle"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overSurfaceVariant
                            Layout.bottomMargin: -4
                        }

                        ToggleRow {
                            label: "Idle Actions"
                            description: "Master switch for all idle timers below"
                            checked: Config.system.idle.enabled ?? false
                            onToggled: checked => {
                                Config.system.idle.enabled = checked;
                            }
                        }

                        ToggleRow {
                            label: "Lock on Sleep"
                            description: "Lock before the system suspends"
                            checked: (Config.system.idle.general.before_sleep_cmd ?? "") !== ""
                            onToggled: checked => {
                                Config.system.idle.general.before_sleep_cmd = checked ? "loginctl lock-session" : "";
                            }
                        }

                        ToggleRow {
                            label: "Lock When Idle"
                            checked: Config.system.idle.lock.enabled ?? true
                            onToggled: checked => {
                                Config.system.idle.lock.enabled = checked;
                            }
                        }

                        SettingsNumberInputRow {
                            label: "Lock After"
                            value: Config.system.idle.lock.timeout ?? 300
                            minValue: 10
                            maxValue: 14400
                            suffix: "s"
                            onValueEdited: newValue => {
                                Config.system.idle.lock.timeout = newValue;
                            }
                        }

                        ToggleRow {
                            label: "Screen Off When Idle"
                            checked: Config.system.idle.screenOff.enabled ?? true
                            onToggled: checked => {
                                Config.system.idle.screenOff.enabled = checked;
                            }
                        }

                        SettingsNumberInputRow {
                            label: "Screen Off After"
                            value: Config.system.idle.screenOff.timeout ?? 330
                            minValue: 10
                            maxValue: 14400
                            suffix: "s"
                            onValueEdited: newValue => {
                                Config.system.idle.screenOff.timeout = newValue;
                            }
                        }

                        ToggleRow {
                            label: "Suspend When Idle"
                            checked: Config.system.idle.suspend.enabled ?? false
                            onToggled: checked => {
                                Config.system.idle.suspend.enabled = checked;
                            }
                        }

                        SettingsNumberInputRow {
                            label: "Suspend After"
                            value: Config.system.idle.suspend.timeout ?? 1800
                            minValue: 60
                            maxValue: 28800
                            suffix: "s"
                            onValueEdited: newValue => {
                                Config.system.idle.suspend.timeout = newValue;
                            }
                        }

                        SettingsTextInputRow {
                            label: "Lock Cmd"
                            value: Config.system.idle.general.lock_cmd ?? ""
                            placeholder: "Command to lock screen"
                            onValueEdited: newValue => {
                                if (newValue !== Config.system.idle.general.lock_cmd) {
                                    Config.system.idle.general.lock_cmd = newValue;
                                }
                            }
                        }

                        SettingsTextInputRow {
                            label: "After Sleep"
                            value: Config.system.idle.general.after_sleep_cmd ?? ""
                            placeholder: "Command after sleep"
                            onValueEdited: newValue => {
                                if (newValue !== Config.system.idle.general.after_sleep_cmd) {
                                    Config.system.idle.general.after_sleep_cmd = newValue;
                                }
                            }
                        }

                        Text {
                            text: "Custom Listeners"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: Colors.overBackground
                            Layout.topMargin: 8
                        }

                        Repeater {
                            model: Config.system.idle.listeners

                            delegate: ColumnLayout {
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                spacing: 4
                                Layout.bottomMargin: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: Colors.surfaceBright
                                    visible: index > 0
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Listener " + (index + 1)
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                        font.bold: true
                                        color: Styling.srItem("overprimary")
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    StyledRect {
                                        id: deleteListenerBtn
                                        variant: "error"
                                        Layout.preferredWidth: 24
                                        Layout.preferredHeight: 24
                                        radius: Styling.radius(-2)

                                        Text {
                                            anchors.centerIn: parent
                                            text: Icons.trash
                                            font.family: Icons.font
                                            color: deleteListenerBtn.item
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var list = [];
                                                for (var i = 0; i < Config.system.idle.listeners.length; i++)
                                                    list.push(Config.system.idle.listeners[i]);
                                                list.splice(index, 1);
                                                Config.system.idle.listeners = list;
                                            }
                                        }
                                    }
                                }

                                SettingsNumberInputRow {
                                    label: "Timeout (s)"
                                    value: modelData.timeout || 0
                                    minValue: 1
                                    maxValue: 7200
                                    onValueEdited: val => {
                                        var list = [];
                                        for (var i = 0; i < Config.system.idle.listeners.length; i++)
                                            list.push(Config.system.idle.listeners[i]);
                                        list[index].timeout = val;
                                        Config.system.idle.listeners = list;
                                    }
                                }

                                SettingsTextInputRow {
                                    label: "On Timeout"
                                    value: modelData.onTimeout || ""
                                    onValueEdited: val => {
                                        var list = [];
                                        for (var i = 0; i < Config.system.idle.listeners.length; i++)
                                            list.push(Config.system.idle.listeners[i]);
                                        list[index].onTimeout = val;
                                        Config.system.idle.listeners = list;
                                    }
                                }

                                SettingsTextInputRow {
                                    label: "On Resume"
                                    value: modelData.onResume || ""
                                    onValueEdited: val => {
                                        var list = [];
                                        for (var i = 0; i < Config.system.idle.listeners.length; i++)
                                            list.push(Config.system.idle.listeners[i]);
                                        list[index].onResume = val;
                                        Config.system.idle.listeners = list;
                                    }
                                }
                            }
                        }

                        StyledRect {
                            id: addListenerBtn
                            variant: "common"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: Styling.radius(-2)

                            Text {
                                anchors.centerIn: parent
                                text: "Add Listener"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                                font.bold: true
                                color: addListenerBtn.item
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var list = [];
                                    if (Config.system.idle.listeners) {
                                        for (var i = 0; i < Config.system.idle.listeners.length; i++)
                                            list.push(Config.system.idle.listeners[i]);
                                    }
                                    list.push({
                                        "timeout": 60,
                                        "onTimeout": "",
                                        "onResume": ""
                                    });
                                    Config.system.idle.listeners = list;
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.currentSection === "recording"
                        property string settingsSection: "recording"
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Recording"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overSurfaceVariant
                            Layout.bottomMargin: -4
                        }

                        SettingsNumberInputRow {
                            label: "Replay Buffer Length"
                            value: Config.system.replay.seconds
                            minValue: 5
                            maxValue: 600
                            suffix: "s"
                            onValueEdited: newValue => {
                                Config.system.replay.seconds = newValue;
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.currentSection === "wallpaper"
                        property string settingsSection: "wallpaper"
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Wallpaper"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overSurfaceVariant
                            Layout.bottomMargin: -4
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Slideshow"
                            description: "Cycle wallpapers automatically"
                            checked: WallpaperSlideshowService.enabled
                            onToggled: checked => {
                                WallpaperSlideshowService.toggle();
                            }
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Shuffle"
                            description: "Pick the next wallpaper at random"
                            checked: WallpaperSlideshowService.shuffle
                            onToggled: checked => {
                                WallpaperSlideshowService.shuffle = checked;
                            }
                        }

                        SettingsNumberInputRow {
                            label: "Interval"
                            value: Config.system.slideshow.minutes
                            minValue: 1
                            maxValue: 1440
                            suffix: "min"
                            onValueEdited: newValue => {
                                Config.system.slideshow.minutes = newValue;
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.currentSection === "daynight"
                        property string settingsSection: "daynight"
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Day & Night"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overSurfaceVariant
                            Layout.bottomMargin: -4
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Auto Theme"
                            description: "Switch between light and dark on schedule"
                            checked: AutoThemeService.enabled
                            onToggled: checked => {
                                AutoThemeService.toggle();
                            }
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Use Sunrise and Sunset"
                            description: "Use weather times when available; otherwise use the times below"
                            checked: Config.system.autoTheme.useSunriseSunset
                            onToggled: checked => Config.system.autoTheme.useSunriseSunset = checked
                        }

                        SettingsTextInputRow {
                            label: "Day Starts"
                            value: Config.system.autoTheme.dayStart
                            placeholder: "HH:MM"
                            onValueEdited: newValue => {
                                if (newValue !== Config.system.autoTheme.dayStart) {
                                    Config.system.autoTheme.dayStart = newValue;
                                }
                            }
                        }

                        SettingsTextInputRow {
                            label: "Night Starts"
                            value: Config.system.autoTheme.nightStart
                            placeholder: "HH:MM"
                            onValueEdited: newValue => {
                                if (newValue !== Config.system.autoTheme.nightStart) {
                                    Config.system.autoTheme.nightStart = newValue;
                                }
                            }
                        }

                        SettingsNumberInputRow {
                            label: "Night Light Temperature"
                            value: Config.system.nightLight.temperature
                            minValue: 1000
                            maxValue: 6500
                            suffix: "K"
                            onValueEdited: newValue => {
                                Config.system.nightLight.temperature = newValue;
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.currentSection === "notifications"
                        property string settingsSection: "notifications"
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Notifications"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overSurfaceVariant
                            Layout.bottomMargin: -4
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Do Not Disturb"
                            description: "Silence popups, notifications still reach history"
                            checked: Notifications.silent
                            onToggled: checked => {
                                Notifications.silent = checked;
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.currentSection === "pomodoro"
                        property string settingsSection: "pomodoro"
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Pomodoro"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overSurfaceVariant
                            Layout.bottomMargin: -4
                        }

                        SettingsNumberInputRow {
                            label: "Work Session"
                            value: Config.system.pomodoro.workTime
                            minValue: 60
                            maxValue: 7200
                            suffix: "s"
                            onValueEdited: newValue => {
                                Config.system.pomodoro.workTime = newValue;
                            }
                        }

                        SettingsNumberInputRow {
                            label: "Rest Session"
                            value: Config.system.pomodoro.restTime
                            minValue: 60
                            maxValue: 3600
                            suffix: "s"
                            onValueEdited: newValue => {
                                Config.system.pomodoro.restTime = newValue;
                            }
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Auto Start Next"
                            description: "Begin the next session automatically"
                            checked: Config.system.pomodoro.autoStart
                            onToggled: checked => {
                                Config.system.pomodoro.autoStart = checked;
                            }
                        }

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Sync Spotify"
                            description: "Play on work, pause on rest"
                            checked: Config.system.pomodoro.syncSpotify
                            onToggled: checked => {
                                Config.system.pomodoro.syncSpotify = checked;
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 16
                    }
                }
            }
        }
    }



    component PrefixRow: SettingsTextInputRow {
        id: prefixRow
        property alias prefixValue: prefixRow.value
        signal prefixEdited(string newValue)
        inputWidth: 80
        inputHeight: 36
        monospace: true
        maximumLength: 4
        alignment: TextInput.AlignHCenter
        trimValue: true
        allowEmpty: false
        onValueEdited: newValue => {
            if (newValue !== prefixValue) prefixEdited(newValue);
        }
    }

    component ToggleRow: ColumnLayout {
        id: toggleRowRoot
        property string label: ""
        property string description: ""
        property bool checked: false
        signal toggled(bool checked)

        Layout.fillWidth: true
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: toggleRowRoot.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overBackground
                Layout.fillWidth: true
            }

            Item {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: toggleRowRoot.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                    border.color: toggleRowRoot.checked ? Styling.srItem("overprimary") : Colors.outline

                    Behavior on color {
                        enabled: Styling.animDuration > 0
                        ColorAnimation {
                            duration: Styling.animDuration / 2
                        }
                    }

                    Rectangle {
                        x: toggleRowRoot.checked ? parent.width - width - 2 : 2
                        y: 2
                        width: parent.height - 4
                        height: width
                        radius: width / 2
                        color: toggleRowRoot.checked ? Colors.background : Colors.overSurfaceVariant

                        Behavior on x {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Styling.animDuration / 2
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toggleRowRoot.toggled(!toggleRowRoot.checked)
                }
            }
        }

        Text {
            visible: toggleRowRoot.description !== ""
            text: toggleRowRoot.description
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
            opacity: 0.7
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }
}
