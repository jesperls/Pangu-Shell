import QtQuick
import QtQuick.Layouts
import qs.modules.globals
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config
import "../../services/macro_utils.js" as MacroUtils

ColumnLayout {
    id: root

    property string macroId: ""
    property var trigger: ({})
    signal triggerEdited(var nextTrigger)

    property string pendingPickAction: ""
    property string pendingSampleIntent: ""
    property string hexInputText: ""
    property int baselineStamp: 0

    readonly property string targetMode: root.trigger?.targetMode === "area" ? "area" : "pixel"
    readonly property bool isArea: root.targetMode === "area"
    readonly property string watchMode: root.trigger?.watchMode === "change" ? "change" : "color"
    readonly property string colorLogic: root.trigger?.colorLogic || "any"
    readonly property string changeRef: root.trigger?.changeRef === "baseline" ? "baseline" : "previous"
    readonly property int posX: Number(root.trigger?.x || 0)
    readonly property int posY: Number(root.trigger?.y || 0)
    readonly property int areaW: Math.max(1, Number(root.trigger?.width || 64))
    readonly property int areaH: Math.max(1, Number(root.trigger?.height || 64))
    readonly property var colors: MacroUtils.asArray(root.trigger?.colors)
    readonly property int colorTolerance: Math.max(1, Number(root.trigger?.colorTolerance || 12))
    readonly property int changeThreshold: Math.max(1, Number(root.trigger?.changeThreshold || 12))
    readonly property int areaThreshold: Math.max(1, Number(root.trigger?.areaThreshold || 15))
    readonly property string baselinePath: String(root.trigger?.baselinePath || "")
    readonly property bool fireOnEdge: root.trigger?.fireOnEdge !== false

    readonly property var liveEntry: (MacroService.pixelTelemetry && root.macroId)
        ? (MacroService.pixelTelemetry[root.macroId] || null)
        : null
    readonly property real liveScore: root.liveEntry ? Number(root.liveEntry.score || 0) : 0
    readonly property bool liveMatched: Boolean(root.liveEntry && root.liveEntry.matched)
    readonly property string liveHex: root.liveEntry && root.liveEntry.hex ? String(root.liveEntry.hex) : ""
    readonly property real liveCoverage: root.liveEntry ? Number(root.liveEntry.coverage || 0) : 0
    readonly property var livePerColor: (root.liveEntry && root.liveEntry.perColor) ? root.liveEntry.perColor : ({})
    readonly property string livePreviewPath: (root.liveEntry && root.liveEntry.previewPath) ? String(root.liveEntry.previewPath) : ""
    readonly property int livePreviewStamp: root.liveEntry ? Number(root.liveEntry.previewStamp || 0) : 0

    readonly property real effectiveThreshold: {
        if (root.liveEntry && typeof root.liveEntry.threshold === "number" && root.liveEntry.threshold > 0)
            return Number(root.liveEntry.threshold);
        if (root.isArea) {
            if (root.watchMode === "color" && root.colorLogic === "none")
                return Math.max(0, 100 - root.areaThreshold);
            return root.areaThreshold;
        }
        if (root.watchMode === "change")
            return root.changeThreshold;
        if (root.colorLogic === "none")
            return root.colorTolerance;
        return Math.max(0, 100 - root.colorTolerance);
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

    function addHexColor(rawHex) {
        const clean = MacroUtils.normalizeHexColor(rawHex);
        if (!clean)
            return false;
        const nextColors = root.colors.slice();
        if (nextColors.indexOf(clean) === -1) {
            if (nextColors.length >= 12)
                nextColors.shift();
            nextColors.push(clean);
            root.patch({ colors: nextColors });
        }
        return true;
    }

    function removeColorAt(idx) {
        const nextColors = root.colors.slice();
        if (idx >= 0 && idx < nextColors.length) {
            nextColors.splice(idx, 1);
            root.patch({ colors: nextColors });
        }
    }

    Connections {
        target: GlobalStates
        function onMousePickSeqChanged() {
            if (root.pendingPickAction === "")
                return;
            const action = root.pendingPickAction;
            root.pendingPickAction = "";
            if (!GlobalStates.mousePickValid)
                return;

            if (action === "target_pixel") {
                const px = GlobalStates.mousePickX;
                const py = GlobalStates.mousePickY;
                root.patch({ targetMode: "pixel", x: px, y: py });
                if (root.watchMode === "color" && root.colors.length === 0 && root.macroId) {
                    root.pendingSampleIntent = "add_single";
                    MacroService.samplePixelRegion(root.macroId, px, py, 1, 1, 1, 10, true);
                }
            } else if (action === "target_area") {
                root.patch({
                    targetMode: "area",
                    x: GlobalStates.mousePickX,
                    y: GlobalStates.mousePickY,
                    width: GlobalStates.mousePickW,
                    height: GlobalStates.mousePickH
                });
            } else if (action === "eyedropper" && root.macroId) {
                root.pendingSampleIntent = "add_single";
                MacroService.samplePixelRegion(
                    root.macroId,
                    GlobalStates.mousePickX,
                    GlobalStates.mousePickY,
                    1,
                    1,
                    1,
                    10,
                    true
                );
            }
        }
    }

    Connections {
        target: MacroService
        function onPixelSampled(macroId, result) {
            if (macroId !== root.macroId || !result)
                return;
            const intent = root.pendingSampleIntent;
            root.pendingSampleIntent = "";
            const nextColors = root.colors.slice();
            if (intent === "add_single" && result.hex) {
                const single = MacroUtils.normalizeHexColor(result.hex);
                if (single && nextColors.indexOf(single) === -1 && nextColors.length < 12)
                    nextColors.push(single);
            } else {
                const sampled = MacroUtils.asArray(result.colors);
                for (let i = 0; i < sampled.length && nextColors.length < 12; i++) {
                    const hx = MacroUtils.normalizeHexColor(sampled[i]?.hex || "");
                    if (hx && nextColors.indexOf(hx) === -1)
                        nextColors.push(hx);
                }
                if (sampled.length === 0 && result.hex) {
                    const fallback = MacroUtils.normalizeHexColor(result.hex);
                    if (fallback && nextColors.indexOf(fallback) === -1 && nextColors.length < 12)
                        nextColors.push(fallback);
                }
            }
            root.patch({ colors: nextColors });
        }
        function onPixelBaselineReady(macroId, path, meta) {
            if (macroId !== root.macroId || !path)
                return;
            void meta;
            root.baselineStamp++;
            root.patch({ baselinePath: path });
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: [
                { id: "pixel", label: "Single Pixel", icon: Icons.cursor },
                { id: "area", label: "Screen Area", icon: Icons.regionScreenshot }
            ]

            MacroButton {
                required property var modelData
                icon: modelData.icon
                text: modelData.label
                implicitHeight: 32
                tone: root.targetMode === modelData.id ? "primary" : "common"
                onClicked: root.patch({ targetMode: modelData.id })
            }
        }

        Item {
            Layout.fillWidth: true
        }

        Text {
            text: qsTr("Detect")
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
        }

        Repeater {
            model: [
                { id: "color", label: "Color Match", icon: Icons.palette },
                { id: "change", label: "Visual Change", icon: Icons.sparkle }
            ]

            MacroButton {
                required property var modelData
                icon: modelData.icon
                text: modelData.label
                implicitHeight: 32
                tone: root.watchMode === modelData.id ? "primary" : "common"
                onClicked: root.patch({ watchMode: modelData.id })
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: geomCol.implicitHeight + 18
        variant: "common"
        radius: Styling.radius(-2)

        ColumnLayout {
            id: geomCol
            anchors.fill: parent
            anchors.margins: 9
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MacroButton {
                    icon: root.isArea ? Icons.crop : Icons.cursor
                    text: root.isArea ? qsTr("Select area") : qsTr("Pick pixel")
                    tone: "primary"
                    onClicked: {
                        if (root.isArea) {
                            root.pendingPickAction = "target_area";
                            GlobalStates.beginScreenPick("region", qsTr("Drag across the screen area to watch — Esc or right-click to cancel"));
                        } else {
                            root.pendingPickAction = "target_pixel";
                            GlobalStates.beginScreenPick("point", qsTr("Click the pixel to watch — Esc or right-click to cancel"));
                        }
                    }
                }

                SettingsNumberInputRow {
                    Layout.fillWidth: true
                    label: "X"
                    suffix: "px"
                    value: root.posX
                    minValue: -32768
                    maxValue: 32767
                    onValueEdited: value => root.patch({ x: Math.round(value) })
                }

                SettingsNumberInputRow {
                    Layout.fillWidth: true
                    label: "Y"
                    suffix: "px"
                    value: root.posY
                    minValue: -32768
                    maxValue: 32767
                    onValueEdited: value => root.patch({ y: Math.round(value) })
                }

                SettingsNumberInputRow {
                    Layout.fillWidth: true
                    visible: root.isArea
                    label: "W"
                    suffix: "px"
                    value: root.areaW
                    minValue: 1
                    maxValue: 8192
                    onValueEdited: value => root.patch({ width: Math.round(value) })
                }

                SettingsNumberInputRow {
                    Layout.fillWidth: true
                    visible: root.isArea
                    label: "H"
                    suffix: "px"
                    value: root.areaH
                    minValue: 1
                    maxValue: 8192
                    onValueEdited: value => root.patch({ height: Math.round(value) })
                }

                Rectangle {
                    Layout.preferredWidth: root.isArea ? 56 : 36
                    Layout.preferredHeight: 32
                    radius: Styling.radius(-4)
                    color: (!root.isArea && root.liveHex) ? root.liveHex : Colors.surfaceBright
                    border.width: 1
                    border.color: Colors.outline
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: root.isArea && root.livePreviewPath.length > 0
                        cache: false
                        smooth: false
                        fillMode: Image.PreserveAspectFit
                        source: root.isArea && root.livePreviewPath.length > 0
                            ? ("file://" + root.livePreviewPath + "?t=" + root.livePreviewStamp)
                            : ""
                    }
                }

                Text {
                    visible: !root.isArea && root.liveHex.length > 0
                    text: root.liveHex
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overSurfaceVariant
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.watchMode === "color"
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MacroButton {
                icon: Icons.picker
                text: qsTr("Pick color")
                tone: root.colors.length === 0 ? "primary" : "common"
                onClicked: {
                    root.pendingPickAction = "eyedropper";
                    GlobalStates.beginScreenPick("eyedropper", qsTr("Click any pixel on screen to add its color — Esc or right-click to cancel"));
                }
            }

            MacroButton {
                icon: Icons.aperture
                text: root.isArea ? qsTr("Sample area") : qsTr("Sample pixel")
                enabled: root.macroId.length > 0 && !MacroService.screenCaptureHide
                onClicked: {
                    root.pendingSampleIntent = root.isArea ? "merge_region" : "add_single";
                    MacroService.samplePixelRegion(
                        root.macroId,
                        root.posX,
                        root.posY,
                        root.isArea ? root.areaW : 1,
                        root.isArea ? root.areaH : 1,
                        root.isArea ? 4 : 1,
                        root.colorTolerance,
                        false
                    );
                }
            }

            MacroTextField {
                id: hexField
                Layout.preferredWidth: 108
                implicitHeight: 34
                value: root.hexInputText
                placeholder: "#RRGGBB"
                onTextEdited: val => {
                    root.hexInputText = val;
                    if (root.addHexColor(val))
                        root.hexInputText = "";
                }
            }

            MacroIconButton {
                size: 32
                iconSize: 14
                icon: Icons.plus
                tone: MacroUtils.normalizeHexColor(root.hexInputText) !== "" ? "primary" : "common"
                tooltip: qsTr("Add hex color")
                onClicked: {
                    if (root.addHexColor(hexField.value))
                        root.hexInputText = "";
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Repeater {
                model: [
                    { id: "any", label: "Any" },
                    { id: "all", label: "All" },
                    { id: "none", label: "Gone" }
                ]

                MacroButton {
                    required property var modelData
                    visible: modelData.id !== "all" || root.isArea || root.colors.length > 1
                    text: modelData.label
                    implicitHeight: 30
                    tone: root.colorLogic === modelData.id ? "primary" : "common"
                    onClicked: root.patch({ colorLogic: modelData.id })
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6
            visible: root.colors.length > 0

            Repeater {
                model: root.colors

                StyledRect {
                    id: chip
                    required property string modelData
                    required property int index

                    readonly property bool hasLive: chip.modelData in root.livePerColor
                    readonly property real pctVal: chip.hasLive ? Number(root.livePerColor[chip.modelData] || 0) : 0

                    variant: "common"
                    radius: Styling.radius(-4)
                    implicitWidth: chipRow.implicitWidth + 14
                    implicitHeight: 30

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            Layout.preferredWidth: 14
                            Layout.preferredHeight: 14
                            radius: 3
                            color: chip.modelData
                            border.width: 1
                            border.color: Colors.outline
                        }

                        Text {
                            text: chip.hasLive
                                ? (chip.modelData + " · " + Math.round(chip.pctVal) + "%")
                                : chip.modelData
                            font.family: Config.theme.monoFont
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overBackground
                        }

                        MacroIconButton {
                            size: 20
                            iconSize: 11
                            icon: Icons.cancel
                            tone: "danger"
                            tooltip: qsTr("Remove color")
                            onClicked: root.removeColorAt(chip.index)
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.colors.length === 0
            text: qsTr("No target colors yet — pick colors from the screen, sample the watched region, or type #RRGGBB.")
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            SettingsNumberInputRow {
                Layout.fillWidth: true
                label: qsTr("Color tolerance")
                suffix: "%"
                value: root.colorTolerance
                minValue: 1
                maxValue: 50
                onValueEdited: value => root.patch({ colorTolerance: Math.round(value) })
            }

            SettingsNumberInputRow {
                Layout.fillWidth: true
                visible: root.isArea
                label: root.colorLogic === "none" ? qsTr("Below coverage") : qsTr("Min coverage")
                suffix: "%"
                value: root.areaThreshold
                minValue: 1
                maxValue: 100
                onValueEdited: value => root.patch({ areaThreshold: Math.round(value) })
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.watchMode === "change"
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: qsTr("Reference")
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
            }

            Repeater {
                model: [
                    { id: "previous", label: "Previous frame" },
                    { id: "baseline", label: "Saved baseline" }
                ]

                MacroButton {
                    required property var modelData
                    text: modelData.label
                    implicitHeight: 30
                    tone: root.changeRef === modelData.id ? "primary" : "common"
                    onClicked: root.patch({ changeRef: modelData.id })
                }
            }

            Item {
                Layout.fillWidth: true
            }

            MacroButton {
                visible: root.changeRef === "baseline"
                icon: Icons.camera
                text: root.baselinePath.length > 0 ? qsTr("Recapture baseline") : qsTr("Capture baseline")
                tone: root.baselinePath.length > 0 ? "common" : "primary"
                enabled: root.macroId.length > 0 && !MacroService.screenCaptureHide
                onClicked: MacroService.capturePixelBaseline(
                    root.macroId,
                    root.posX,
                    root.posY,
                    root.isArea ? root.areaW : 1,
                    root.isArea ? root.areaH : 1
                )
            }

            Rectangle {
                visible: root.changeRef === "baseline" && root.baselinePath.length > 0
                Layout.preferredWidth: 44
                Layout.preferredHeight: 28
                radius: Styling.radius(-4)
                color: Colors.surfaceBright
                border.width: 1
                border.color: Colors.outline
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    cache: false
                    smooth: false
                    fillMode: Image.PreserveAspectFit
                    source: root.baselinePath.length > 0
                        ? ("file://" + root.baselinePath + "?v=" + root.baselineStamp)
                        : ""
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            SettingsNumberInputRow {
                Layout.fillWidth: true
                label: root.isArea ? qsTr("Pixel delta") : qsTr("Change threshold")
                suffix: "%"
                value: root.changeThreshold
                minValue: 1
                maxValue: 100
                onValueEdited: value => root.patch({ changeThreshold: Math.round(value) })
            }

            SettingsNumberInputRow {
                Layout.fillWidth: true
                visible: root.isArea
                label: qsTr("Changed area")
                suffix: "%"
                value: root.areaThreshold
                minValue: 1
                maxValue: 100
                onValueEdited: value => root.patch({ areaThreshold: Math.round(value) })
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
            color: root.liveMatched ? Colors.primary : Colors.outline
            opacity: root.liveMatched ? 0.85 : 0.45

            Behavior on width {
                enabled: Styling.animDuration > 0
                NumberAnimation {
                    duration: 80
                }
            }
        }

        Rectangle {
            x: 3 + (parent.width - 6) * Math.min(1, Math.max(0, root.effectiveThreshold / 100)) - 1
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
                text: {
                    if (root.watchMode === "change")
                        return (root.isArea ? "Changed area: " : "Pixel delta: ") + Math.round(root.liveScore) + "%";
                    if (root.colorLogic === "none")
                        return "Matched: " + root.liveCoverage.toFixed(root.isArea ? 1 : 0) + "%";
                    return (root.isArea ? "Coverage: " : "Color match: ") + Math.round(root.liveScore) + "%";
                }
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overBackground
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: "Threshold: " + Math.round(root.effectiveThreshold) + "% · click bar to adjust"
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function applyThreshold(px) {
                const pct = Math.round(Math.max(1, Math.min(99, ((px - 3) / Math.max(1, meterBar.width - 6)) * 100)));
                if (root.isArea) {
                    if (root.watchMode === "color" && root.colorLogic === "none")
                        root.patch({ areaThreshold: Math.max(1, Math.min(99, 100 - pct)) });
                    else
                        root.patch({ areaThreshold: Math.max(1, Math.min(100, pct)) });
                } else if (root.watchMode === "change") {
                    root.patch({ changeThreshold: Math.max(1, Math.min(100, pct)) });
                } else if (root.colorLogic === "none") {
                    root.patch({ colorTolerance: Math.max(1, Math.min(50, pct)) });
                } else {
                    root.patch({ colorTolerance: Math.max(1, Math.min(50, 100 - pct)) });
                }
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
        spacing: 10

        Repeater {
            model: [
                { edge: true, label: "On transition" },
                { edge: false, label: "While active" }
            ]

            MacroButton {
                required property var modelData
                text: modelData.label
                implicitHeight: 30
                tone: root.fireOnEdge === modelData.edge ? "primary" : "common"
                onClicked: root.patch({ fireOnEdge: modelData.edge })
            }
        }

        SettingsNumberInputRow {
            Layout.fillWidth: true
            label: qsTr("Hold")
            suffix: "ms"
            value: Number(root.trigger?.minHoldMs || 0)
            minValue: 0
            maxValue: 10000
            onValueEdited: value => root.patch({ minHoldMs: Math.round(value) })
        }

        SettingsNumberInputRow {
            Layout.fillWidth: true
            label: qsTr("Poll")
            suffix: "ms"
            value: Number(root.trigger?.intervalMs || 150)
            minValue: 50
            maxValue: 10000
            onValueEdited: value => root.patch({ intervalMs: Math.round(value) })
        }

        SettingsNumberInputRow {
            Layout.fillWidth: true
            label: qsTr("Cooldown")
            suffix: "ms"
            value: Number(root.trigger?.cooldownMs || 1000)
            minValue: 100
            maxValue: 300000
            onValueEdited: value => root.patch({ cooldownMs: Math.round(value) })
        }
    }
}
