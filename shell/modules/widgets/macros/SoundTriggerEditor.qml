import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config

ColumnLayout {
    id: root

    property string macroId: ""
    property var trigger: ({})
    signal triggerEdited(var nextTrigger)

    property var peaks: []
    property real clipDuration: 0
    property int dominantHz: 0
    property int suggestedMinHz: 1200
    property int suggestedMaxHz: 3800
    property real localTrimStart: 0
    property real localTrimEnd: 0
    property string draggingHandle: ""
    property real dragAnchorSec: 0
    property bool pendingAutotrim: false
    property string inspectedPath: ""

    readonly property bool isRecording: MacroService.recordingMacroId !== "" && MacroService.recordingMacroId === root.macroId
    readonly property string samplePath: String(root.trigger?.samplePath || "")
    readonly property bool hasSample: root.samplePath.length > 0
    readonly property string mode: root.trigger?.mode || "sample"
    readonly property string source: root.trigger?.source || "desktop"
    readonly property int threshold: root.trigger?.threshold || 70
    readonly property int liveScore: Number(MacroService.soundScores[root.macroId] || 0)
    readonly property int livePeakHz: {
        const map = MacroService.soundPeakHz || ({});
        if (root.source === "mic")
            return Number(map.mic || 0);
        if (root.source === "both")
            return Math.max(Number(map.desktop || 0), Number(map.mic || 0));
        return Number(map.desktop || 0);
    }

    spacing: 10

    function patch(fields) {
        const out = {};
        if (root.trigger) {
            for (const k in root.trigger)
                out[k] = root.trigger[k];
        }
        for (const k in fields)
            out[k] = fields[k];
        root.triggerEdited(out);
    }

    function _syncLocalTrim() {
        if (root.draggingHandle !== "")
            return;
        const dur = root.clipDuration;
        const t0 = Number(root.trigger?.trimStart || 0);
        const t1 = Number(root.trigger?.trimEnd || 0);
        root.localTrimStart = Math.max(0, t0);
        root.localTrimEnd = (t1 > t0) ? (dur > 0 ? Math.min(dur, t1) : t1) : dur;
    }

    function _refreshInspection(force) {
        if (root.samplePath.length === 0) { // hasSample may still hold its previous value inside onSamplePathChanged
            root.peaks = [];
            root.clipDuration = 0;
            root.dominantHz = 0;
            root.inspectedPath = "";
            return;
        }
        if (!force && root.inspectedPath === root.samplePath && root.peaks.length > 0)
            return;
        root.inspectedPath = root.samplePath;
        MacroService.inspectSoundSample(root.samplePath, root.trigger?.trimStart || 0, root.trigger?.trimEnd || 0, false);
    }

    onSamplePathChanged: _refreshInspection(false)
    onTriggerChanged: _syncLocalTrim()
    Component.onCompleted: {
        _syncLocalTrim();
        _refreshInspection(false);
    }

    Connections {
        target: MacroService
        function onSoundSampleReady(macroId, path, meta) {
            if (macroId !== root.macroId || !meta)
                return;
            root.inspectedPath = path;
            root.peaks = meta.peaks || [];
            root.clipDuration = Number(meta.duration || 0);
            root.dominantHz = Number(meta.dominantHz || 0);
            root.suggestedMinHz = Number(meta.bandMinHz || 1200);
            root.suggestedMaxHz = Number(meta.bandMaxHz || 3800);
            root.localTrimStart = Number(meta.trimStart || 0);
            root.localTrimEnd = Number(meta.trimEnd || root.clipDuration);
            root.patch({
                samplePath: path,
                trimStart: root.localTrimStart,
                trimEnd: root.localTrimEnd,
                minHz: root.suggestedMinHz,
                maxHz: root.suggestedMaxHz
            });
        }
        function onSoundSampleInspected(path, meta) {
            if (path !== root.samplePath || !meta)
                return;
            root.peaks = meta.peaks || [];
            root.clipDuration = Number(meta.duration || 0);
            root.dominantHz = Number(meta.dominantHz || 0);
            root.suggestedMinHz = Number(meta.bandMinHz || 1200);
            root.suggestedMaxHz = Number(meta.bandMaxHz || 3800);
            if (root.pendingAutotrim) {
                root.pendingAutotrim = false;
                root.localTrimStart = Number(meta.trimStart || 0);
                root.localTrimEnd = Number(meta.trimEnd || root.clipDuration);
                root.patch({
                    trimStart: root.localTrimStart,
                    trimEnd: root.localTrimEnd,
                    minHz: root.suggestedMinHz,
                    maxHz: root.suggestedMaxHz
                });
            } else {
                root._syncLocalTrim();
            }
        }
    }

    Process {
        id: importPicker
        command: [
            "zenity", "--file-selection", "--title=Import target sound",
            "--file-filter=Audio | *.wav *.mp3 *.ogg *.oga *.opus *.flac *.m4a *.aac *.webm *.mp4"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const picked = text.trim();
                if (picked.length > 0 && root.macroId !== "")
                    MacroService.importSoundSample(root.macroId, picked);
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            text: qsTr("Listen on")
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            color: Colors.overSurfaceVariant
        }

        Repeater {
            model: [
                { id: "desktop", label: "Desktop", icon: Icons.speakerHigh },
                { id: "mic", label: "Mic", icon: Icons.mic },
                { id: "both", label: "Both", icon: Icons.waveform }
            ]

            MacroButton {
                required property var modelData
                icon: modelData.icon
                text: modelData.label
                implicitHeight: 32
                tone: root.source === modelData.id ? "primary" : "common"
                onClicked: root.patch({ source: modelData.id })
            }
        }

        Item {
            Layout.fillWidth: true
        }

        Repeater {
            model: [
                { id: "sample", label: "Sound clip", icon: Icons.scissors },
                { id: "frequency", label: "Frequency", icon: Icons.waveform }
            ]

            MacroButton {
                required property var modelData
                icon: modelData.icon
                text: modelData.label
                implicitHeight: 32
                tone: root.mode === modelData.id ? "primary" : "common"
                onClicked: root.patch({ mode: modelData.id })
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.mode === "sample"
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MacroButton {
                icon: root.isRecording ? Icons.stop : Icons.recordScreen
                text: root.isRecording
                    ? ("Stop (" + MacroService.recordingSeconds.toFixed(1) + "s)")
                    : qsTr("Record sound")
                tone: root.isRecording ? "danger" : "primary"
                onClicked: {
                    if (root.isRecording)
                        MacroService.stopSoundRecord();
                    else
                        MacroService.startSoundRecord(root.macroId, root.source === "mic" ? "mic" : "desktop");
                }
            }

            MacroButton {
                icon: Icons.folder
                text: qsTr("Import file")
                enabled: !root.isRecording
                onClicked: importPicker.running = true
            }

            MacroButton {
                icon: Icons.scissors
                text: qsTr("Auto-snip")
                enabled: root.hasSample && !root.isRecording
                onClicked: {
                    root.pendingAutotrim = true;
                    MacroService.inspectSoundSample(root.samplePath, 0, 0, true);
                }
            }

            MacroButton {
                icon: MacroService.previewPlaying ? Icons.stop : Icons.play
                text: MacroService.previewPlaying ? qsTr("Stop") : qsTr("Preview snip")
                enabled: root.hasSample && !root.isRecording
                onClicked: {
                    if (MacroService.previewPlaying)
                        MacroService.stopSoundPreview();
                    else
                        MacroService.previewSoundSnippet(root.samplePath, root.localTrimStart, root.localTrimEnd);
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 24
            visible: root.isRecording
            variant: "common"
            radius: Styling.radius(-4)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 3
                width: Math.max(4, (parent.width - 6) * Math.min(1.0, MacroService.recordingLevel))
                radius: Styling.radius(-6)
                color: Colors.error
            }

            Text {
                anchors.centerIn: parent
                text: "Capturing " + (root.source === "mic" ? "microphone" : "desktop audio") + " — play or ring the sound now…"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overBackground
            }
        }

        StyledRect {
            id: waveBox
            Layout.fillWidth: true
            implicitHeight: 88
            variant: "common"
            radius: Styling.radius(-2)
            clip: true

            readonly property real startRatio: root.clipDuration > 0 ? Math.max(0, Math.min(1, root.localTrimStart / root.clipDuration)) : 0
            readonly property real endRatio: root.clipDuration > 0 ? Math.max(startRatio, Math.min(1, (root.localTrimEnd > 0 ? root.localTrimEnd : root.clipDuration) / root.clipDuration)) : 1
            readonly property real innerW: Math.max(1, width - 16)
            readonly property real startX: 8 + startRatio * innerW
            readonly property real endX: 8 + endRatio * innerW

            Text {
                anchors.centerIn: parent
                visible: !root.hasSample || root.peaks.length === 0
                text: root.hasSample
                    ? "Loading waveform…"
                    : "Record desktop/mic audio or import a sound file, then drag handles to snip the exact cue."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
            }

            Item {
                anchors.fill: parent
                anchors.margins: 8
                visible: root.hasSample && root.peaks.length > 0

                Row {
                    id: barsRow
                    anchors.fill: parent
                    spacing: 2

                    Repeater {
                        model: root.peaks

                        Item {
                            required property int index
                            required property real modelData
                            readonly property real barRatio: (index + 0.5) / Math.max(1, root.peaks.length)
                            readonly property bool inSnip: barRatio >= waveBox.startRatio && barRatio <= waveBox.endRatio
                            width: Math.max(1, (barsRow.width - (root.peaks.length - 1) * 2) / Math.max(1, root.peaks.length))
                            height: barsRow.height

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: Math.max(3, parent.height * Math.max(0.05, parent.modelData))
                                radius: 1.5
                                color: parent.inSnip ? Colors.primary : Colors.outline
                                opacity: parent.inSnip ? 0.95 : 0.35
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: root.hasSample && root.peaks.length > 0
                x: 0
                y: 0
                width: Math.max(0, waveBox.startX)
                height: parent.height
                color: Colors.background
                opacity: 0.45
            }

            Rectangle {
                visible: root.hasSample && root.peaks.length > 0
                x: waveBox.endX
                y: 0
                width: Math.max(0, parent.width - waveBox.endX)
                height: parent.height
                color: Colors.background
                opacity: 0.45
            }

            Rectangle {
                visible: root.hasSample && root.peaks.length > 0
                x: waveBox.startX - 1.5
                y: 4
                width: 3
                height: parent.height - 8
                radius: 1.5
                color: Colors.primary

                Rectangle {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 10
                    height: 14
                    radius: 3
                    color: Colors.primary
                }
            }

            Rectangle {
                visible: root.hasSample && root.peaks.length > 0
                x: waveBox.endX - 1.5
                y: 4
                width: 3
                height: parent.height - 8
                radius: 1.5
                color: Colors.primary

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 10
                    height: 14
                    radius: 3
                    color: Colors.primary
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.hasSample && root.clipDuration > 0
                cursorShape: Qt.SizeHorCursor

                function secAt(px) {
                    const ratio = Math.max(0, Math.min(1, (px - 8) / waveBox.innerW));
                    return ratio * root.clipDuration;
                }

                onPressed: mouse => {
                    const dStart = Math.abs(mouse.x - waveBox.startX);
                    const dEnd = Math.abs(mouse.x - waveBox.endX);
                    if (dStart <= 14 && dStart <= dEnd) {
                        root.draggingHandle = "start";
                    } else if (dEnd <= 14) {
                        root.draggingHandle = "end";
                    } else {
                        root.draggingHandle = "range";
                        root.dragAnchorSec = secAt(mouse.x);
                        root.localTrimStart = root.dragAnchorSec;
                        root.localTrimEnd = Math.min(root.clipDuration, root.dragAnchorSec + 0.06);
                    }
                }

                onPositionChanged: mouse => {
                    if (!pressed || root.draggingHandle === "")
                        return;
                    const sec = secAt(mouse.x);
                    if (root.draggingHandle === "start") {
                        root.localTrimStart = Math.max(0, Math.min(sec, root.localTrimEnd - 0.06));
                    } else if (root.draggingHandle === "end") {
                        root.localTrimEnd = Math.min(root.clipDuration, Math.max(sec, root.localTrimStart + 0.06));
                    } else if (root.draggingHandle === "range") {
                        const lo = Math.min(root.dragAnchorSec, sec);
                        const hi = Math.max(root.dragAnchorSec, sec);
                        root.localTrimStart = lo;
                        root.localTrimEnd = Math.min(root.clipDuration, Math.max(lo + 0.06, hi));
                    }
                }

                onReleased: {
                    if (root.draggingHandle === "")
                        return;
                    root.draggingHandle = "";
                    const t0 = Math.round(root.localTrimStart * 1000) / 1000;
                    const t1 = Math.round(root.localTrimEnd * 1000) / 1000;
                    root.patch({ trimStart: t0, trimEnd: t1 });
                    MacroService.inspectSoundSample(root.samplePath, t0, t1, false);
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.hasSample
            spacing: 12

            Text {
                text: "Snip: " + root.localTrimStart.toFixed(2) + "s – " + root.localTrimEnd.toFixed(2) + "s"
                    + " (" + Math.max(0, root.localTrimEnd - root.localTrimStart).toFixed(2) + "s)"
                    + (root.dominantHz > 0 ? "  ·  Peak: ~" + root.dominantHz + " Hz" : "")
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
                Layout.fillWidth: true
            }

            SettingsToggleRow {
                Layout.preferredWidth: 165
                Layout.maximumWidth: 165
                label: qsTr("Band filter")
                checked: root.trigger?.bandFilter === true
                onToggled: value => root.patch({
                    bandFilter: value,
                    minHz: root.trigger?.minHz || root.suggestedMinHz,
                    maxHz: root.trigger?.maxHz || root.suggestedMaxHz
                })
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.hasSample && root.trigger?.bandFilter === true
            spacing: 12

            SettingsNumberInputRow {
                Layout.fillWidth: true
                label: "Min Hz"
                suffix: "Hz"
                value: root.trigger?.minHz || 1200
                minValue: 60
                maxValue: 7500
                onValueEdited: value => root.patch({ minHz: value })
            }

            SettingsNumberInputRow {
                Layout.fillWidth: true
                label: "Max Hz"
                suffix: "Hz"
                value: root.trigger?.maxHz || 3800
                minValue: 100
                maxValue: 7800
                onValueEdited: value => root.patch({ maxHz: value })
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.mode === "frequency"
        spacing: 8

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { label: "Bell / Chime", minHz: 1200, maxHz: 3800, hold: 60 },
                    { label: "High Ping", minHz: 2400, maxHz: 5600, hold: 45 },
                    { label: "Mid Beep", minHz: 650, maxHz: 1500, hold: 80 },
                    { label: "Low Alert", minHz: 180, maxHz: 650, hold: 100 }
                ]

                MacroButton {
                    required property var modelData
                    text: modelData.label
                    implicitHeight: 30
                    tone: root.trigger?.minHz === modelData.minHz && root.trigger?.maxHz === modelData.maxHz ? "primary" : "common"
                    onClicked: root.patch({
                        minHz: modelData.minHz,
                        maxHz: modelData.maxHz,
                        minDurationMs: modelData.hold
                    })
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            SettingsNumberInputRow {
                Layout.fillWidth: true
                label: "Min Hz"
                suffix: "Hz"
                value: root.trigger?.minHz || 1200
                minValue: 60
                maxValue: 7500
                onValueEdited: value => root.patch({ minHz: value })
            }

            SettingsNumberInputRow {
                Layout.fillWidth: true
                label: "Max Hz"
                suffix: "Hz"
                value: root.trigger?.maxHz || 3800
                minValue: 100
                maxValue: 7800
                onValueEdited: value => root.patch({ maxHz: value })
            }

            SettingsNumberInputRow {
                Layout.fillWidth: true
                label: "Hold"
                suffix: "ms"
                value: root.trigger?.minDurationMs || 60
                minValue: 20
                maxValue: 5000
                onValueEdited: value => root.patch({ minDurationMs: value })
            }
        }
    }

    StyledRect {
        id: meterBar
        Layout.fillWidth: true
        implicitHeight: 26
        variant: "common"
        radius: Styling.radius(-4)
        clip: true

        Rectangle {
            x: 3
            y: 3
            height: parent.height - 6
            width: Math.max(0, (parent.width - 6) * Math.min(1, root.liveScore / 100))
            radius: Styling.radius(-6)
            color: root.liveScore >= root.threshold ? Colors.primary : Colors.outline
            opacity: root.liveScore >= root.threshold ? 0.85 : 0.45

            Behavior on width {
                enabled: Styling.animDuration > 0
                NumberAnimation {
                    duration: 80
                }
            }
        }

        Rectangle {
            x: 3 + (parent.width - 6) * (root.threshold / 100) - 1
            y: 2
            width: 2
            height: parent.height - 4
            color: Colors.overBackground
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10

            Text {
                text: "Live match: " + root.liveScore + "%"
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overBackground
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: root.livePeakHz > 0 ? ("Live peak: " + root.livePeakHz + " Hz") : "Click bar to set threshold"
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function applyThreshold(px) {
                const pct = Math.round(Math.max(30, Math.min(98, ((px - 3) / Math.max(1, meterBar.width - 6)) * 100)));
                root.patch({ threshold: pct });
            }
            onPressed: mouse => applyThreshold(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    applyThreshold(mouse.x);
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        SettingsNumberInputRow {
            Layout.fillWidth: true
            label: "Match threshold"
            suffix: "%"
            value: root.threshold
            minValue: 30
            maxValue: 98
            onValueEdited: value => root.patch({ threshold: value })
        }

        SettingsNumberInputRow {
            Layout.fillWidth: true
            label: "Cooldown"
            suffix: "ms"
            value: root.trigger?.cooldownMs || 1500
            minValue: 100
            maxValue: 300000
            onValueEdited: value => root.patch({ cooldownMs: value })
        }
    }
}
