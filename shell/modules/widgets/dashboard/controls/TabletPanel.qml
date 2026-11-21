pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.theme
import "../../../services/tablet_utils.js" as TabletUtils

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    readonly property var region: TabletService.effectiveRegion
    readonly property var activeRect: TabletService.activeRect
    readonly property string targetMode: Config.tablet.targetMode || "centered"
    readonly property string inputMode: Config.tablet.inputMode || "pen"
    readonly property bool penActive: inputMode !== "touchpad"
    readonly property bool touchpadEnabled: inputMode !== "pen"

    readonly property var openWindows: {
        const list = Compositor.clients.values || [];
        return list.filter(c => c && c.mapped !== false && !c.hidden && c.title !== "Pangu Settings");
    }

    Component.onCompleted: {
        TabletService.telemetryActive = true;
        TabletService.refreshDevices();
    }

    Component.onDestruction: {
        TabletService.telemetryActive = false;
    }

    component SectionHeading: Text {
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-1)
        font.weight: Font.Medium
        color: Colors.overSurfaceVariant
        Layout.topMargin: 4
    }

    component ChoicePill: StyledRect {
        id: pill
        property string label: ""
        property string icon: ""
        property bool selected: false
        property bool hovered: false
        signal activated()

        variant: selected ? "primary" : (hovered ? "focus" : "common")
        radius: Styling.radius(-2)
        implicitHeight: 34
        implicitWidth: Math.max(44, pillRow.implicitWidth + 20)
        opacity: enabled ? 1.0 : 0.45

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6

            Text {
                visible: pill.icon !== ""
                text: pill.icon
                font.family: Icons.font
                font.pixelSize: 15
                color: pill.item
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: pill.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                font.weight: pill.selected ? Font.Bold : Font.Normal
                color: pill.item
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: pill.enabled
            hoverEnabled: true
            cursorShape: pill.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: pill.hovered = true
            onExited: pill.hovered = false
            onClicked: pill.activated()
        }
    }

    component SliderRow: ColumnLayout {
        id: sRow
        property string label: ""
        property string valueText: ""
        property real sliderValue: 0
        property real stepSize: 0
        signal sliderMoved(real ratio)

        Layout.fillWidth: true
        spacing: 4
        opacity: enabled ? 1.0 : 0.45

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: sRow.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overBackground
                Layout.fillWidth: true
            }

            Text {
                text: sRow.valueText
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overSurfaceVariant
            }
        }

        StyledSlider {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            value: sRow.sliderValue
            stepSize: sRow.stepSize
            snapMode: sRow.stepSize > 0 ? "always" : "none"
            tooltip: false
            smoothDrag: false
            onMoved: v => sRow.sliderMoved(v)
        }
    }

    Flickable {
        id: mainFlickable
        anchors.fill: parent
        contentHeight: mainColumn.implicitHeight + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: mainColumn
            width: mainFlickable.width
            spacing: 12

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: titlebar.height

                PanelTitlebar {
                    id: titlebar
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    title: "Tablet"
                    showToggle: true
                    toggleChecked: TabletService.enabled
                    statusText: {
                        if (!TabletService.enabled)
                            return "Disabled";
                        if (TabletService.connected) {
                            const link = TabletService.transport === "wifi" ? "Wi-Fi" : "USB";
                            return (TabletService.deviceModel || "Connected") + " · " + link;
                        }
                        if (TabletService.state === "unauthorized")
                            return "Authorize";
                        if (TabletService.state === "error")
                            return "Error";
                        return "Waiting...";
                    }

                    actions: [
                        {
                            icon: TabletService.transport === "wifi" ? Icons.wifiOff : Icons.wifiHigh,
                            tooltip: TabletService.transport === "wifi"
                                ? "Disconnect Wireless ADB"
                                : ((TabletService.connected && TabletService.transport === "usb")
                                    ? ("Switch to Wireless" + (TabletService.wifiIp ? (" (" + TabletService.wifiIp + ")") : ""))
                                    : (Config.tablet.wirelessAddress
                                        ? ("Connect Wireless (" + Config.tablet.wirelessAddress + ")")
                                        : "Switch USB tablet to Wireless ADB")),
                            enabled: !TabletService.wirelessBusy && (TabletService.connected || Boolean(Config.tablet.wirelessAddress)),
                            loading: TabletService.wirelessBusy,
                            onClicked: function () {
                                TabletService.toggleWireless();
                            }
                        },
                        {
                            icon: Icons.regionScreenshot,
                            tooltip: "Pick target area, window, or screen",
                            onClicked: function () {
                                GlobalStates.beginTabletPick("area", true);
                            }
                        },
                        {
                            icon: Icons.sync,
                            tooltip: TabletService.enabled ? "Reconnect tablet" : "Scan ADB devices",
                            onClicked: function () {
                                TabletService.reconnect();
                            }
                        },
                        {
                            icon: Icons.arrowCounterClockwise,
                            tooltip: "Reset tablet settings to defaults",
                            onClicked: function () {
                                TabletService.resetDefaults();
                            }
                        }
                    ]

                    onToggleChanged: checked => TabletService.setEnabled(checked)
                }
            }

            ColumnLayout {
                width: root.contentWidth
                Layout.preferredWidth: root.contentWidth
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                // Status & device card
                StyledRect {
                    variant: "common"
                    Layout.fillWidth: true
                    implicitHeight: statusCol.implicitHeight + 20
                    radius: Styling.radius(-2)

                    ColumnLayout {
                        id: statusCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                color: {
                                    if (!TabletService.enabled)
                                        return Colors.outline;
                                    if (TabletService.connected)
                                        return Styling.srItem("overprimary");
                                    if (TabletService.state === "error" || TabletService.state === "unauthorized")
                                        return Colors.error;
                                    return Colors.secondary;
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: {
                                    if (!TabletService.enabled)
                                        return "Enable to bridge an ADB stylus tablet via uinput";
                                    if (TabletService.connected)
                                        return (TabletService.deviceModel || TabletService.deviceSerial) + (TabletService.digitizerName ? ("  (" + TabletService.digitizerName + ")") : "");
                                    return TabletService.statusMessage || "Waiting for tablet...";
                                }
                                elide: Text.ElideRight
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overBackground
                            }
                        }

                        Text {
                            visible: TabletService.connected
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: {
                                const r = root.region;
                                const modeTag = TabletService.touchpadActive ? (root.penActive ? " · Pen + Touchpad" : " · Touchpad") : "";
                                const dims = TabletService.tabletMaxX + "×" + TabletService.tabletMaxY
                                    + (root.penActive ? (" · " + TabletService.tabletMaxPressure + " levels" + (TabletService.hasTilt ? " · Tilt" : "")) : "")
                                    + modeTag
                                    + (TabletService.grabActive ? " · Tablet input suppressed" : "");
                                const mapped = (root.penActive && r) ? (" → " + r.width + "×" + r.height + " @ " + r.globalX + "," + r.globalY) : "";
                                return dims + mapped;
                            }
                            font.family: Config.theme.monoFont
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overSurfaceVariant
                        }

                        Flow {
                            visible: TabletService.availableDevices.length > 0
                            Layout.fillWidth: true
                            spacing: 6

                            ChoicePill {
                                label: "Auto"
                                selected: Config.tablet.deviceSerial === ""
                                onActivated: Config.tablet.deviceSerial = ""
                            }

                            Repeater {
                                model: TabletService.availableDevices
                                delegate: ChoicePill {
                                    required property var modelData
                                    label: (modelData.model || modelData.serial) + (String(modelData.serial || "").indexOf(":") >= 0 ? " · Wi-Fi" : " · USB") + (modelData.state !== "device" ? (" (" + modelData.state + ")") : "")
                                    selected: Config.tablet.deviceSerial === modelData.serial
                                    onActivated: Config.tablet.deviceSerial = modelData.serial
                                }
                            }
                        }

                        Flow {
                            visible: (TabletService.connected && TabletService.transport === "usb")
                                || TabletService.transport === "wifi"
                                || Boolean(Config.tablet.wirelessAddress)
                            Layout.fillWidth: true
                            spacing: 6

                            ChoicePill {
                                visible: TabletService.connected && TabletService.transport === "usb"
                                enabled: !TabletService.wirelessBusy
                                icon: Icons.wifiHigh
                                label: TabletService.wirelessBusy ? "Switching..." : ("Switch to Wireless" + (TabletService.wifiIp ? (" (" + TabletService.wifiIp + ")") : ""))
                                selected: true
                                onActivated: TabletService.enableWireless()
                            }

                            ChoicePill {
                                visible: TabletService.transport !== "wifi" && Boolean(Config.tablet.wirelessAddress)
                                enabled: !TabletService.wirelessBusy
                                icon: Icons.wifiHigh
                                label: TabletService.wirelessBusy ? "Connecting..." : ("Connect " + Config.tablet.wirelessAddress)
                                onActivated: TabletService.connectWireless(Config.tablet.wirelessAddress)
                            }

                            ChoicePill {
                                visible: TabletService.transport === "wifi"
                                enabled: !TabletService.wirelessBusy
                                icon: Icons.wifiOff
                                label: "Disconnect Wi-Fi"
                                onActivated: TabletService.disconnectWireless(TabletService.deviceSerial || Config.tablet.wirelessAddress)
                            }
                        }

                        Text {
                            visible: TabletService.wirelessFeedback !== ""
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: TabletService.wirelessFeedback
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: TabletService.wirelessError ? Colors.error : Styling.srItem("overprimary")
                        }
                    }
                }

                // Input mode selector (Pen / Hybrid / Touchpad)
                SectionHeading { text: "Input Mode" }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "pen", label: "Pen Only", icon: Icons.edit },
                            { id: "hybrid", label: "Pen + Touchpad", icon: Icons.handGrab },
                            { id: "touchpad", label: "Touchpad Only", icon: Icons.cursor }
                        ]
                        delegate: ChoicePill {
                            required property var modelData
                            label: modelData.label
                            icon: modelData.icon
                            selected: root.inputMode === modelData.id
                            onActivated: TabletService.setInputMode(modelData.id)
                        }
                    }
                }

                // Live visual mapping preview (Screen target / Touchpad legend + Tablet active surface)
                StyledRect {
                    variant: "common"
                    Layout.fillWidth: true
                    implicitHeight: 132
                    radius: Styling.radius(-2)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 12

                        // Monitor / screen target preview (Pen & Hybrid modes)
                        ColumnLayout {
                            visible: root.penActive
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 4

                            Text {
                                text: "Screen Target · " + (root.region ? (root.region.width + "×" + root.region.height) : "")
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overSurfaceVariant
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Item {
                                id: screenPreviewBox
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                readonly property real monW: Math.max(1, root.region?.monitorWidth || 1920)
                                readonly property real monH: Math.max(1, root.region?.monitorHeight || 1080)
                                readonly property real scaleFit: Math.min(width / monW, height / monH)
                                readonly property real drawW: Math.max(12, monW * scaleFit)
                                readonly property real drawH: Math.max(12, monH * scaleFit)

                                Rectangle {
                                    id: monOutline
                                    width: screenPreviewBox.drawW
                                    height: screenPreviewBox.drawH
                                    anchors.centerIn: parent
                                    color: Colors.surfaceDim
                                    border.width: 1
                                    border.color: Colors.outline
                                    radius: 4
                                    clip: true

                                    Rectangle {
                                        readonly property real rx: ((root.region?.globalX ?? 0) - (root.region?.monitorX ?? 0)) * screenPreviewBox.scaleFit
                                        readonly property real ry: ((root.region?.globalY ?? 0) - (root.region?.monitorY ?? 0)) * screenPreviewBox.scaleFit
                                        readonly property real rw: (root.region?.width ?? 0) * screenPreviewBox.scaleFit
                                        readonly property real rh: (root.region?.height ?? 0) * screenPreviewBox.scaleFit
                                        x: rx
                                        y: ry
                                        width: Math.max(4, rw)
                                        height: Math.max(4, rh)
                                        color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.28)
                                        border.width: 1.5
                                        border.color: Styling.srItem("overprimary")
                                        radius: 2

                                        Rectangle {
                                            visible: TabletService.penInProx
                                            width: TabletService.penTouching ? 7 : 5
                                            height: width
                                            radius: width / 2
                                            color: TabletService.penTouching ? Styling.srItem("overprimary") : Colors.overBackground
                                            x: Math.max(0, Math.min(parent.width - width, TabletService.penX * parent.width - width / 2))
                                            y: Math.max(0, Math.min(parent.height - height, TabletService.penY * parent.height - height / 2))
                                        }
                                    }
                                }
                            }
                        }

                        // Touchpad gestures legend (Touchpad Only mode)
                        ColumnLayout {
                            visible: !root.penActive
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 4

                            Text {
                                text: TabletService.touchFingers.length > 0
                                    ? ("Precision Touchpad · " + TabletService.touchFingers.length + (TabletService.touchFingers.length === 1 ? " finger" : " fingers"))
                                    : "Precision Touchpad · Relative Mouse"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.weight: Font.Medium
                                color: Colors.overBackground
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                wrapMode: Text.Wrap
                                verticalAlignment: Text.AlignVCenter
                                text: "1 finger: move cursor & tap to click\n2 fingers: smooth scroll, pinch zoom & right-click\n3 fingers: middle-click or 3-finger drag"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overSurfaceVariant
                            }
                        }

                        // Tablet active surface preview
                        ColumnLayout {
                            Layout.preferredWidth: 148
                            Layout.fillHeight: true
                            spacing: 4

                            Text {
                                text: root.penActive
                                    ? ("Tablet · " + Math.round((Config.tablet.areaScale ?? 1.0) * 100) + "% · " + (Config.tablet.rotation || 0) + "°")
                                    : ("Touchpad · " + Number(Config.tablet.touchpadSpeed ?? 1.0).toFixed(1) + "× · " + (Config.tablet.touchpadRotation === "auto" ? "Auto" : (Config.tablet.touchpadRotation + "°")))
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overSurfaceVariant
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Item {
                                id: tabletPreviewBox
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                readonly property real tAspect: TabletService.tabletAspect
                                readonly property real drawW: Math.min(width, height * tAspect)
                                readonly property real drawH: drawW / Math.max(0.2, tAspect)

                                Rectangle {
                                    id: tabletSurfaceRect
                                    width: Math.max(12, tabletPreviewBox.drawW)
                                    height: Math.max(12, tabletPreviewBox.drawH)
                                    anchors.centerIn: parent
                                    color: Colors.surfaceDim
                                    border.width: 1
                                    border.color: Colors.outline
                                    radius: 4
                                    clip: true

                                    Rectangle {
                                        visible: root.penActive
                                        x: (root.activeRect?.x ?? 0) * parent.width
                                        y: (root.activeRect?.y ?? 0) * parent.height
                                        width: Math.max(4, (root.activeRect?.width ?? 1) * parent.width)
                                        height: Math.max(4, (root.activeRect?.height ?? 1) * parent.height)
                                        color: Qt.rgba(Colors.secondary.r, Colors.secondary.g, Colors.secondary.b, 0.25)
                                        border.width: 1.5
                                        border.color: Colors.secondary
                                        radius: 2
                                    }

                                    Rectangle {
                                        visible: root.penActive && TabletService.penInProx
                                        width: TabletService.penTouching ? 7 : 5
                                        height: width
                                        radius: width / 2
                                        color: TabletService.penTouching ? Styling.srItem("overprimary") : Colors.overBackground
                                        x: Math.max(0, Math.min(parent.width - width, TabletService.penRawX * parent.width - width / 2))
                                        y: Math.max(0, Math.min(parent.height - height, TabletService.penRawY * parent.height - height / 2))
                                    }

                                    Repeater {
                                        model: TabletService.touchFingers
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 10
                                            height: 10
                                            radius: 5
                                            color: Qt.rgba(Colors.tertiary.r, Colors.tertiary.g, Colors.tertiary.b, 0.45)
                                            border.width: 1.5
                                            border.color: Colors.tertiary
                                            x: Math.max(0, Math.min(tabletSurfaceRect.width - width, Number(modelData.x || 0) * tabletSurfaceRect.width - width / 2))
                                            y: Math.max(0, Math.min(tabletSurfaceRect.height - height, Number(modelData.y || 0) * tabletSurfaceRect.height - height / 2))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Touchpad & Gestures (Hybrid & Touchpad modes)
                ColumnLayout {
                    visible: root.touchpadEnabled
                    Layout.fillWidth: true
                    spacing: 12

                    SectionHeading { text: "Touchpad & Gestures" }

                    SliderRow {
                        label: "Touchpad Pointer Speed"
                        valueText: Number(Config.tablet.touchpadSpeed ?? 1.0).toFixed(2) + "×"
                        sliderValue: ((Config.tablet.touchpadSpeed ?? 1.0) - 0.4) / 2.1
                        stepSize: 0.05 / 2.1
                        onSliderMoved: r => Config.tablet.touchpadSpeed = Math.round((0.4 + r * 2.1) * 20) / 20
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Acceleration Profile"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: Colors.overBackground
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: 6
                            ChoicePill {
                                label: "Adaptive"
                                selected: (Config.tablet.touchpadAccelProfile || "adaptive") === "adaptive"
                                onActivated: Config.tablet.touchpadAccelProfile = "adaptive"
                            }
                            ChoicePill {
                                label: "Flat"
                                selected: Config.tablet.touchpadAccelProfile === "flat"
                                onActivated: Config.tablet.touchpadAccelProfile = "flat"
                            }
                        }
                    }

                    SliderRow {
                        label: "Two-Finger Scroll Speed"
                        valueText: Number(Config.tablet.touchpadScrollFactor ?? 1.0).toFixed(2) + "×"
                        sliderValue: ((Config.tablet.touchpadScrollFactor ?? 1.0) - 0.2) / 2.8
                        stepSize: 0.05 / 2.8
                        onSliderMoved: r => Config.tablet.touchpadScrollFactor = Math.round((0.2 + r * 2.8) * 20) / 20
                    }

                    SettingsToggleRow {
                        label: "Natural Scrolling"
                        checked: Config.tablet.touchpadNaturalScroll
                        onToggled: v => Config.tablet.touchpadNaturalScroll = v
                    }

                    SettingsToggleRow {
                        label: "Tap-to-Click (1L · 2R · 3M)"
                        checked: Config.tablet.touchpadTapToClick
                        onToggled: v => Config.tablet.touchpadTapToClick = v
                    }

                    SettingsToggleRow {
                        label: "Tap-and-Drag"
                        checked: Config.tablet.touchpadTapAndDrag
                        onToggled: v => Config.tablet.touchpadTapAndDrag = v
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Multi-Finger Drag"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: Colors.overBackground
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: [
                                    { id: 0, label: "Off" },
                                    { id: 1, label: "3-Finger" },
                                    { id: 2, label: "4-Finger" }
                                ]
                                delegate: ChoicePill {
                                    required property var modelData
                                    label: modelData.label
                                    selected: (Config.tablet.touchpadDrag3fg ?? 0) === modelData.id
                                    onActivated: Config.tablet.touchpadDrag3fg = modelData.id
                                }
                            }
                        }
                    }

                    SettingsToggleRow {
                        label: "Disable Touchpad While Typing"
                        checked: Config.tablet.touchpadDisableWhileTyping
                        onToggled: v => Config.tablet.touchpadDisableWhileTyping = v
                    }

                    SliderRow {
                        visible: root.inputMode === "hybrid"
                        label: "Pen Palm Rejection Cooldown"
                        valueText: (Config.tablet.touchpadPalmRejectMs ?? 350) + " ms"
                        sliderValue: (Config.tablet.touchpadPalmRejectMs ?? 350) / 800
                        stepSize: 50 / 800
                        onSliderMoved: r => Config.tablet.touchpadPalmRejectMs = Math.round(r * 16) * 50
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Touchpad Orientation"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: Colors.overBackground
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: [
                                    { id: "auto", label: "Auto" },
                                    { id: "0", label: "0°" },
                                    { id: "90", label: "90°" },
                                    { id: "180", label: "180°" },
                                    { id: "270", label: "270°" }
                                ]
                                delegate: ChoicePill {
                                    required property var modelData
                                    label: modelData.label
                                    selected: (Config.tablet.touchpadRotation || "auto") === modelData.id
                                    onActivated: Config.tablet.touchpadRotation = modelData.id
                                }
                            }
                        }
                    }

                    Separator { Layout.fillWidth: true }
                }

                // Target Mode & Selectors (Pen & Hybrid modes)
                ColumnLayout {
                    visible: root.penActive
                    Layout.fillWidth: true
                    spacing: 12

                SectionHeading { text: "Mapping Target" }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "centered", label: "Centered", icon: Icons.layout },
                            { id: "screen", label: "Screen", icon: Icons.fullScreenshot },
                            { id: "area", label: "Area", icon: Icons.regionScreenshot },
                            { id: "window", label: "Window", icon: Icons.windowScreenshot }
                        ]
                        delegate: ChoicePill {
                            required property var modelData
                            label: modelData.label
                            icon: modelData.icon
                            selected: root.targetMode === modelData.id
                            onActivated: Config.tablet.targetMode = modelData.id
                        }
                    }
                }

                // Quick interactive pickers
                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    ChoicePill {
                        icon: Icons.regionScreenshot
                        label: "Pick Area"
                        onActivated: GlobalStates.beginTabletPick("area", true)
                    }
                    ChoicePill {
                        icon: Icons.windowScreenshot
                        label: "Pick Window"
                        onActivated: GlobalStates.beginTabletPick("window", true)
                    }
                    ChoicePill {
                        icon: Icons.fullScreenshot
                        label: "Pick Screen"
                        onActivated: GlobalStates.beginTabletPick("screen", true)
                    }
                }

                // Monitor selector (used by Screen & Centered modes)
                ColumnLayout {
                    visible: root.targetMode === "screen" || root.targetMode === "centered"
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Monitor"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overSurfaceVariant
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        ChoicePill {
                            label: "Focused"
                            selected: Config.tablet.monitor === ""
                            onActivated: Config.tablet.monitor = ""
                        }

                        Repeater {
                            model: Compositor.monitors.values
                            delegate: ChoicePill {
                                required property var modelData
                                label: modelData.name + " (" + Math.round(modelData.logicalWidth) + "×" + Math.round(modelData.logicalHeight) + ")"
                                selected: Config.tablet.monitor === modelData.name
                                onActivated: Config.tablet.monitor = modelData.name
                            }
                        }
                    }
                }

                // Centered mode controls
                ColumnLayout {
                    visible: root.targetMode === "centered"
                    Layout.fillWidth: true
                    spacing: 8

                    SettingsToggleRow {
                        label: "Match Centered Layout Width"
                        checked: Config.tablet.centeredMatchLayout
                        onToggled: v => Config.tablet.centeredMatchLayout = v
                    }

                    Flow {
                        visible: !Config.tablet.centeredMatchLayout
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { label: "2560×1440", w: 2560, h: 1440 },
                                { label: "1920×1440 (4:3)", w: 1920, h: 1440 },
                                { label: "1920×1080", w: 1920, h: 1080 },
                                { label: "Half Width", w: Math.round((root.region?.monitorWidth || 5120) / 2), h: Math.round(root.region?.monitorHeight || 1440) }
                            ]
                            delegate: ChoicePill {
                                required property var modelData
                                label: modelData.label
                                selected: Config.tablet.centeredWidth === modelData.w && Config.tablet.centeredHeight === modelData.h
                                onActivated: TabletService.selectCentered(undefined, modelData.w, modelData.h)
                            }
                        }
                    }

                    SettingsNumberInputRow {
                        visible: !Config.tablet.centeredMatchLayout
                        label: "Centered Width"
                        value: Config.tablet.centeredWidth
                        minValue: 128
                        maxValue: 10000
                        suffix: "px"
                        onValueEdited: v => Config.tablet.centeredWidth = Math.round(v)
                    }

                    SettingsNumberInputRow {
                        visible: !Config.tablet.centeredMatchLayout
                        label: "Centered Height"
                        value: Config.tablet.centeredHeight
                        minValue: 128
                        maxValue: 10000
                        suffix: "px"
                        onValueEdited: v => Config.tablet.centeredHeight = Math.round(v)
                    }
                }

                // Area mode numeric controls
                ColumnLayout {
                    visible: root.targetMode === "area"
                    Layout.fillWidth: true
                    spacing: 8

                    SettingsNumberInputRow {
                        label: "Area X"
                        value: Config.tablet.areaX
                        minValue: -20000
                        maxValue: 20000
                        suffix: "px"
                        onValueEdited: v => Config.tablet.areaX = Math.round(v)
                    }

                    SettingsNumberInputRow {
                        label: "Area Y"
                        value: Config.tablet.areaY
                        minValue: -20000
                        maxValue: 20000
                        suffix: "px"
                        onValueEdited: v => Config.tablet.areaY = Math.round(v)
                    }

                    SettingsNumberInputRow {
                        label: "Area Width"
                        value: Config.tablet.areaWidth
                        minValue: 32
                        maxValue: 20000
                        suffix: "px"
                        onValueEdited: v => Config.tablet.areaWidth = Math.round(v)
                    }

                    SettingsNumberInputRow {
                        label: "Area Height"
                        value: Config.tablet.areaHeight
                        minValue: 32
                        maxValue: 20000
                        suffix: "px"
                        onValueEdited: v => Config.tablet.areaHeight = Math.round(v)
                    }
                }

                // Window mode selector
                ColumnLayout {
                    visible: root.targetMode === "window"
                    Layout.fillWidth: true
                    spacing: 8

                    SettingsToggleRow {
                        label: "Follow Window Move & Resize"
                        checked: Config.tablet.followWindow
                        onToggled: v => Config.tablet.followWindow = v
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: {
                                if (!Config.tablet.windowAddress && !Config.tablet.windowClass)
                                    return "Following focused window" + (root.region?.windowFound ? (" (" + root.region.label + ")") : "");
                                return "Bound: " + (Config.tablet.windowTitle || Config.tablet.windowClass) + (root.region?.windowFound ? " (active)" : " (not open)");
                            }
                            elide: Text.ElideRight
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.overSurfaceVariant
                        }

                        ChoicePill {
                            visible: Boolean((Config.tablet.windowAddress || Config.tablet.windowClass) && root.region?.windowFound)
                            label: "Focus"
                            onActivated: TabletService.focusTrackedWindow()
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        ChoicePill {
                            label: "Focused Window"
                            selected: Config.tablet.windowAddress === "" && Config.tablet.windowClass === ""
                            onActivated: TabletService.selectFocusedWindow()
                        }

                        Repeater {
                            model: root.openWindows
                            delegate: ChoicePill {
                                required property var modelData
                                readonly property string rawLabel: modelData.title || modelData["class"] || "Window"
                                label: rawLabel.length > 26 ? (rawLabel.slice(0, 25) + "…") : rawLabel
                                selected: Config.tablet.windowAddress === String(modelData.address || "")
                                onActivated: TabletService.selectWindow(modelData)
                            }
                        }
                    }
                }

                Separator { Layout.fillWidth: true }
                }

                // Surface, Size & Orientation
                SectionHeading { text: root.penActive ? "Orientation & Active Surface" : "Orientation" }

                RowLayout {
                    visible: root.penActive
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Aspect Ratio"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        color: Colors.overBackground
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: [
                                { id: "fit-tablet", label: "Fit Tablet" },
                                { id: "fit-screen", label: "Fit Screen" },
                                { id: "stretch", label: "Stretch" }
                            ]
                            delegate: ChoicePill {
                                required property var modelData
                                label: modelData.label
                                selected: Config.tablet.aspectMode === modelData.id
                                onActivated: Config.tablet.aspectMode = modelData.id
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Orientation"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        color: Colors.overBackground
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: [0, 90, 180, 270]
                            delegate: ChoicePill {
                                required property int modelData
                                label: modelData + "°"
                                selected: Config.tablet.rotation === modelData
                                onActivated: Config.tablet.rotation = modelData
                            }
                        }
                    }
                }

                SettingsToggleRow {
                    label: "Flip Horizontal"
                    checked: Config.tablet.flipX
                    onToggled: v => Config.tablet.flipX = v
                }

                SettingsToggleRow {
                    label: "Flip Vertical"
                    checked: Config.tablet.flipY
                    onToggled: v => Config.tablet.flipY = v
                }

                SettingsToggleRow {
                    visible: root.penActive
                    label: "Relative Input (Mouse Mode)"
                    checked: Config.tablet.relativeMode
                    onToggled: v => Config.tablet.relativeMode = v
                }

                SliderRow {
                    visible: root.penActive
                    label: "Active Area Size"
                    valueText: Math.round((Config.tablet.areaScale ?? 1.0) * 100) + "%"
                    sliderValue: ((Config.tablet.areaScale ?? 1.0) - 0.25) / 0.75
                    stepSize: 1 / 75
                    onSliderMoved: r => Config.tablet.areaScale = Math.round((0.25 + r * 0.75) * 100) / 100
                }

                SliderRow {
                    visible: root.penActive
                    label: "Active Area Horizontal Offset"
                    valueText: Math.round((Config.tablet.areaOffsetX ?? 0) * 100) + "%"
                    sliderValue: (Config.tablet.areaOffsetX ?? 0) + 0.5
                    stepSize: 0.02
                    onSliderMoved: r => Config.tablet.areaOffsetX = Math.round((r - 0.5) * 100) / 100
                }

                SliderRow {
                    visible: root.penActive
                    label: "Active Area Vertical Offset"
                    valueText: Math.round((Config.tablet.areaOffsetY ?? 0) * 100) + "%"
                    sliderValue: (Config.tablet.areaOffsetY ?? 0) + 0.5
                    stepSize: 0.02
                    onSliderMoved: r => Config.tablet.areaOffsetY = Math.round((r - 0.5) * 100) / 100
                }

                Separator { Layout.fillWidth: true }

                // Pen & Pressure Sensitivity
                ColumnLayout {
                    visible: root.penActive
                    Layout.fillWidth: true
                    spacing: 12

                SectionHeading { text: "Pen & Pressure Sensitivity" }

                SettingsToggleRow {
                    label: "Pressure Sensitivity"
                    checked: Config.tablet.pressureEnabled
                    onToggled: v => Config.tablet.pressureEnabled = v
                }

                // Pressure curve & live meter
                StyledRect {
                    variant: "common"
                    Layout.fillWidth: true
                    implicitHeight: 112
                    radius: Styling.radius(-2)
                    opacity: Config.tablet.pressureEnabled ? 1.0 : 0.45

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 12

                        Canvas {
                            id: pressureCanvas
                            Layout.preferredWidth: 140
                            Layout.fillHeight: true

                            readonly property real gammaVal: Config.tablet.pressureGamma ?? 1.0
                            readonly property real minVal: Config.tablet.pressureMin ?? 0.0
                            readonly property real maxVal: Config.tablet.pressureMax ?? 1.0
                            readonly property bool enabledVal: Config.tablet.pressureEnabled !== false
                            readonly property real liveRaw: TabletService.penRawPressure
                            readonly property real liveOut: TabletService.penPressure

                            onGammaValChanged: requestPaint()
                            onMinValChanged: requestPaint()
                            onMaxValChanged: requestPaint()
                            onEnabledValChanged: requestPaint()
                            onLiveRawChanged: requestPaint()
                            onLiveOutChanged: requestPaint()

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);

                                const pad = 6;
                                const w = Math.max(1, width - pad * 2);
                                const h = Math.max(1, height - pad * 2);

                                ctx.strokeStyle = Qt.rgba(Colors.outline.r, Colors.outline.g, Colors.outline.b, 0.45);
                                ctx.lineWidth = 1;
                                ctx.strokeRect(pad, pad, w, h);

                                // Diagonal linear reference
                                ctx.beginPath();
                                ctx.moveTo(pad, pad + h);
                                ctx.lineTo(pad + w, pad);
                                ctx.strokeStyle = Qt.rgba(Colors.outline.r, Colors.outline.g, Colors.outline.b, 0.3);
                                ctx.stroke();

                                // Active curve
                                ctx.beginPath();
                                for (let i = 0; i <= 40; i++) {
                                    const rx = i / 40;
                                    const ry = TabletUtils.evaluatePressure(rx, enabledVal, gammaVal, minVal, maxVal);
                                    const px = pad + rx * w;
                                    const py = pad + (1 - ry) * h;
                                    if (i === 0)
                                        ctx.moveTo(px, py);
                                    else
                                        ctx.lineTo(px, py);
                                }
                                ctx.strokeStyle = Styling.srItem("overprimary");
                                ctx.lineWidth = 2;
                                ctx.stroke();

                                if (liveRaw > 0) {
                                    const dx = pad + liveRaw * w;
                                    const dy = pad + (1 - liveOut) * h;
                                    ctx.beginPath();
                                    ctx.arc(dx, dy, 4, 0, Math.PI * 2);
                                    ctx.fillStyle = Colors.secondary;
                                    ctx.fill();
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 6

                            Text {
                                text: "Live Pressure"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overSurfaceVariant
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 14
                                radius: 7
                                color: Colors.surfaceDim

                                Rectangle {
                                    height: parent.height
                                    width: parent.width * Math.max(0, Math.min(1, TabletService.penPressure))
                                    radius: 7
                                    color: Styling.srItem("overprimary")
                                }
                            }

                            Text {
                                text: "Output: " + Math.round(TabletService.penPressure * 100) + "%  (Raw: " + Math.round(TabletService.penRawPressure * 100) + "%)"
                                font.family: Config.theme.monoFont
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overBackground
                            }

                            Text {
                                text: TabletService.hasTilt
                                    ? ("Tilt: " + TabletService.penTiltX + "°, " + TabletService.penTiltY + "°")
                                    : "Tilt not reported by digitizer"
                                font.family: Config.theme.monoFont
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overSurfaceVariant
                            }
                        }
                    }
                }

                SliderRow {
                    enabled: Config.tablet.pressureEnabled
                    label: "Pressure Curve (Soft ↔ Firm)"
                    valueText: (Config.tablet.pressureGamma ?? 1.0).toFixed(2)
                    sliderValue: ((Config.tablet.pressureGamma ?? 1.0) - 0.3) / 2.2
                    stepSize: 0.05 / 2.2
                    onSliderMoved: r => Config.tablet.pressureGamma = Math.round((0.3 + r * 2.2) * 20) / 20
                }

                SliderRow {
                    enabled: Config.tablet.pressureEnabled
                    label: "Min Pressure Deadzone"
                    valueText: Math.round((Config.tablet.pressureMin ?? 0.0) * 100) + "%"
                    sliderValue: (Config.tablet.pressureMin ?? 0.0) / 0.35
                    stepSize: 1 / 35
                    onSliderMoved: r => {
                        const nextMin = Math.round(r * 35) / 100;
                        TabletService.batchUpdate(() => {
                            Config.tablet.pressureMin = nextMin;
                            if ((Config.tablet.pressureMax ?? 1.0) < nextMin + 0.05)
                                Config.tablet.pressureMax = Math.min(1.0, Math.round((nextMin + 0.05) * 100) / 100);
                        });
                    }
                }

                SliderRow {
                    enabled: Config.tablet.pressureEnabled
                    label: "Max Pressure Saturation"
                    valueText: Math.round((Config.tablet.pressureMax ?? 1.0) * 100) + "%"
                    sliderValue: ((Config.tablet.pressureMax ?? 1.0) - 0.4) / 0.6
                    stepSize: 1 / 60
                    onSliderMoved: r => {
                        const nextMax = Math.round((0.4 + r * 0.6) * 100) / 100;
                        Config.tablet.pressureMax = Math.max((Config.tablet.pressureMin ?? 0.0) + 0.05, nextMax);
                    }
                }

                SliderRow {
                    label: "Input Smoothing"
                    valueText: (Config.tablet.smoothing ?? 0) === 0 ? "Off" : String(Config.tablet.smoothing)
                    sliderValue: (Config.tablet.smoothing ?? 0) / 10
                    stepSize: 0.1
                    onSliderMoved: r => Config.tablet.smoothing = Math.round(r * 10)
                }

                SettingsToggleRow {
                    label: "Tilt Sensitivity"
                    checked: Config.tablet.tiltEnabled
                    onToggled: v => Config.tablet.tiltEnabled = v
                }

                SettingsToggleRow {
                    label: "Eraser Tip Support"
                    checked: Config.tablet.eraserEnabled
                    onToggled: v => Config.tablet.eraserEnabled = v
                }

                SettingsToggleRow {
                    label: "Swap Stylus Buttons"
                    checked: Config.tablet.swapStylusButtons
                    onToggled: v => Config.tablet.swapStylusButtons = v
                }

                Separator { Layout.fillWidth: true }
                }

                SectionHeading { text: "Tablet Device Input" }

                SettingsToggleRow {
                    label: "Suppress Pen Input on Tablet"
                    checked: Config.tablet.suppressPen
                    onToggled: v => Config.tablet.suppressPen = v
                }

                SettingsToggleRow {
                    label: "Suppress Touch & Palm on Tablet"
                    checked: Config.tablet.suppressTouch
                    onToggled: v => Config.tablet.suppressTouch = v
                }

                SettingsToggleRow {
                    label: "Keep Tablet Awake While Connected"
                    checked: Config.tablet.keepAwake
                    onToggled: v => Config.tablet.keepAwake = v
                }

                Separator { Layout.fillWidth: true }

                SectionHeading { text: "Wireless ADB (Wi-Fi)" }

                SettingsToggleRow {
                    label: "Auto-Connect Wireless Address"
                    checked: Config.tablet.wirelessAutoConnect
                    onToggled: v => Config.tablet.wirelessAutoConnect = v
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledRect {
                        variant: "common"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: Styling.radius(-2)

                        TextInput {
                            id: wifiAddrInput
                            anchors.fill: parent
                            anchors.margins: 8
                            font.family: Config.theme.monoFont
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.overBackground
                            selectByMouse: true
                            clip: true
                            verticalAlignment: TextInput.AlignVCenter
                            readonly property string configVal: Config.tablet.wirelessAddress || ""
                            onConfigValChanged: if (!activeFocus && text !== configVal) text = configVal
                            Component.onCompleted: text = configVal
                            onEditingFinished: Config.tablet.wirelessAddress = text.trim()

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !wifiAddrInput.text && !wifiAddrInput.activeFocus
                                text: TabletService.wifiIp ? (TabletService.wifiIp + ":5555") : "192.168.x.x:5555"
                                font: wifiAddrInput.font
                                color: Colors.overSurfaceVariant
                            }
                        }
                    }

                    ChoicePill {
                        enabled: !TabletService.wirelessBusy
                        icon: Icons.wifiHigh
                        label: TabletService.wirelessBusy ? "..." : "Connect"
                        onActivated: TabletService.connectWireless(wifiAddrInput.text || (TabletService.wifiIp ? (TabletService.wifiIp + ":5555") : ""))
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    ChoicePill {
                        id: pairToggle
                        property bool expanded: false
                        label: expanded ? "Hide Pairing" : "Pair Wireless Debugging..."
                        onActivated: expanded = !expanded
                    }
                }

                ColumnLayout {
                    visible: pairToggle.expanded
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "On tablet: Developer Options → Wireless debugging → Pair device with pairing code, then enter the pairing IP:port and 6-digit code below."
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledRect {
                            variant: "common"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: Styling.radius(-2)

                            TextInput {
                                id: pairAddrInput
                                anchors.fill: parent
                                anchors.margins: 8
                                font.family: Config.theme.monoFont
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overBackground
                                selectByMouse: true
                                clip: true
                                verticalAlignment: TextInput.AlignVCenter

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !pairAddrInput.text && !pairAddrInput.activeFocus
                                    text: "Pairing IP:port"
                                    font: pairAddrInput.font
                                    color: Colors.overSurfaceVariant
                                }
                            }
                        }

                        StyledRect {
                            variant: "common"
                            Layout.preferredWidth: 100
                            Layout.preferredHeight: 34
                            radius: Styling.radius(-2)

                            TextInput {
                                id: pairCodeInput
                                anchors.fill: parent
                                anchors.margins: 8
                                font.family: Config.theme.monoFont
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overBackground
                                selectByMouse: true
                                clip: true
                                verticalAlignment: TextInput.AlignVCenter

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !pairCodeInput.text && !pairCodeInput.activeFocus
                                    text: "6-digit code"
                                    font: pairCodeInput.font
                                    color: Colors.overSurfaceVariant
                                }
                            }
                        }

                        ChoicePill {
                            enabled: !TabletService.wirelessBusy
                            label: "Pair"
                            onActivated: TabletService.pairWireless(pairAddrInput.text, pairCodeInput.text)
                        }
                    }
                }
            }
        }
    }
}
