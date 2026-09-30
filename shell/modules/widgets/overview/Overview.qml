import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config



Item {
    id: overviewRoot

    readonly property real scale: Config.overview.scale
    readonly property int rows: Config.overview.rows
    readonly property int columns: Config.overview.columns
    readonly property int workspacesShown: rows * columns
    readonly property real workspaceSpacing: Config.overview.workspaceSpacing
    readonly property real workspacePadding: 8
    readonly property color activeBorderColor: Styling.srItem("overprimary")

    property var currentScreen: null
    readonly property var monitor: currentScreen ? Compositor.monitorFor(currentScreen) : Compositor.focusedMonitor
    readonly property int workspaceGroup: Math.floor((monitor?.activeWorkspace?.id - 1 || 0) / workspacesShown)

    readonly property var windowList: Compositor.windowList
    readonly property var monitors: Compositor.monitors.values
    readonly property int monitorId: monitor?.id ?? -1
    readonly property var monitorData: monitors.find(m => m.id === monitorId) ?? null

    readonly property string barPosition: Config.bar.position
    readonly property var barPanel: monitor ? Visibilities.getBarPanelForScreen(monitor.name) : null
    readonly property bool isBarPinned: barPanel ? barPanel.pinned : (Config.bar.pinnedOnStartup ?? true)
    readonly property int barReserved: isBarPinned ? (Config.showBackground ? 44 : 40) : 0

    property string searchQuery: ""
    property var matchingWindows: []
    property int selectedMatchIndex: 0

    function resetSearch() {
        searchQuery = "";
        matchingWindows = [];
        selectedMatchIndex = 0;
    }

    onSearchQueryChanged: updateMatchingWindows()
    onWindowListChanged: updateMatchingWindows()

    function fuzzyMatch(query, target) {
        if (query.length === 0)
            return true;
        if (target.length === 0)
            return false;

        let queryIndex = 0;
        for (let i = 0; i < target.length && queryIndex < query.length; i++) {
            if (target[i] === query[queryIndex]) {
                queryIndex++;
            }
        }
        return queryIndex === query.length;
    }

    function fuzzyScore(query, target) {
        if (query.length === 0)
            return 0;
        if (target.length === 0)
            return -1;

        if (target.includes(query))
            return 1000 + (100 - target.length);

        let queryIndex = 0;
        let consecutiveMatches = 0;
        let maxConsecutive = 0;
        let score = 0;

        for (let i = 0; i < target.length && queryIndex < query.length; i++) {
            if (target[i] === query[queryIndex]) {
                queryIndex++;
                consecutiveMatches++;
                maxConsecutive = Math.max(maxConsecutive, consecutiveMatches);
                if (i === 0 || target[i - 1] === ' ' || target[i - 1] === '-' || target[i - 1] === '_') {
                    score += 10;
                }
            } else {
                consecutiveMatches = 0;
            }
        }

        if (queryIndex !== query.length)
            return -1;  // No match

        return score + maxConsecutive * 5;
    }

    function updateMatchingWindows() {
        if (searchQuery.length === 0) {
            matchingWindows = [];
            selectedMatchIndex = 0;
            return;
        }

        const query = searchQuery.toLowerCase();
        const matches = windowList.filter(win => {
            if (!win)
                return false;
            const title = (win.title || "").toLowerCase();
            const windowClass = (win.class || "").toLowerCase();
            return fuzzyMatch(query, title) || fuzzyMatch(query, windowClass);
        }).map(win => ({
                    window: win,
                    score: Math.max(fuzzyScore(query, (win.title || "").toLowerCase()), fuzzyScore(query, (win.class || "").toLowerCase()))
                })).sort((a, b) => b.score - a.score).map(item => item.window);

        matchingWindows = matches;
        selectedMatchIndex = matches.length > 0 ? 0 : -1;
    }

    function navigateToSelectedWindow() {
        if (matchingWindows.length === 0 || selectedMatchIndex < 0)
            return;

        const win = matchingWindows[selectedMatchIndex];
        if (!win)
            return;

        Visibilities.setActiveModule("", true);
        Qt.callLater(() => {
            Compositor.dispatch(`focuswindow address:${win.address}`);
        });
    }

    function selectNextMatch() {
        if (matchingWindows.length === 0)
            return;
        selectedMatchIndex = (selectedMatchIndex + 1) % matchingWindows.length;
    }

    function selectPrevMatch() {
        if (matchingWindows.length === 0)
            return;
        selectedMatchIndex = (selectedMatchIndex - 1 + matchingWindows.length) % matchingWindows.length;
    }

    function isWindowMatched(windowAddress) {
        if (searchQuery.length === 0)
            return false;
        return matchingWindows.some(win => win?.address === windowAddress);
    }

    function isWindowSelected(windowAddress) {
        if (matchingWindows.length === 0 || selectedMatchIndex < 0)
            return false;
        return matchingWindows[selectedMatchIndex]?.address === windowAddress;
    }

    readonly property real workspaceImplicitWidth: {
        if (!monitorData)
            return 200;
        let scaledWidth = monitorData.logicalWidth * scale;
        if (barPosition === "left" || barPosition === "right") {
            scaledWidth -= barReserved * scale;
        }
        return Math.max(0, Math.round(scaledWidth));
    }

    readonly property real workspaceImplicitHeight: {
        if (!monitorData)
            return 150;
        let scaledHeight = monitorData.logicalHeight * scale;
        if (barPosition === "top" || barPosition === "bottom") {
            scaledHeight -= barReserved * scale;
        }
        return Math.max(0, Math.round(scaledHeight));
    }

    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1

    implicitWidth: overviewBackground.implicitWidth
    implicitHeight: overviewBackground.implicitHeight

    Item {
        id: overviewBackground
        anchors.centerIn: parent

        implicitWidth: workspaceColumnLayout.implicitWidth
        implicitHeight: workspaceColumnLayout.implicitHeight

        ColumnLayout {
            id: workspaceColumnLayout
            anchors.centerIn: parent
            spacing: workspaceSpacing

            Repeater {
                model: overviewRoot.rows
                delegate: RowLayout {
                    id: row
                    property int rowIndex: index
                    spacing: workspaceSpacing

                    Repeater {
                        model: overviewRoot.columns
                        Rectangle {
                            id: workspace
                            property int colIndex: index
                            property int workspaceValue: overviewRoot.workspaceGroup * workspacesShown + rowIndex * overviewRoot.columns + colIndex + 1
                            property color hoveredBorderColor: Colors.outline
                            property bool hoveredWhileDragging: false

                            implicitWidth: overviewRoot.workspaceImplicitWidth + workspacePadding
                            implicitHeight: overviewRoot.workspaceImplicitHeight + workspacePadding
                            color: "transparent"
                            radius: Styling.radius(2)
                            border.width: 2
                            border.color: hoveredWhileDragging ? hoveredBorderColor : "transparent"
                            clip: true

                            TintedWallpaper {
                                id: workspaceWallpaper
                                anchors.fill: parent
                                radius: Styling.radius(2)
                                tintEnabled: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.tintEnabled : false
                                sourceSize: Qt.size(960, 540)

                                property string lockscreenFramePath: {
                                    if (!GlobalStates.wallpaperManager)
                                        return "";
                                    return GlobalStates.wallpaperManager.getLockscreenFramePath(GlobalStates.wallpaperManager.currentWallpaper);
                                }

                                source: lockscreenFramePath ? "file://" + lockscreenFramePath : ""
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onClicked: {
                                    if (overviewRoot.draggingTargetWorkspace === -1) {
                                        Compositor.dispatch(`workspace ${workspaceValue}`);
                                    }
                                }
                                onDoubleClicked: {
                                    if (overviewRoot.draggingTargetWorkspace === -1) {
                                        Visibilities.setActiveModule("");
                                        Compositor.dispatch(`workspace ${workspaceValue}`);
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: {
                                    overviewRoot.draggingTargetWorkspace = workspaceValue;
                                    if (overviewRoot.draggingFromWorkspace == overviewRoot.draggingTargetWorkspace)
                                        return;
                                    hoveredWhileDragging = true;
                                }
                                onExited: {
                                    hoveredWhileDragging = false;
                                    if (overviewRoot.draggingTargetWorkspace == workspaceValue)
                                        overviewRoot.draggingTargetWorkspace = -1;
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: windowSpace
            anchors.centerIn: parent
            implicitWidth: workspaceColumnLayout.implicitWidth
            implicitHeight: workspaceColumnLayout.implicitHeight

            readonly property var filteredWindowData: {
                const minWs = overviewRoot.workspaceGroup * overviewRoot.workspacesShown;
                const maxWs = (overviewRoot.workspaceGroup + 1) * overviewRoot.workspacesShown;
                const monId = overviewRoot.monitorId;
                const toplevels = ToplevelManager.toplevels.values;

                return overviewRoot.windowList.filter(win => {
                    const wsId = win?.workspace?.id;
                    return wsId > minWs && wsId <= maxWs && win.monitor === monId;
                }).map(win => ({
                            windowData: win,
                            toplevel: (() => {
                                const cls = win.class || "";
                                if (!cls) return null;
                                const candidates = toplevels.filter(t => t.appId === cls);
                                if (candidates.length <= 1) return candidates[0] || null;
                                return candidates.find(t => t.title === (win.title || "")) || candidates[0];
                            })()
                        }));
            }

            Repeater {
                model: windowSpace.filteredWindowData

                delegate: OverviewWindow {
                    id: window
                    required property var modelData
                    windowData: modelData.windowData
                    toplevel: modelData.toplevel
                    scale: overviewRoot.scale
                    overviewItem: overviewRoot
                    availableWorkspaceWidth: overviewRoot.workspaceImplicitWidth
                    availableWorkspaceHeight: overviewRoot.workspaceImplicitHeight
                    monitorData: overviewRoot.monitorData
                    barPosition: overviewRoot.barPosition
                    barReserved: overviewRoot.barReserved

                    isSearchMatch: overviewRoot.isWindowMatched(windowData?.address)
                    isSearchSelected: overviewRoot.isWindowSelected(windowData?.address)

                    property int workspaceColIndex: (windowData?.workspace.id - 1) % overviewRoot.columns
                    property int workspaceRowIndex: Math.floor((windowData?.workspace.id - 1) % overviewRoot.workspacesShown / overviewRoot.columns)

                    xOffset: Math.round((overviewRoot.workspaceImplicitWidth + workspacePadding + workspaceSpacing) * workspaceColIndex + workspacePadding / 2)
                    yOffset: Math.round((overviewRoot.workspaceImplicitHeight + workspacePadding + workspaceSpacing) * workspaceRowIndex + workspacePadding / 2)

                    onDragStarted: overviewRoot.draggingFromWorkspace = windowData?.workspace.id || -1
                    onDragFinished: targetWorkspace => {
                        overviewRoot.draggingFromWorkspace = -1;
                    }
                    onWindowClicked: {
                        Visibilities.setActiveModule("", true);
                        Qt.callLater(() => {
                            Compositor.dispatch(`focuswindow address:${windowData.address}`);
                        });
                    }
                    onWindowClosed: {
                        Compositor.dispatch(`closewindow address:${windowData.address}`);
                    }
                }
            }

            Rectangle {
                id: focusedWorkspaceIndicator
                property int activeWorkspaceInGroup: (monitor?.activeWorkspace?.id || 1) - (overviewRoot.workspaceGroup * overviewRoot.workspacesShown)
                property int activeWorkspaceRowIndex: Math.floor((activeWorkspaceInGroup - 1) / overviewRoot.columns)
                property int activeWorkspaceColIndex: (activeWorkspaceInGroup - 1) % overviewRoot.columns

                x: Math.round((overviewRoot.workspaceImplicitWidth + workspacePadding + workspaceSpacing) * activeWorkspaceColIndex)
                y: Math.round((overviewRoot.workspaceImplicitHeight + workspacePadding + workspaceSpacing) * activeWorkspaceRowIndex)
                width: Math.round(overviewRoot.workspaceImplicitWidth + workspacePadding)
                height: Math.round(overviewRoot.workspaceImplicitHeight + workspacePadding)
                color: "transparent"
                radius: Styling.radius(2)
                border.width: 2
                border.color: overviewRoot.activeBorderColor

                Behavior on x {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on y {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
            }
        }
    }
}
