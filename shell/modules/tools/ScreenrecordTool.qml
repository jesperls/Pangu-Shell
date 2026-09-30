import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.config

PanelWindow {
    id: screenrecordPopup

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: state !== "idle"
    exclusionMode: ExclusionMode.Ignore

    property string state: "idle" // idle, loading, active, processing
    property string currentMode: "region" // region, window, screen, portal
    property var activeWindows: []

    property bool replayMode: false
    property int replaySeconds: 60
    readonly property var replayDurations: [30, 60, 120, 300]

    property bool recordAudioOutput: false
    property bool recordAudioInput: false

    function formatDuration(seconds) {
        return seconds < 60 ? seconds + "s" : (seconds / 60) + "m";
    }

    property var focusedMonitor: null  // List of monitor objects from compositor

    function getModes() {
        return [
            {
                name: "modeswitch",
                icon: replayMode ? Icons.rewind : Icons.recordScreen,
                tooltip: replayMode ? "Replay Buffer (click for recording)" : "Recording (click for replay buffer)",
                type: "toggle",
                variant: replayMode ? "tertiary" : "primary"
            },
            {
                type: "separator"
            },
            {
                name: "audio",
                icon: recordAudioOutput ? Icons.speakerHigh : Icons.speakerSlash,
                tooltip: "Toggle Audio Output",
                type: "toggle",
                variant: recordAudioOutput ? "primary" : "focus"
            },
            {
                name: "mic",
                icon: recordAudioInput ? Icons.mic : Icons.micSlash,
                tooltip: "Toggle Microphone",
                type: "toggle",
                variant: recordAudioInput ? "primary" : "focus"
            },
            {
                type: "separator"
            },
            {
                name: "region",
                icon: Icons.regionScreenshot,
                tooltip: ScreenRecorder.canRecordDirectly ? "Region" : "Region (Unavailable on NixOS without config)",
                enabled: ScreenRecorder.canRecordDirectly
            },
            {
                name: "window",
                icon: Icons.windowScreenshot,
                tooltip: ScreenRecorder.canRecordDirectly ? "Window" : "Window (Unavailable on NixOS without config)",
                enabled: ScreenRecorder.canRecordDirectly
            },
            {
                name: "screen",
                icon: Icons.fullScreenshot,
                tooltip: ScreenRecorder.canRecordDirectly ? "Screen" : "Screen (Unavailable on NixOS without config)",
                enabled: ScreenRecorder.canRecordDirectly
            },
            {
                name: "portal",
                icon: Icons.aperture,
                tooltip: replayMode ? "Portal (recording only)" : "Portal",
                enabled: !replayMode
            }
        ];
    }

    function open() {
        screenrecordPopup.replayMode = GlobalStates.screenRecordReplayMode;
        screenrecordPopup.replaySeconds = Config.system.replay?.seconds ?? 60;
        if (modeGrid)
            modeGrid.currentIndex = ScreenRecorder.canRecordDirectly ? 5 : 8;
        screenrecordPopup.currentMode = ScreenRecorder.canRecordDirectly ? "region" : "portal";
        screenrecordPopup.recordAudioOutput = screenrecordPopup.replayMode;
        screenrecordPopup.recordAudioInput = false;

        Screenshot.fetchWindows();

        screenrecordPopup.state = "active";

        if (modeGrid)
            modeGrid.forceActiveFocus();
    }

    function startCapture(mode, regionStr) {
        if (screenrecordPopup.replayMode) {
            ReplayService.startWithOptions(mode === "screen" ? "screen" : "region", regionStr, screenrecordPopup.recordAudioOutput, screenrecordPopup.recordAudioInput, screenrecordPopup.replaySeconds);
        } else {
            ScreenRecorder.startRecording(screenrecordPopup.recordAudioOutput, screenrecordPopup.recordAudioInput, mode, regionStr);
        }
        screenrecordPopup.close();
    }

    function close() {
        screenrecordPopup.state = "idle";
        GlobalStates.screenRecordToolVisible = false;
    }

    function executeCapture() {
        if (screenrecordPopup.currentMode === "screen") {
            startCapture("screen", "");
        } else if (screenrecordPopup.currentMode === "region") {
            if (selectionRect.width > 0) {
                var w = Math.round(selectionRect.width);
                var h = Math.round(selectionRect.height);
                var x = Math.round(selectionRect.x);
                var y = Math.round(selectionRect.y);

                if (screenrecordPopup.focusedMonitor) {
                    x = x + screenrecordPopup.focusedMonitor.x;
                    y = y + screenrecordPopup.focusedMonitor.y;
                }

                startCapture("region", w + "x" + h + "+" + x + "+" + y);
            }
        } else if (screenrecordPopup.currentMode === "window") {
        } else if (screenrecordPopup.currentMode === "portal") {
            startCapture("portal", "");
        }
    }

    Connections {
        target: Screenshot
        function onMonitorsListReady(monitors) {
            screenrecordPopup.focusedMonitor = monitors.find(m => m.focused);
        }
        function onWindowListReady(windows) {
            screenrecordPopup.activeWindows = windows;
        }
    }

    mask: Region {
        item: screenrecordPopup.visible ? fullMask : emptyMask
    }

    Item {
        id: fullMask
        anchors.fill: parent
    }

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    FocusGrab {
        id: focusGrab
        windows: [screenrecordPopup]
        active: screenrecordPopup.visible
    }

    FocusScope {
        id: mainFocusScope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: screenrecordPopup.close()

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: screenrecordPopup.state === "active" ? 0.4 : 0
            visible: screenrecordPopup.state === "active" && screenrecordPopup.currentMode !== "screen" && screenrecordPopup.currentMode !== "portal"
        }

        Item {
            anchors.fill: parent
            visible: screenrecordPopup.state === "active" && screenrecordPopup.currentMode === "window"

            Repeater {
                model: screenrecordPopup.activeWindows
                delegate: Rectangle {
                    x: modelData.at[0] - screenrecordPopup.screen.x
                    y: modelData.at[1] - screenrecordPopup.screen.y
                    width: modelData.size[0]
                    height: modelData.size[1]
                    color: "transparent"
                    border.color: hoverHandler.hovered ? Styling.srItem("overprimary") : "transparent"
                    border.width: 2

                    Rectangle {
                        anchors.fill: parent
                        color: Styling.srItem("overprimary")
                        opacity: hoverHandler.hovered ? 0.2 : 0
                    }

                    HoverHandler {
                        id: hoverHandler
                    }

                    TapHandler {
                        onTapped: {
                            var w = Math.round(modelData.size[0]);
                            var h = Math.round(modelData.size[1]);
                            var x = Math.round(modelData.at[0]);
                            var y = Math.round(modelData.at[1]);

                            screenrecordPopup.startCapture("region", w + "x" + h + "+" + x + "+" + y);
                        }
                    }
                }
            }
        }

        MouseArea {
            id: regionArea
            anchors.fill: parent
            enabled: screenrecordPopup.state === "active" && (screenrecordPopup.currentMode === "region" || screenrecordPopup.currentMode === "screen" || screenrecordPopup.currentMode === "portal")
            hoverEnabled: true
            cursorShape: screenrecordPopup.currentMode === "region" ? Qt.CrossCursor : Qt.ArrowCursor

            property point startPoint: Qt.point(0, 0)
            property bool selecting: false

            onPressed: mouse => {
                if (screenrecordPopup.currentMode === "screen" || screenrecordPopup.currentMode === "portal") {
                    return;
                }

                startPoint = Qt.point(mouse.x, mouse.y);
                selectionRect.x = mouse.x;
                selectionRect.y = mouse.y;
                selectionRect.width = 0;
                selectionRect.height = 0;
                selecting = true;
            }

            onClicked: {
                if (screenrecordPopup.currentMode === "screen") {
                    screenrecordPopup.startCapture("screen", "");
                } else if (screenrecordPopup.currentMode === "portal") {
                    screenrecordPopup.startCapture("portal", "");
                }
            }

            onPositionChanged: mouse => {
                if (!selecting)
                    return;
                var x = Math.min(startPoint.x, mouse.x);
                var y = Math.min(startPoint.y, mouse.y);
                var w = Math.abs(startPoint.x - mouse.x);
                var h = Math.abs(startPoint.y - mouse.y);

                selectionRect.x = x;
                selectionRect.y = y;
                selectionRect.width = w;
                selectionRect.height = h;
            }

            onReleased: {
                if (!selecting)
                    return;
                selecting = false;
                if (selectionRect.width > 5 && selectionRect.height > 5) {
                    var w = Math.round(selectionRect.width);
                    var h = Math.round(selectionRect.height);
                    var x = Math.round(selectionRect.x);
                    var y = Math.round(selectionRect.y);

                    x = x + screenrecordPopup.focusedMonitor.x;
                    y = y + screenrecordPopup.focusedMonitor.y;

                    screenrecordPopup.startCapture("region", w + "x" + h + "+" + x + "+" + y);
                }
            }
        }

        Rectangle {
            id: selectionRect
            visible: screenrecordPopup.state === "active" && screenrecordPopup.currentMode === "region"
            color: "transparent"
            border.color: Styling.srItem("overprimary")
            border.width: 2

            Rectangle {
                anchors.fill: parent
                color: Styling.srItem("overprimary")
                opacity: 0.2
            }
        }

        Rectangle {
            id: controlsBar
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 50

            width: contentColumn.width + 32
            height: contentColumn.height + 32

            radius: Styling.radius(20)
            color: Colors.background
            border.color: Colors.surface
            border.width: 1
            visible: screenrecordPopup.state === "active"

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
            }

            ColumnLayout {
                id: contentColumn
                anchors.centerIn: parent
                spacing: 12

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    visible: screenrecordPopup.replayMode
                    spacing: 8

                    Text {
                        text: "Buffer"
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                    }

                    Repeater {
                        model: {
                            var durations = screenrecordPopup.replayDurations.slice();
                            if (durations.indexOf(screenrecordPopup.replaySeconds) === -1)
                                durations.push(screenrecordPopup.replaySeconds);
                            durations.sort((a, b) => a - b);
                            return durations;
                        }

                        StyledRect {
                            id: durationPill
                            required property int modelData

                            readonly property bool selected: screenrecordPopup.replaySeconds === modelData

                            variant: selected ? "primary" : (durationMouse.containsMouse ? "focus" : "common")
                            radius: Styling.radius(0)
                            implicitWidth: durationLabel.implicitWidth + 20
                            implicitHeight: 28

                            Text {
                                id: durationLabel
                                anchors.centerIn: parent
                                text: screenrecordPopup.formatDuration(durationPill.modelData)
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: durationPill.selected ? Font.Bold : Font.Normal
                                color: durationPill.selected ? Styling.srItem("primary") : Colors.overBackground
                            }

                            MouseArea {
                                id: durationMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: screenrecordPopup.replaySeconds = durationPill.modelData
                            }
                        }
                    }
                }

                ActionGrid {
                    id: modeGrid
                    Layout.alignment: Qt.AlignHCenter
                    actions: screenrecordPopup.getModes()
                    buttonSize: 48
                    iconSize: 24
                    spacing: 10

                    onCurrentIndexChanged: {
                        if (currentIndex > 4) {
                            var captureIndex = currentIndex - 5;
                            var captureOptions = ["region", "window", "screen", "portal"];
                            if (captureIndex >= 0 && captureIndex < captureOptions.length) {
                                screenrecordPopup.currentMode = captureOptions[captureIndex];
                            }
                        }
                    }

                    onActionTriggered: action => {
                        if (action.name === "modeswitch") {
                            screenrecordPopup.replayMode = !screenrecordPopup.replayMode;
                            if (screenrecordPopup.replayMode && screenrecordPopup.currentMode === "portal") {
                                screenrecordPopup.currentMode = "region";
                                modeGrid.currentIndex = 5;
                            }
                        } else if (action.tooltip === "Toggle Audio Output") {
                            screenrecordPopup.recordAudioOutput = !screenrecordPopup.recordAudioOutput;
                        } else if (action.tooltip === "Toggle Microphone") {
                            screenrecordPopup.recordAudioInput = !screenrecordPopup.recordAudioInput;
                        } else {
                            screenrecordPopup.executeCapture();
                        }
                    }
                }
            }
        }
    }
}
