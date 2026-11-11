pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.globals
import qs.config

Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool layerEnabled: true
    property bool flatStyle: false

    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    property bool popupOpen: controlsPopup.isOpen
    property bool showSinks: false
    property bool showSources: false
    property bool showPresets: false

    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    StyledToolTip {
        show: root.isHovered && !root.popupOpen
        tooltipText: "Audio Hub & Controls"
    }

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    StyledRect {
        id: buttonBg
        variant: root.popupOpen ? "primary" : (root.flatStyle ? "transparent" : "bg")
        anchors.fill: parent
        enableShadow: !root.flatStyle && root.layerEnabled

        topLeftRadius: root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.endRadius

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.popupOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Styling.animDuration > 0
                NumberAnimation {
                    duration: Styling.animDuration / 2
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: Icons.faders
            font.family: Icons.font
            font.pixelSize: 18
            color: root.popupOpen ? buttonBg.item : Colors.overBackground
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    controlsPopup.close();
                    GlobalStates.openSettingsSection("mixer", "");
                    return;
                } else if (mouse.button === Qt.LeftButton) {
                    controlsPopup.toggle();
                }
            }
        }
    }

    BarPopup {
        id: controlsPopup
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 14

        contentWidth: 310
        contentHeight: Math.min(540, slidersColumn.implicitHeight + popupPadding * 2)

        onIsOpenChanged: {
            if (isOpen) {
                EasyEffectsService.refresh();
                PeripheralBatteryService.refresh();
            } else {
                root.showSinks = false;
                root.showSources = false;
                root.showPresets = false;
            }
        }

        Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: slidersColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: slidersColumn
                width: parent.width
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        ControlSliderRow {
                            id: volumeRow
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            displayMultiplier: Audio.hardMaxValue * 100

                            icon: Audio.volumeIcon(Audio.value, Audio.sink?.audio?.muted ?? false)
                            sliderValue: Audio.value / Audio.hardMaxValue
                            progressColor: Audio.sink?.audio?.muted ? Colors.outline : Styling.srItem("overprimary")
                            wavy: true
                            wavyAmplitude: Audio.sink?.audio?.muted ? 0.5 : 1.5 * effectiveValue
                            wavyFrequency: Audio.sink?.audio?.muted ? 1.0 : 8.0 * effectiveValue

                            onValueChanged: newValue => Audio.setVolume(newValue * Audio.hardMaxValue)
                            onIconClicked: {
                                if (Audio.sink?.audio)
                                    Audio.sink.audio.muted = !Audio.sink.audio.muted;
                            }
                        }

                        StyledRect {
                            id: sinkToggleBtn
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            radius: Styling.radius(-4)
                            variant: root.showSinks ? "primary" : (sinkBtnMa.containsMouse ? "focus" : "common")
                            enableShadow: false
                            visible: Audio.outputDevices.length > 1

                            Text {
                                anchors.centerIn: parent
                                text: root.showSinks ? Icons.caretUp : Icons.caretDown
                                font.family: Icons.font
                                font.pixelSize: 12
                                color: sinkToggleBtn.item
                            }

                            MouseArea {
                                id: sinkBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showSinks = !root.showSinks
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 32
                        text: Audio.friendlyDeviceName(Audio.sink)
                        textFormat: Text.PlainText
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        elide: Text.ElideRight
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        visible: root.showSinks

                        Repeater {
                            model: Audio.outputDevices

                            delegate: StyledRect {
                                id: sinkItem
                                required property var modelData
                                readonly property bool active: Audio.sink?.id === modelData?.id
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: Styling.radius(-4)
                                variant: active ? "primary" : (sinkItemMa.containsMouse ? "focus" : "internalbg")
                                enableShadow: false

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    Text {
                                        text: sinkItem.active ? Icons.accept : Icons.speakerHigh
                                        font.family: Icons.font
                                        font.pixelSize: 13
                                        color: sinkItem.item
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: Audio.friendlyDeviceName(sinkItem.modelData)
                                        textFormat: Text.PlainText
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                        color: sinkItem.item
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: sinkItemMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Audio.setDefaultSink(sinkItem.modelData);
                                        root.showSinks = false;
                                    }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        ControlSliderRow {
                            id: micRow
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            displayMultiplier: Audio.hardMaxValue * 100

                            icon: Audio.source?.audio?.muted ? Icons.micSlash : Icons.mic
                            sliderValue: Math.min(1, (Number.isFinite(Audio.source?.audio?.volume) ? Audio.source.audio.volume : 0) / Audio.hardMaxValue)
                            progressColor: Audio.source?.audio?.muted ? Colors.outline : Styling.srItem("overprimary")
                            wavy: true
                            wavyAmplitude: Audio.source?.audio?.muted ? 0.5 : 1.5 * effectiveValue
                            wavyFrequency: Audio.source?.audio?.muted ? 1.0 : 8.0 * effectiveValue

                            onValueChanged: newValue => Audio.setMicVolume(newValue * Audio.hardMaxValue)
                            onIconClicked: {
                                if (Audio.source?.audio)
                                    Audio.source.audio.muted = !Audio.source.audio.muted;
                            }
                        }

                        StyledRect {
                            id: sourceToggleBtn
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            radius: Styling.radius(-4)
                            variant: root.showSources ? "primary" : (sourceBtnMa.containsMouse ? "focus" : "common")
                            enableShadow: false
                            visible: Audio.inputDevices.length > 1

                            Text {
                                anchors.centerIn: parent
                                text: root.showSources ? Icons.caretUp : Icons.caretDown
                                font.family: Icons.font
                                font.pixelSize: 12
                                color: sourceToggleBtn.item
                            }

                            MouseArea {
                                id: sourceBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showSources = !root.showSources
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 32
                        text: Audio.friendlyDeviceName(Audio.source)
                        textFormat: Text.PlainText
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        elide: Text.ElideRight
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        visible: root.showSources

                        Repeater {
                            model: Audio.inputDevices

                            delegate: StyledRect {
                                id: sourceItem
                                required property var modelData
                                readonly property bool active: Audio.source?.id === modelData?.id
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: Styling.radius(-4)
                                variant: active ? "primary" : (sourceItemMa.containsMouse ? "focus" : "internalbg")
                                enableShadow: false

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    Text {
                                        text: sourceItem.active ? Icons.accept : Icons.mic
                                        font.family: Icons.font
                                        font.pixelSize: 13
                                        color: sourceItem.item
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: Audio.friendlyDeviceName(sourceItem.modelData)
                                        textFormat: Text.PlainText
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                        color: sourceItem.item
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: sourceItemMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Audio.setDefaultSource(sourceItem.modelData);
                                        root.showSources = false;
                                    }
                                }
                            }
                        }
                    }
                }

                ControlSliderRow {
                    id: brightnessRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    Layout.rightMargin: 4

                    property var currentMonitor: Brightness.getMonitorForScreen(root.bar.screen)
                    visible: currentMonitor?.ready ?? false

                    icon: Icons.sun
                    sliderValue: currentMonitor?.brightness ?? 0.5
                    progressColor: Styling.srItem("overprimary")
                    wavy: true
                    wavyAmplitude: 1.5 * effectiveValue
                    wavyFrequency: 8.0 * effectiveValue
                    iconRotation: effectiveValue * 180
                    iconScale: 0.8 + effectiveValue * 0.2

                    onValueChanged: newValue => {
                        if (Brightness.syncBrightness) {
                            for (let i = 0; i < Brightness.monitors.length; i++) {
                                let mon = Brightness.monitors[i];
                                if (mon && mon.ready)
                                    mon.setBrightness(newValue);
                            }
                        } else if (currentMonitor && currentMonitor.ready) {
                            currentMonitor.setBrightness(newValue);
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: EasyEffectsService.available

                    Separator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        StyledRect {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: Styling.radius(-4)
                            variant: eeExpandMa.containsMouse ? "focus" : "common"
                            enableShadow: false

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 6

                                Text {
                                    text: Icons.sparkle
                                    font.family: Icons.font
                                    font.pixelSize: 14
                                    color: EasyEffectsService.bypassed ? Colors.outline : Colors.primary
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: EasyEffectsService.bypassed ? "EQ Bypassed" : (EasyEffectsService.activeOutputPreset || "EasyEffects")
                                    textFormat: Text.PlainText
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.Medium
                                    color: EasyEffectsService.bypassed ? Colors.overSurfaceVariant : Colors.overBackground
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: root.showPresets ? Icons.caretUp : Icons.caretDown
                                    font.family: Icons.font
                                    font.pixelSize: 12
                                    color: Colors.overSurfaceVariant
                                }
                            }

                            MouseArea {
                                id: eeExpandMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showPresets = !root.showPresets
                            }
                        }

                        StyledRect {
                            id: eeBypassBtn
                            Layout.preferredWidth: 58
                            Layout.preferredHeight: 30
                            radius: Styling.radius(-4)
                            variant: !EasyEffectsService.bypassed ? "primary" : (eeBypassMa.containsMouse ? "focus" : "common")
                            enableShadow: false

                            Text {
                                anchors.centerIn: parent
                                text: EasyEffectsService.bypassed ? "Off" : "On"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Bold
                                color: eeBypassBtn.item
                            }

                            MouseArea {
                                id: eeBypassMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: EasyEffectsService.setBypass(!EasyEffectsService.bypassed)
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: root.showPresets && EasyEffectsService.outputPresets.length > 0

                        Repeater {
                            model: EasyEffectsService.outputPresets

                            delegate: StyledRect {
                                id: outPresetChip
                                required property string modelData
                                readonly property bool active: !EasyEffectsService.bypassed && EasyEffectsService.activeOutputPreset === modelData
                                width: chipLabel.implicitWidth + 18
                                height: 26
                                radius: Styling.radius(-4)
                                variant: active ? "primary" : (chipMa.containsMouse ? "focus" : "internalbg")
                                enableShadow: false

                                Text {
                                    id: chipLabel
                                    anchors.centerIn: parent
                                    text: outPresetChip.modelData
                                    textFormat: Text.PlainText
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.weight: outPresetChip.active ? Font.Bold : Font.Normal
                                    color: outPresetChip.item
                                }

                                MouseArea {
                                    id: chipMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: EasyEffectsService.loadOutputPreset(outPresetChip.modelData)
                                }
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: root.showPresets && EasyEffectsService.inputPresets.length > 0

                        Repeater {
                            model: EasyEffectsService.inputPresets

                            delegate: StyledRect {
                                id: inPresetChip
                                required property string modelData
                                readonly property bool active: EasyEffectsService.activeInputPreset === modelData
                                width: inChipRow.implicitWidth + 16
                                height: 26
                                radius: Styling.radius(-4)
                                variant: active ? "secondary" : (inChipMa.containsMouse ? "focus" : "internalbg")
                                enableShadow: false

                                Row {
                                    id: inChipRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        text: Icons.mic
                                        font.family: Icons.font
                                        font.pixelSize: 11
                                        color: inPresetChip.item
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: inPresetChip.modelData
                                        textFormat: Text.PlainText
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-2)
                                        font.weight: inPresetChip.active ? Font.Bold : Font.Normal
                                        color: inPresetChip.item
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: inChipMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: EasyEffectsService.loadInputPreset(inPresetChip.modelData)
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: Audio.outputAppNodes.length > 0

                    Separator {
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Applications"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        font.weight: Font.Bold
                        color: Colors.overSurfaceVariant
                    }

                    Repeater {
                        model: Audio.outputAppNodes

                        delegate: Item {
                            id: streamRow
                            required property PwNode modelData
                            Layout.fillWidth: true
                            implicitHeight: 42

                            PwObjectTracker {
                                objects: [streamRow.modelData]
                            }

                            readonly property bool streamMuted: streamRow.modelData?.audio?.muted ?? false
                            readonly property real streamVol: Number.isFinite(streamRow.modelData?.audio?.volume) ? streamRow.modelData.audio.volume : 0

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        text: Audio.appNodeDisplayName(streamRow.modelData)
                                        textFormat: Text.PlainText
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-2)
                                        color: Colors.overBackground
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: streamRow.streamMuted ? "Muted" : `${Math.round(streamRow.streamVol * 100)}%`
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-2)
                                        color: streamRow.streamMuted ? Colors.error : Colors.overSurfaceVariant
                                    }
                                }

                                ControlSliderRow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 22
                                    displayMultiplier: Audio.hardMaxValue * 100
                                    icon: streamRow.streamMuted ? Icons.speakerX : Icons.speakerHigh
                                    sliderValue: Math.min(1, streamRow.streamVol / Audio.hardMaxValue)
                                    progressColor: streamRow.streamMuted ? Colors.outline : Colors.primary
                                    wavy: false

                                    onValueChanged: newValue => Audio.setNodeVolume(streamRow.modelData, newValue * Audio.hardMaxValue)
                                    onIconClicked: {
                                        if (streamRow.modelData?.audio)
                                            streamRow.modelData.audio.muted = !streamRow.modelData.audio.muted;
                                    }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: PeripheralBatteryService.devices.length > 0

                    Separator {
                        Layout.fillWidth: true
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: PeripheralBatteryService.devices

                            delegate: StyledRect {
                                id: periphPill
                                required property var modelData
                                width: Math.min(slidersColumn.width, periphRow.implicitWidth + 16)
                                height: 26
                                radius: Styling.radius(-4)
                                variant: "common"
                                enableShadow: false

                                Row {
                                    id: periphRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Text {
                                        text: periphPill.modelData.icon
                                        font.family: Icons.font
                                        font.pixelSize: 13
                                        color: periphPill.modelData.percentage <= 20 ? Colors.error : Colors.primary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: periphPill.modelData.name
                                        textFormat: Text.PlainText
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-2)
                                        color: Colors.overBackground
                                        width: Math.min(implicitWidth, 120)
                                        elide: Text.ElideRight
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: periphPill.modelData.percentage + "%" + (periphPill.modelData.charging ? "+" : "")
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-2)
                                        font.weight: Font.Bold
                                        color: periphPill.modelData.percentage <= 20 ? Colors.error : Colors.overSurfaceVariant
                                        anchors.verticalCenter: parent.verticalCenter
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
