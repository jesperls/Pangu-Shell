import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.config

Item {
    id: workspacesWidget
    required property var bar
    required property string orientation
    readonly property var monitor: Compositor.monitorFor(bar.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    readonly property int shownCount: Math.max(1, Config.workspaces.shown || 1)
    readonly property int workspaceGroup: Math.floor(Math.max(0, ((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) || 1) - 1) / shownCount)
    property var workspaceOccupied: []
    property var dynamicWorkspaceIds: []
    property int effectiveWorkspaceCount: Config.workspaces.dynamic ? Math.max(1, dynamicWorkspaceIds.length) : shownCount
    property int widgetPadding: 4
    property real radius: Styling.radius(0)
    property real startRadius: radius
    property real endRadius: radius
    property bool flatStyle: Config.bar?.flatButtons ?? false
    property bool enableShadow: false
    property var _desktopEntryCache: ({})

    function lookupDesktopEntry(windowClass) {
        if (!windowClass)
            return null;
        if (Object.prototype.hasOwnProperty.call(_desktopEntryCache, windowClass))
            return _desktopEntryCache[windowClass];
        const entry = DesktopEntries.heuristicLookup(windowClass) || null;
        _desktopEntryCache[windowClass] = entry;
        return entry;
    }

    Connections {
        target: AppSearch
        function onListChanged() {
            workspacesWidget._desktopEntryCache = {};
        }
    }
    
    property int baseSize: 36
    property int workspaceButtonSize: baseSize - widgetPadding * 2
    property int workspaceButtonWidth: workspaceButtonSize
    property real workspaceIconSize: Math.round(workspaceButtonWidth * 0.6)
    property real workspaceIconSizeShrinked: Math.round(workspaceButtonWidth * 0.5)
    property real workspaceIconOpacityShrinked: 1
    property real workspaceIconMarginShrinked: -4
    property int workspaceIndexInGroup: {
        const activeId = (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) || 1;
        if (Config.workspaces.dynamic) {
            return Math.max(0, dynamicWorkspaceIds.indexOf(activeId));
        }
        return Math.max(0, (activeId - 1) % shownCount);
    }
    property var occupiedRanges: []

    function updateWorkspaceOccupied() {
        if (Config.workspaces.dynamic) {
            const activeId = (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) || 1;
            const allOccupied = Compositor.workspaces.values
                .filter(ws => ws.id > 0 && Compositor.workspaceOccupationMap[ws.id])
                .map(ws => ws.id)
                .sort((a, b) => a - b);

            let occupiedIds = allOccupied.slice(0, shownCount);
            if (!occupiedIds.includes(activeId)) {
                occupiedIds = allOccupied.slice(0, Math.max(0, shownCount - 1));
                occupiedIds.push(activeId);
                occupiedIds.sort((a, b) => a - b);
            }

            dynamicWorkspaceIds = occupiedIds;
            workspaceOccupied = Array.from({
                length: dynamicWorkspaceIds.length
            }, (_, i) => Compositor.workspaceOccupationMap[dynamicWorkspaceIds[i]]);
        } else {
            workspaceOccupied = Array.from({
                length: shownCount
            }, (_, i) => {
                const wsId = workspaceGroup * shownCount + i + 1;
                return Compositor.workspaceOccupationMap[wsId];
            });
        }
        updateOccupiedRanges();
    }

    function updateOccupiedRanges() {
        const ranges = [];
        let rangeStart = -1;

        for (let i = 0; i < effectiveWorkspaceCount; i++) {
            const isOccupied = workspaceOccupied[i];

            if (isOccupied) {
                if (rangeStart === -1) {
                    rangeStart = i;
                }
            } else {
                if (rangeStart !== -1) {
                    ranges.push({
                        start: rangeStart,
                        end: i - 1
                    });
                    rangeStart = -1;
                }
            }
        }

        if (rangeStart !== -1) {
            ranges.push({
                start: rangeStart,
                end: effectiveWorkspaceCount - 1
            });
        }

        occupiedRanges = ranges;
    }

    function workspaceLabelFontSize(value) {
        const label = String(value);
        const shrink = label.length > 1 && label !== "10" ? (label.length - 1) * 2 : 0;
        return Math.round(Math.max(1, Config.theme.fontSize - shrink));
    }

    function getWorkspaceId(index) {
        if (Config.workspaces.dynamic) {
            return dynamicWorkspaceIds[index] || 1;
        }
        return workspaceGroup * shownCount + index + 1;
    }

    Timer {
        id: updateTimer
        interval: 100
        repeat: false
        onTriggered: workspacesWidget.updateWorkspaceOccupied()
    }

    Component.onCompleted: updateTimer.restart()

    Connections {
        target: Compositor.workspaces
        function onValuesChanged() {
            updateTimer.restart();
        }
    }

    Connections {
        target: activeWindow
        function onActivatedChanged() {
            updateTimer.restart();
        }
    }

    Connections {
        target: Compositor
        function onWindowListChanged() {
            updateTimer.restart();
        }
    }

    onWorkspaceGroupChanged: {
        updateTimer.restart();
    }

    implicitWidth: orientation === "vertical" ? baseSize : workspaceButtonSize * effectiveWorkspaceCount + widgetPadding * 2
    implicitHeight: orientation === "vertical" ? workspaceButtonSize * effectiveWorkspaceCount + widgetPadding * 2 : baseSize

    readonly property bool effectiveContainBar: Config.bar.containBar && ((Config.bar.frameEnabled !== undefined ? Config.bar.frameEnabled : false))

    StyledRect {
        id: bgRect
        variant: workspacesWidget.flatStyle ? "transparent" : "bg"
        anchors.fill: parent
        enableShadow: !workspacesWidget.flatStyle && workspacesWidget.enableShadow
        
        topLeftRadius: workspacesWidget.startRadius
        topRightRadius: orientation === "vertical" ? workspacesWidget.startRadius : workspacesWidget.endRadius
        bottomLeftRadius: orientation === "vertical" ? workspacesWidget.endRadius : workspacesWidget.startRadius
        bottomRightRadius: workspacesWidget.endRadius
    }

    function switchOnMonitor(cmd) {
        const monName = bar?.screen?.name ?? "";
        if (monName && Compositor.focusedMonitor?.name !== monName) {
            Compositor.dispatch(`focusmonitor ${monName}`);
        }
        Compositor.dispatch(cmd);
    }

    WheelHandler {
        onWheel: event => {
            if (event.angleDelta.y < 0)
                workspacesWidget.switchOnMonitor(`workspace r+1`);
            else if (event.angleDelta.y > 0)
                workspacesWidget.switchOnMonitor(`workspace r-1`);
        }
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onPressed: event => {
            if (event.button === Qt.BackButton) {
                Compositor.dispatch(`togglespecialworkspace`);
            }
        }
    }

    Component {
        id: workspaceButtonDelegate
        Button {
            id: button
            required property int index
            property int workspaceValue: workspacesWidget.getWorkspaceId(index)
            Layout.fillHeight: workspacesWidget.orientation === "horizontal"
            Layout.fillWidth: workspacesWidget.orientation === "vertical"
            width: workspacesWidget.workspaceButtonWidth
            height: workspacesWidget.workspaceButtonWidth
            onPressed: workspacesWidget.switchOnMonitor(`workspace ${workspaceValue}`)

            background: Item {
                id: workspaceButtonBackground
                implicitWidth: workspacesWidget.workspaceButtonWidth
                implicitHeight: workspacesWidget.workspaceButtonWidth
                property var focusedWindow: {
                    const windowsInThisWorkspace = Compositor.workspaceWindowsMap[button.workspaceValue] || [];
                    if (windowsInThisWorkspace.length === 0)
                        return null;
                    return windowsInThisWorkspace.reduce((best, win) => {
                        const bestFocus = (best && best.focusHistoryID !== undefined ? best.focusHistoryID : Infinity);
                        const winFocus = (win && win.focusHistoryID !== undefined ? win.focusHistoryID : Infinity);
                        return winFocus < bestFocus ? win : best;
                    }, null);
                }
                readonly property string focusedWindowClass: focusedWindow?.class ?? ""
                readonly property var focusedDesktopEntry: workspacesWidget.lookupDesktopEntry(focusedWindowClass)
                property var mainAppIconSource: {
                    if (focusedDesktopEntry && focusedDesktopEntry.icon) {
                        return Quickshell.iconPath(focusedDesktopEntry.icon, "image-missing");
                    }
                    return Quickshell.iconPath(AppSearch.getCachedIcon(focusedWindowClass !== "" ? focusedWindowClass : undefined), "image-missing");
                }

                Text {
                    opacity: Config.workspaces.alwaysShowNumbers || ((Config.workspaces.showNumbers && (!Config.workspaces.showAppIcons || !workspaceButtonBackground.focusedWindow || Config.workspaces.alwaysShowNumbers)) || (Config.workspaces.alwaysShowNumbers && !Config.workspaces.showAppIcons)) ? 1 : 0
                    z: 3

                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.family: Config.theme.font
                    font.pixelSize: workspacesWidget.workspaceLabelFontSize(text)
                    text: `${button.workspaceValue}`
                    elide: Text.ElideRight
                    color: ((workspacesWidget.monitor && workspacesWidget.monitor.activeWorkspace ? workspacesWidget.monitor.activeWorkspace.id : undefined) == button.workspaceValue) ? Styling.srItem("primary") : (workspacesWidget.workspaceOccupied[button.index] ? Colors.overBackground : Colors.overSecondaryFixedVariant)

                    Behavior on opacity {
                        enabled: Styling.animDuration > 0
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutQuad
                        }
                    }
                }
                Rectangle {
                    opacity: (Config.workspaces.showNumbers || Config.workspaces.alwaysShowNumbers || (Config.workspaces.showAppIcons && workspaceButtonBackground.focusedWindow)) ? 0 : (((workspacesWidget.monitor && workspacesWidget.monitor.activeWorkspace ? workspacesWidget.monitor.activeWorkspace.id : undefined) == button.workspaceValue) || workspacesWidget.workspaceOccupied[button.index] ? 1 : 0.5)
                    visible: opacity > 0
                    anchors.centerIn: parent
                    width: workspacesWidget.workspaceButtonWidth * 0.2
                    height: width
                    radius: width / 2
                    color: ((workspacesWidget.monitor && workspacesWidget.monitor.activeWorkspace ? workspacesWidget.monitor.activeWorkspace.id : undefined) == button.workspaceValue) ? Styling.srItem("primary") : Colors.overBackground

                    Behavior on opacity {
                        enabled: Styling.animDuration > 0
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutQuad
                        }
                    }
                }
                Item {
                    anchors.centerIn: parent
                    width: workspacesWidget.workspaceButtonWidth
                    height: workspacesWidget.workspaceButtonWidth
                    opacity: !Config.workspaces.showAppIcons ? 0 : (workspaceButtonBackground.focusedWindow && !Config.workspaces.alwaysShowNumbers && Config.workspaces.showAppIcons) ? 1 : workspaceButtonBackground.focusedWindow ? workspacesWidget.workspaceIconOpacityShrinked : 0
                    visible: opacity > 0
                    IconImage {
                        id: mainAppIcon
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.bottomMargin: (!Config.workspaces.alwaysShowNumbers && Config.workspaces.showAppIcons) ? Math.round((workspacesWidget.workspaceButtonWidth - workspacesWidget.workspaceIconSize) / 2) : workspacesWidget.workspaceIconMarginShrinked
                        anchors.rightMargin: (!Config.workspaces.alwaysShowNumbers && Config.workspaces.showAppIcons) ? Math.round((workspacesWidget.workspaceButtonWidth - workspacesWidget.workspaceIconSize) / 2) : workspacesWidget.workspaceIconMarginShrinked

                        source: workspaceButtonBackground.mainAppIconSource
                        implicitSize: (!Config.workspaces.alwaysShowNumbers && Config.workspaces.showAppIcons) ? workspacesWidget.workspaceIconSize : workspacesWidget.workspaceIconSizeShrinked

                        Behavior on opacity {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }
                        Behavior on anchors.bottomMargin {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }
                        Behavior on anchors.rightMargin {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }
                        Behavior on implicitSize {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }
                    }

                    Tinted {
                        sourceItem: mainAppIcon
                        anchors.fill: mainAppIcon
                    }
                }
            }
        }
    }

    Loader {
        id: horizontalWorkspacesLoader
        anchors.fill: parent
        active: workspacesWidget.orientation === "horizontal"
        visible: active
        sourceComponent: Item {
            anchors.fill: parent

            Item {
                id: rowLayout
                z: 1
                anchors.fill: parent
                anchors.margins: workspacesWidget.widgetPadding

                Repeater {
                    model: workspacesWidget.occupiedRanges

                    StyledRect {
                        variant: "focus"
                        required property int index
                        required property var modelData
                        z: 1
                        width: (modelData.end - modelData.start + 1) * workspacesWidget.workspaceButtonWidth
                        height: workspacesWidget.workspaceButtonWidth
                        radius: workspacesWidget.startRadius > 0 ? Math.max(workspacesWidget.startRadius - workspacesWidget.widgetPadding, 0) : 0
                        opacity: Config.theme.srFocus.opacity
                        x: modelData.start * workspacesWidget.workspaceButtonWidth
                        y: 0

                        Behavior on opacity {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Math.max(0, Styling.animDuration - 100)
                                easing.type: Easing.OutQuad
                            }
                        }
                        Behavior on x {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Math.max(0, Styling.animDuration - 100)
                                easing.type: Easing.OutQuad
                            }
                        }
                        Behavior on width {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Math.max(0, Styling.animDuration - 100)
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }
            }

            StyledRect {
                id: activeHighlightH
                variant: "primary"
                z: 2
                property real activeWorkspaceMargin: 4
                property real idx1: workspacesWidget.workspaceIndexInGroup
                property real idx2: workspacesWidget.workspaceIndexInGroup

                implicitWidth: Math.abs(idx1 - idx2) * workspacesWidget.workspaceButtonWidth + workspacesWidget.workspaceButtonWidth - activeWorkspaceMargin * 2
                implicitHeight: workspacesWidget.workspaceButtonWidth - activeWorkspaceMargin * 2

                radius: {
                    const activeWorkspaceId = (workspacesWidget.monitor && workspacesWidget.monitor.activeWorkspace ? workspacesWidget.monitor.activeWorkspace.id : undefined) || 1;
                    const currentWorkspaceHasWindows = Compositor.workspaceOccupationMap[activeWorkspaceId];
                    if (workspacesWidget.radius === 0)
                        return 0;
                    return currentWorkspaceHasWindows ? workspacesWidget.radius > 0 ? Math.max(workspacesWidget.radius - workspacesWidget.widgetPadding - activeWorkspaceMargin, 0) : 0 : implicitHeight / 2;
                }

                anchors.verticalCenter: parent.verticalCenter
                x: Math.min(idx1, idx2) * workspacesWidget.workspaceButtonWidth + activeWorkspaceMargin + workspacesWidget.widgetPadding

                Behavior on activeWorkspaceMargin {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration / 2
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on idx1 {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration / 3
                        easing.type: Easing.OutSine
                    }
                }
                Behavior on idx2 {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration
                        easing.type: Easing.OutSine
                    }
                }
            }

            RowLayout {
                id: rowLayoutNumbers
                z: 3
                spacing: 0
                anchors.fill: parent
                anchors.margins: workspacesWidget.widgetPadding
                implicitHeight: workspacesWidget.workspaceButtonWidth

                Repeater {
                    model: workspacesWidget.effectiveWorkspaceCount
                    delegate: workspaceButtonDelegate
                }
            }
        }
    }

    Loader {
        id: verticalWorkspacesLoader
        anchors.fill: parent
        active: workspacesWidget.orientation === "vertical"
        visible: active
        sourceComponent: Item {
            anchors.fill: parent

            Item {
                id: columnLayout
                z: 1
                anchors.fill: parent
                anchors.margins: workspacesWidget.widgetPadding

                Repeater {
                    model: workspacesWidget.occupiedRanges

                    StyledRect {
                        variant: "focus"
                        required property int index
                        required property var modelData
                        z: 1
                        width: workspacesWidget.workspaceButtonWidth
                        height: (modelData.end - modelData.start + 1) * workspacesWidget.workspaceButtonWidth
                        radius: workspacesWidget.startRadius > 0 ? Math.max(workspacesWidget.startRadius - workspacesWidget.widgetPadding, 0) : 0
                        opacity: Config.theme.srFocus.opacity
                        x: 0
                        y: modelData.start * workspacesWidget.workspaceButtonWidth

                        Behavior on opacity {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Math.max(0, Styling.animDuration - 100)
                                easing.type: Easing.OutQuad
                            }
                        }
                        Behavior on y {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Math.max(0, Styling.animDuration - 100)
                                easing.type: Easing.OutQuad
                            }
                        }
                        Behavior on height {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Math.max(0, Styling.animDuration - 100)
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }
            }

            StyledRect {
                id: activeHighlightV
                variant: "primary"
                z: 2
                property real activeWorkspaceMargin: 4
                property real idx1: workspacesWidget.workspaceIndexInGroup
                property real idx2: workspacesWidget.workspaceIndexInGroup

                implicitWidth: workspacesWidget.workspaceButtonWidth - activeWorkspaceMargin * 2
                implicitHeight: Math.abs(idx1 - idx2) * workspacesWidget.workspaceButtonWidth + workspacesWidget.workspaceButtonWidth - activeWorkspaceMargin * 2

                radius: {
                    const activeWorkspaceId = (workspacesWidget.monitor && workspacesWidget.monitor.activeWorkspace ? workspacesWidget.monitor.activeWorkspace.id : undefined) || 1;
                    const currentWorkspaceHasWindows = Compositor.workspaceOccupationMap[activeWorkspaceId];
                    if (workspacesWidget.radius === 0)
                        return 0;
                    return currentWorkspaceHasWindows ? workspacesWidget.radius > 0 ? Math.max(workspacesWidget.radius - workspacesWidget.widgetPadding - activeWorkspaceMargin, 0) : 0 : implicitWidth / 2;
                }

                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.min(idx1, idx2) * workspacesWidget.workspaceButtonWidth + activeWorkspaceMargin + workspacesWidget.widgetPadding

                Behavior on activeWorkspaceMargin {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration / 2
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on idx1 {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration / 3
                        easing.type: Easing.OutSine
                    }
                }
                Behavior on idx2 {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration
                        easing.type: Easing.OutSine
                    }
                }
            }

            ColumnLayout {
                id: columnLayoutNumbers
                z: 3
                spacing: 0
                anchors.fill: parent
                anchors.margins: workspacesWidget.widgetPadding
                implicitWidth: workspacesWidget.workspaceButtonWidth

                Repeater {
                    model: workspacesWidget.effectiveWorkspaceCount
                    delegate: workspaceButtonDelegate
                }
            }
        }
    }
}
