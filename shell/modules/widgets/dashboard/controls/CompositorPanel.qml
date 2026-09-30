pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
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

    readonly property var colorNames: Colors.availableColorNames

    property bool colorPickerActive: false
    property var colorPickerColorNames: []
    property string colorPickerCurrentColor: ""
    property string colorPickerDialogTitle: ""
    property var colorPickerCallback: null

    function openColorPicker(colorNames, currentColor, dialogTitle, callback) {
        colorPickerColorNames = colorNames;
        colorPickerCurrentColor = currentColor.toString();
        colorPickerDialogTitle = dialogTitle ? dialogTitle.toString() : "";
        colorPickerCallback = callback;
        colorPickerActive = true;
    }

    function closeColorPicker() {
        colorPickerActive = false;
        colorPickerCallback = null;
    }

    function handleColorSelected(color) {
        if (colorPickerCallback) {
            colorPickerCallback(color);
        }
        colorPickerCurrentColor = color;
    }

    component ToggleRow: SettingsToggleRow {}


    component DecimalInputRow: SettingsNumberInputRow {
        decimals: 2
        maxValue: 1
    }

    component BorderGradientRow: ColumnLayout {
        id: gradientRow
        property string label: ""
        property var colors: []
        property string dialogTitle: ""
        property bool enabled: true
        signal colorsEdited(var newColors)

        spacing: 8
        Layout.fillWidth: true
        opacity: enabled ? 1.0 : 0.5

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: gradientRow.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overBackground
                Layout.fillWidth: true
            }
            Text {
                text: "Right click to remove"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
                visible: gradientRow.colors.length > 1
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                id: colorsRepeater
                model: gradientRow.colors
                delegate: MouseArea {
                    width: 32
                    height: 32
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    required property int index
                    required property var modelData

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Colors.resolve(parent.modelData)
                        border.width: 2
                        border.color: parent.containsMouse ? Styling.srItem("overprimary") : Colors.outline

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - 4
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: Colors.surface
                            opacity: 0.3
                        }
                    }

                    StyledToolTip {
                        text: parent.modelData.toString()
                        visible: parent.containsMouse && !contextMenu.visible
                    }

                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (gradientRow.colors.length > 1) {
                                let newColors = [...gradientRow.colors];
                                newColors.splice(index, 1);
                                gradientRow.colorsEdited(newColors);
                            }
                        } else {
                            root.openColorPicker(root.colorNames, modelData, gradientRow.dialogTitle, function (selectedColor) {
                                let newColors = [...gradientRow.colors];
                                newColors[index] = selectedColor;
                                gradientRow.colorsEdited(newColors);
                            });
                        }
                    }
                }
            }
            StyledRect {
                width: 32
                height: 32
                radius: 16
                variant: "common"
                color: mouseAreaAdd.containsMouse ? Colors.surfaceBright : Colors.surface
                border.width: 1
                border.color: Colors.outline

                Text {
                    anchors.centerIn: parent
                    text: Icons.plus
                    font.family: Icons.font
                    font.pixelSize: 16
                    color: Colors.overSurfaceVariant
                }

                MouseArea {
                    id: mouseAreaAdd
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        let newColors = [...gradientRow.colors];
                        let colorToAdd = newColors.length > 0 ? newColors[newColors.length - 1] : "primary";
                        newColors.push(colorToAdd);
                        gradientRow.colorsEdited(newColors);
                    }
                }
            }
        }
    }

    component CompositorTabButton: StyledRect {
        id: tabBtn
        property string label: ""
        property string icon: ""
        property string image: ""
        property bool isSelected: false
        signal clicked

        variant: isSelected ? "primary" : (hoverHandler.hovered ? "focus" : "common")
        Layout.preferredWidth: 140
        Layout.preferredHeight: 36
        radius: isSelected ? Styling.radius(0) / 2 : Styling.radius(0)
        enableShadow: true

        HoverHandler {
            id: hoverHandler
        }
        TapHandler {
            onTapped: tabBtn.clicked()
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: 8

            Image {
                mipmap: true
                visible: tabBtn.image !== ""
                source: tabBtn.image
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                sourceSize: Qt.size(32, 32)
                fillMode: Image.PreserveAspectFit
                smooth: true

                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: tabBtn.item
                }
            }

            Text {
                visible: tabBtn.icon !== "" && tabBtn.image === ""
                text: tabBtn.icon
                font.family: Icons.font
                font.pixelSize: 14
                color: tabBtn.item
            }

            Text {
                text: tabBtn.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                font.bold: true
                color: tabBtn.item
            }
        }
    }

    Flickable {
        id: mainFlickable
        anchors.fill: parent
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: !root.colorPickerActive

        opacity: root.colorPickerActive ? 0 : 1
        transform: Translate {
            x: root.colorPickerActive ? -30 : 0

            Behavior on x {
                enabled: Styling.animDuration > 0
                NumberAnimation {
                    duration: Styling.animDuration / 2
                    easing.type: Easing.OutQuart
                }
            }
        }

        Behavior on opacity {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration / 2
                easing.type: Easing.OutQuart
            }
        }

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
                    title: root.currentSection === "" ? "Compositor" : (root.currentSection.charAt(0).toUpperCase() + root.currentSection.slice(1))
                    statusText: GlobalStates.compositorHasChanges ? "Unsaved changes" : ""
                    statusColor: Colors.error

                    actions: {
                        let baseActions = [
                            {
                                icon: Icons.arrowCounterClockwise,
                                tooltip: "Discard changes",
                                enabled: GlobalStates.compositorHasChanges,
                                onClicked: function () {
                                    GlobalStates.discardCompositorChanges();
                                }
                            },
                            {
                                icon: Icons.disk,
                                tooltip: "Apply changes",
                                enabled: GlobalStates.compositorHasChanges,
                                onClicked: function () {
                                    GlobalStates.applyCompositorChanges();
                                }
                            }
                        ];

                        if (root.currentSection !== "") {
                            return [
                                {
                                    icon: Icons.arrowLeft,
                                    tooltip: "Back",
                                    onClicked: function () {
                                        root.currentSection = "";
                                    }
                                }
                            ].concat(baseActions);
                        }

                        return baseActions;
                    }
                }
            }

            Item {
                visible: root.currentSection === ""
                Layout.fillWidth: true
                Layout.preferredHeight: 40

                CompositorTabButton {
                    anchors.centerIn: parent
                    label: "Hyprland"
                    image: Paths.assetUrl("compositors/hyprland.svg")
                    isSelected: true
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: stackLayout.height

                StackLayout {
                    id: stackLayout
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: compositorPage.implicitHeight
                    currentIndex: 0

                    ColumnLayout {
                        id: compositorPage
                        Layout.fillWidth: true
                        spacing: 16

                        ColumnLayout {
                            visible: root.currentSection === ""
                            Layout.fillWidth: true
                            spacing: 8

                            SectionButton {
                                text: "General"
                                sectionId: "general"
                            }
                            SectionButton {
                                text: "Colors"
                                sectionId: "colors"
                            }
                            SectionButton {
                                text: "Shadows"
                                sectionId: "shadows"
                            }
                            SectionButton {
                                text: "Blur"
                                sectionId: "blur"
                            }
                        }

                        ColumnLayout {
                            visible: root.currentSection === "general"
                            property string settingsSection: "general"
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "General"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overSurfaceVariant
                                Layout.bottomMargin: -4
                            }

                            ToggleRow {
                                label: "Sync Border Size"
                                checked: Config.compositor.syncBorderWidth ?? false
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.syncBorderWidth = value;
                                }
                            }

                            SettingsNumberInputRow {
                                label: "Border Size"
                                value: Config.compositor.borderSize ?? 2
                                minValue: 0
                                maxValue: 999
                                suffix: "px"
                                enabled: !Config.compositor.syncBorderWidth
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.borderSize = newValue;
                                }
                            }

                            ToggleRow {
                                label: "Sync Rounding"
                                checked: Config.compositor.syncRoundness ?? true
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.syncRoundness = value;
                                }
                            }

                            SettingsNumberInputRow {
                                label: "Rounding"
                                value: Config.compositor.rounding ?? 16
                                minValue: 0
                                maxValue: 999
                                suffix: "px"
                                enabled: !Config.compositor.syncRoundness
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.rounding = newValue;
                                }
                            }

                            SettingsNumberInputRow {
                                label: "Gaps In"
                                value: Config.compositor.gapsIn ?? 5
                                minValue: 0
                                maxValue: 50
                                suffix: "px"
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.gapsIn = newValue;
                                }
                            }

                            SettingsNumberInputRow {
                                label: "Gaps Out"
                                value: Config.compositor.gapsOut ?? 10
                                minValue: 0
                                maxValue: 50
                                suffix: "px"
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.gapsOut = newValue;
                                }
                            }

                            SettingsNumberInputRow {
                                label: "Border Angle"
                                value: Config.compositor.borderAngle ?? 45
                                minValue: 0
                                maxValue: 360
                                suffix: "deg"
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.borderAngle = newValue;
                                }
                            }

                            SettingsNumberInputRow {
                                label: "Inactive Angle"
                                value: Config.compositor.inactiveBorderAngle ?? 45
                                minValue: 0
                                maxValue: 360
                                suffix: "deg"
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.inactiveBorderAngle = newValue;
                                }
                            }
                        }

                        Separator {
                            Layout.fillWidth: true
                            visible: false
                        }

                        ColumnLayout {
                            visible: root.currentSection === "colors"
                            property string settingsSection: "colors"
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Colors"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overSurfaceVariant
                                Layout.bottomMargin: -4
                            }

                            ToggleRow {
                                label: "Sync Border Color"
                                checked: Config.compositor.syncBorderColor ?? false
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.syncBorderColor = value;
                                }
                            }

                            BorderGradientRow {
                                label: "Active Border"
                                colors: Config.compositor.activeBorderColor || ["primary"]
                                dialogTitle: "Edit Active Border Color"
                                enabled: !Config.compositor.syncBorderColor
                                onColorsEdited: newColors => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.activeBorderColor = newColors;
                                }
                            }

                            BorderGradientRow {
                                label: "Inactive Border"
                                colors: Config.compositor.inactiveBorderColor || ["surface"]
                                dialogTitle: "Edit Inactive Border Color"
                                onColorsEdited: newColors => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.inactiveBorderColor = newColors;
                                }
                            }
                        }

                        Separator {
                            Layout.fillWidth: true
                            visible: false
                        }

                        ColumnLayout {
                            visible: root.currentSection === "shadows"
                            property string settingsSection: "shadows"
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Shadows"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overSurfaceVariant
                                Layout.bottomMargin: -4
                            }

                            ToggleRow {
                                label: "Enabled"
                                checked: Config.compositor.shadowEnabled ?? true
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.shadowEnabled = value;
                                }
                            }

                            ToggleRow {
                                label: "Sync Color"
                                checked: Config.compositor.syncShadowColor ?? false
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.syncShadowColor = value;
                                }
                            }

                            ToggleRow {
                                label: "Sync Opacity"
                                checked: Config.compositor.syncShadowOpacity ?? false
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.syncShadowOpacity = value;
                                }
                            }

                            SettingsNumberInputRow {
                                label: "Range"
                                value: Config.compositor.shadowRange ?? 4
                                minValue: 0
                                maxValue: 100
                                suffix: "px"
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.shadowRange = newValue;
                                }
                            }

                            SettingsNumberInputRow {
                                label: "Offset X"
                                value: parseInt((Config.compositor.shadowOffset ?? "0 0").split(" ")[0]) || 0
                                minValue: -50
                                maxValue: 50
                                suffix: "px"
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    let parts = (Config.compositor.shadowOffset ?? "0 0").split(" ");
                                    let y = parts.length > 1 ? parts[1] : "0";
                                    Config.compositor.shadowOffset = newValue + " " + y;
                                }
                            }

                            SettingsNumberInputRow {
                                label: "Offset Y"
                                value: parseInt((Config.compositor.shadowOffset ?? "0 0").split(" ")[1]) || 0
                                minValue: -50
                                maxValue: 50
                                suffix: "px"
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    let parts = (Config.compositor.shadowOffset ?? "0 0").split(" ");
                                    let x = parts.length > 0 ? parts[0] : "0";
                                    Config.compositor.shadowOffset = x + " " + newValue;
                                }
                            }

                            SettingsNumberInputRow {
                                label: "Render Power"
                                value: Config.compositor.shadowRenderPower ?? 3
                                minValue: 1
                                maxValue: 4
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.shadowRenderPower = newValue;
                                }
                            }

                            DecimalInputRow {
                                label: "Scale"
                                value: Config.compositor.shadowScale ?? 1.0
                                minValue: 0.0
                                maxValue: 1.0
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.shadowScale = newValue;
                                }
                            }

                            DecimalInputRow {
                                label: "Opacity"
                                value: Config.compositor.shadowOpacity ?? 0.5
                                minValue: 0.0
                                maxValue: 1.0
                                enabled: !Config.compositor.syncShadowOpacity
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.shadowOpacity = newValue;
                                }
                            }

                            ToggleRow {
                                label: "Sharp"
                                checked: Config.compositor.shadowSharp ?? false
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.shadowSharp = value;
                                }
                            }
                        }

                        Separator {
                            Layout.fillWidth: true
                            visible: false
                        }

                        ColumnLayout {
                            visible: root.currentSection === "blur"
                            property string settingsSection: "blur"
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Blur"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overSurfaceVariant
                                Layout.bottomMargin: -4
                            }

                            ToggleRow {
                                label: "Enabled"
                                checked: Config.compositor.blurEnabled ?? true
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurEnabled = value;
                                }
                            }

                            SettingsNumberInputRow {
                                label: "Size"
                                value: Config.compositor.blurSize ?? 8
                                minValue: 0
                                maxValue: 20
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurSize = newValue;
                                }
                            }

                            SettingsNumberInputRow {
                                label: "Passes"
                                value: Config.compositor.blurPasses ?? 1
                                minValue: 0
                                maxValue: 4
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurPasses = newValue;
                                }
                            }

                            ToggleRow {
                                label: "Xray"
                                checked: Config.compositor.blurXray ?? false
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurXray = value;
                                }
                            }

                            ToggleRow {
                                label: "New Optimizations"
                                checked: Config.compositor.blurNewOptimizations ?? true
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurNewOptimizations = value;
                                }
                            }

                            ToggleRow {
                                label: "Blur Special Workspaces"
                                checked: Config.compositor.blurSpecial ?? true
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurSpecial = value;
                                }
                            }

                            ToggleRow {
                                label: "Blur Popups"
                                checked: Config.compositor.blurPopups ?? false
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurPopups = value;
                                }
                            }

                            ToggleRow {
                                label: "Ignore Opacity"
                                checked: Config.compositor.blurIgnoreOpacity ?? true
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurIgnoreOpacity = value;
                                }
                            }

                            ToggleRow {
                                label: "Explicit Ignorealpha"
                                checked: Config.compositor.blurExplicitIgnoreAlpha ?? false
                                onToggled: value => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurExplicitIgnoreAlpha = value;
                                }
                            }

                            DecimalInputRow {
                                label: "Ignorealpha Value"
                                value: Config.compositor.blurIgnoreAlphaValue ?? 0.2
                                minValue: 0.0
                                maxValue: 1.0
                                enabled: Config.compositor.blurExplicitIgnoreAlpha
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurIgnoreAlphaValue = newValue;
                                }
                            }

                            DecimalInputRow {
                                label: "Noise"
                                value: Config.compositor.blurNoise ?? 0.01
                                minValue: 0.0
                                maxValue: 1.0
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurNoise = newValue;
                                }
                            }

                            DecimalInputRow {
                                label: "Contrast"
                                value: Config.compositor.blurContrast ?? 0.89
                                minValue: 0.0
                                maxValue: 2.0
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurContrast = newValue;
                                }
                            }

                            DecimalInputRow {
                                label: "Brightness"
                                value: Config.compositor.blurBrightness ?? 0.81
                                minValue: 0.0
                                maxValue: 2.0
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurBrightness = newValue;
                                }
                            }

                            DecimalInputRow {
                                label: "Vibrancy"
                                value: Config.compositor.blurVibrancy ?? 0.17
                                minValue: 0.0
                                maxValue: 1.0
                                onValueEdited: newValue => {
                                    GlobalStates.markCompositorChanged();
                                    Config.compositor.blurVibrancy = newValue;
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
    }

    Item {
        id: colorPickerContainer
        anchors.fill: parent
        clip: true

        opacity: root.colorPickerActive ? 1 : 0
        transform: Translate {
            x: root.colorPickerActive ? 0 : 30

            Behavior on x {
                enabled: Styling.animDuration > 0
                NumberAnimation {
                    duration: Styling.animDuration / 2
                    easing.type: Easing.OutQuart
                }
            }
        }

        Behavior on opacity {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration / 2
                easing.type: Easing.OutQuart
            }
        }

        enabled: root.colorPickerActive

        MouseArea {
            anchors.fill: parent
            enabled: root.colorPickerActive
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onPressed: event => event.accepted = true
            onReleased: event => event.accepted = true
            onWheel: event => event.accepted = true
        }

        ColorPickerView {
            id: colorPickerContent
            anchors.fill: parent
            anchors.leftMargin: root.sideMargin
            anchors.rightMargin: root.sideMargin
            colorNames: root.colorPickerColorNames
            currentColor: root.colorPickerCurrentColor
            dialogTitle: root.colorPickerDialogTitle

            onColorSelected: color => root.handleColorSelected(color)
            onClosed: root.closeColorPicker()
        }
    }
}
