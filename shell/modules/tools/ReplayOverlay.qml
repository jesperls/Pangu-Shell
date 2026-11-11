pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.modules.theme
import qs.modules.components
import qs.modules.services

PanelWindow {
    id: root

    required property var targetScreen
    screen: targetScreen

    property string clipPath: ""
    property string posterPath: ""
    property real durationSec: 60.0
    property double sizeBytes: 0
    property real startRatio: 0.0
    property real endRatio: 1.0
    property bool processing: false
    property string statusLabel: ""

    readonly property real startSec: Math.max(0, startRatio * durationSec)
    readonly property real endSec: Math.max(startSec + 0.2, endRatio * durationSec)
    readonly property string scriptPath: Paths.script("process_clip.sh")

    anchors {
        left: true
        bottom: true
    }

    implicitWidth: card.width + 40
    implicitHeight: card.height + 40

    color: "transparent"
    visible: clipPath !== ""

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "pangu:replay-overlay"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    function formatDuration(sec) {
        const total = Math.max(0, Math.round(sec));
        const m = Math.floor(total / 60);
        const s = total % 60;
        return m + ":" + String(s).padStart(2, "0");
    }

    function formatSize(bytes) {
        if (bytes <= 0)
            return "";
        return (bytes / (1024 * 1024)).toFixed(1) + " MB";
    }

    function loadClip(path) {
        root.clipPath = path;
        root.posterPath = "";
        root.startRatio = 0.0;
        root.endRatio = 1.0;
        root.statusLabel = "";
        probeProcess.command = [root.scriptPath, "probe", path];
        probeProcess.running = true;
        hideTimer.restart();
    }

    Connections {
        target: ReplayService
        function onClipSaved(path, screenName) {
            if (screenName === root.targetScreen?.name)
                root.loadClip(path);
        }
    }

    Process {
        id: probeProcess
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const info = JSON.parse(text.trim());
                    if (info.duration > 0)
                        root.durationSec = info.duration;
                    root.sizeBytes = info.sizeBytes || 0;
                    root.posterPath = info.poster || "";
                } catch (e) {}
            }
        }
    }

    Process {
        id: workerProcess
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.processing = false;
                const out = text.trim();
                if (out !== "") {
                    root.statusLabel = "Copied URI";
                    root.loadClip(out);
                } else {
                    root.statusLabel = "Failed";
                }
            }
        }
        onExited: code => {
            if (code !== 0) {
                root.processing = false;
                root.statusLabel = "Error";
            }
        }
    }

    Process {
        id: copyUriProcess
        command: ["bash", "-c", "printf 'file://%s\\r\\n' \"$1\" | wl-copy --type text/uri-list", "pangu-replay-copy", root.clipPath]
        running: false
        onExited: code => {
            if (code === 0)
                root.statusLabel = "Copied";
        }
    }

    Timer {
        id: hideTimer
        interval: 10000
        repeat: false
        running: root.visible && !overlayHover.hovered && !root.processing && !startHandleMa.pressed && !endHandleMa.pressed
        onTriggered: root.clipPath = ""
    }

    StyledRect {
        id: card
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 20
        width: 336
        height: contentCol.implicitHeight + 24
        variant: "popup"
        enableShadow: true
        radius: Styling.radius(8)

        HoverHandler {
            id: overlayHover
        }

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: Icons.filmStrip
                    font.family: Icons.font
                    font.pixelSize: 15
                    color: Colors.primary
                }

                Text {
                    Layout.fillWidth: true
                    text: root.processing ? root.statusLabel : ("Instant Replay" + (root.statusLabel ? " · " + root.statusLabel : ""))
                    textFormat: Text.PlainText
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    font.weight: Font.Bold
                    color: Colors.overBackground
                    elide: Text.ElideRight
                }

                Text {
                    visible: root.sizeBytes > 0
                    text: root.formatSize(root.sizeBytes)
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    font.weight: Font.Bold
                    color: root.sizeBytes <= 10 * 1024 * 1024 ? Colors.green : Colors.overSurfaceVariant
                }

                MouseArea {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.clipPath = ""

                    Text {
                        anchors.centerIn: parent
                        text: Icons.cancel
                        font.family: Icons.font
                        font.pixelSize: 13
                        color: Colors.overSurfaceVariant
                    }
                }
            }

            ClippingRectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 158
                radius: Styling.radius(2)
                color: Colors.surfaceContainerLowest
                border.width: 1
                border.color: Colors.outlineVariant

                Image {
                    id: posterImg
                    anchors.fill: parent
                    source: root.posterPath !== "" ? "file://" + root.posterPath : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    mipmap: true

                    Item {
                        id: clipDragTarget
                        Drag.active: clipDragArea.drag.active
                        Drag.dragType: Drag.Automatic
                        Drag.supportedActions: Qt.CopyAction
                        Drag.mimeData: ({
                            "text/uri-list": "file://" + root.clipPath + "\r\n"
                        })
                        Drag.imageSource: posterImg.source
                    }

                    MouseArea {
                        id: clipDragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.DragCopyCursor
                        acceptedButtons: Qt.LeftButton
                        drag.target: clipDragTarget
                        onClicked: ApplicationLauncher.launchCommand(["mpv", "--", root.clipPath])
                    }
                }

                StyledRect {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    width: durText.implicitWidth + 12
                    height: 22
                    radius: Styling.radius(-4)
                    variant: "bg"
                    enableShadow: false

                    Text {
                        id: durText
                        anchors.centerIn: parent
                        text: root.formatDuration(root.startSec) + " – " + root.formatDuration(root.endSec)
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        font.weight: Font.Bold
                        color: Colors.overBackground
                    }
                }
            }

            Item {
                id: trimTrack
                Layout.fillWidth: true
                Layout.preferredHeight: 22

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6
                    radius: 3
                    color: Colors.surfaceBright
                }

                Rectangle {
                    x: parent.width * root.startRatio
                    width: Math.max(4, parent.width * (root.endRatio - root.startRatio))
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6
                    radius: 3
                    color: Colors.primary
                }

                Rectangle {
                    id: startHandle
                    x: Math.max(0, Math.min(trimTrack.width - width, trimTrack.width * root.startRatio - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 18
                    radius: 4
                    color: Colors.overBackground

                    MouseArea {
                        id: startHandleMa
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.SizeHorCursor
                        preventStealing: true
                        onPositionChanged: mouse => {
                            if (!pressed || trimTrack.width <= 0)
                                return;
                            const mapped = mapToItem(trimTrack, mouse.x, mouse.y).x;
                            root.startRatio = Math.max(0, Math.min(root.endRatio - 0.03, mapped / trimTrack.width));
                        }
                    }
                }

                Rectangle {
                    id: endHandle
                    x: Math.max(0, Math.min(trimTrack.width - width, trimTrack.width * root.endRatio - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 18
                    radius: 4
                    color: Colors.overBackground

                    MouseArea {
                        id: endHandleMa
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.SizeHorCursor
                        preventStealing: true
                        onPositionChanged: mouse => {
                            if (!pressed || trimTrack.width <= 0)
                                return;
                            const mapped = mapToItem(trimTrack, mouse.x, mouse.y).x;
                            root.endRatio = Math.min(1, Math.max(root.startRatio + 0.03, mapped / trimTrack.width));
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                OverlayAction {
                    Layout.fillWidth: true
                    icon: Icons.scissors
                    label: "Trim"
                    enabled: !root.processing && (root.startRatio > 0.005 || root.endRatio < 0.995)
                    onTriggered: {
                        root.processing = true;
                        root.statusLabel = "Trimming…";
                        workerProcess.command = [root.scriptPath, "trim", root.clipPath, root.startSec.toFixed(2), root.endSec.toFixed(2)];
                        workerProcess.running = true;
                    }
                }

                OverlayAction {
                    Layout.fillWidth: true
                    icon: Icons.arrowsInSimple
                    label: "<10MB"
                    accent: true
                    enabled: !root.processing
                    onTriggered: {
                        root.processing = true;
                        root.statusLabel = "Compressing…";
                        workerProcess.command = [root.scriptPath, "compress", root.clipPath, root.startSec.toFixed(2), root.endSec.toFixed(2)];
                        workerProcess.running = true;
                    }
                }

                OverlayAction {
                    Layout.preferredWidth: 34
                    icon: Icons.copy
                    enabled: !root.processing
                    onTriggered: copyUriProcess.running = true
                }

                OverlayAction {
                    Layout.preferredWidth: 34
                    icon: Icons.trash
                    danger: true
                    enabled: !root.processing
                    onTriggered: {
                        Quickshell.execDetached(["rm", "-f", "--", root.clipPath]);
                        root.clipPath = "";
                    }
                }
            }
        }
    }

    component OverlayAction: MouseArea {
        id: actionBtn
        implicitHeight: 32
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        opacity: enabled ? 1.0 : 0.45

        property string icon: ""
        property string label: ""
        property bool accent: false
        property bool danger: false

        signal triggered

        StyledRect {
            id: actionBg
            anchors.fill: parent
            radius: Styling.radius(-2)
            enableShadow: false
            variant: {
                if (!actionBtn.enabled)
                    return "common";
                if (actionBtn.danger && actionBtn.containsMouse)
                    return "error";
                if (actionBtn.accent)
                    return actionBtn.containsMouse ? "focus" : "primary";
                return actionBtn.containsMouse ? "focus" : "common";
            }

            Row {
                anchors.centerIn: parent
                spacing: 5

                Text {
                    text: actionBtn.icon
                    font.family: Icons.font
                    font.pixelSize: 14
                    color: actionBg.item
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    visible: actionBtn.label !== ""
                    text: actionBtn.label
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    font.weight: Font.Bold
                    color: actionBg.item
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        onClicked: if (enabled) triggered()
    }
}
