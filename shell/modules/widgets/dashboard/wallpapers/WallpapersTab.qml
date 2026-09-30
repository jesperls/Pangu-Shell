import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.config

FocusScope {
    id: wallpapersTabRoot

    implicitWidth: 800

    property string searchText: ""
    property int selectedIndex: GlobalStates.wallpaperSelectedIndex

    function setSelectedIndex(newIndex: int) {
        GlobalStates.wallpaperSelectedIndex = newIndex;
        selectedIndex = newIndex;
        selectedPath = filteredWallpapers[newIndex] || "";
    }

    readonly property string currentScreenName: Compositor.focusedMonitor ? Compositor.focusedMonitor.name : ""

    property bool isPerScreen: {
        if (!GlobalStates.wallpaperManager || currentScreenName === "") return false;
        let perScreen = GlobalStates.wallpaperManager.perScreenWallpapers || {};
        return perScreen[currentScreenName] !== undefined;
    }

    function togglePerScreenMode() {
        if (!GlobalStates.wallpaperManager || currentScreenName === "") return;
        
        if (isPerScreen) {
            GlobalStates.wallpaperManager.clearPerScreenWallpaper(currentScreenName);
        } else {
            let currentWall = GlobalStates.wallpaperManager.currentWallpaper;
            if (currentWall) {
                GlobalStates.wallpaperManager.setWallpaper(currentWall, currentScreenName);
            }
        }
    }

    property var activeFilters: []

    readonly property int gridColumns: Math.max(1, Math.floor(width / (Math.max(100, Math.min(240, Config.dashboard.wallpaperCardWidth ?? 160)) + 12)))
    readonly property int wallpaperMargin: 6
    readonly property bool showNames: Config.dashboard.wallpaperShowNames ?? true
    property string selectedPath: ""

    property var focusableElements: [
        {
            id: "perScreenCheckbox",
            focusFunc: function () {
                perScreenChip.forceActiveFocus();
            }
        },
        {
            id: "oledCheckbox",
            focusFunc: function () {
                oledChip.forceActiveFocus();
            }
        },
        {
            id: "tintCheckbox",
            focusFunc: function () {
                tintChip.forceActiveFocus();
            }
        },
        {
            id: "schemeSelector",
            focusFunc: function () {
                schemeSelector.openAndFocus();
            }
        },
        {
            id: "filters",
            focusFunc: function () {
                wallpapersFilterBar.focusFilters();
            }
        }
    ]

    property int currentFocusIndex: -1

    function focusSearch() {
        currentFocusIndex = -1;
        wallpaperSearchInput.focusInput();

        if (selectedIndex === -1 && filteredWallpapers.length > 0) {
            const currentIndex = findCurrentWallpaperIndex();
            setSelectedIndex(currentIndex !== -1 ? currentIndex : 0);
        }
    }

    function focusSearchInput() {
        focusSearch();
    }

    function focusFilters() {
        currentFocusIndex = 4;
        focusableElements[4].focusFunc();
    }

    function focusNextElement() {
        if (currentFocusIndex === -1) {
            currentFocusIndex = 0;
            focusableElements[currentFocusIndex].focusFunc();
        } else if (currentFocusIndex === focusableElements.length - 1) {
            focusSearch();
        } else {
            currentFocusIndex++;
            focusableElements[currentFocusIndex].focusFunc();
        }
    }

    function focusPreviousElement() {
        if (currentFocusIndex === -1 || currentFocusIndex === 0) {
            focusSearch();
        } else {
            currentFocusIndex--;
            focusableElements[currentFocusIndex].focusFunc();
        }
    }

    function revealCurrentWallpaper() {
        const currentIndex = findCurrentWallpaperIndex();
        if (currentIndex !== -1) {
            setSelectedIndex(currentIndex);

            wallpaperGrid.positionViewAtIndex(currentIndex, GridView.Contain);
        }
    }

    function findCurrentWallpaperIndex() {
        if (!GlobalStates.wallpaperManager) {
            return -1;
        }

        let perScreen = GlobalStates.wallpaperManager.perScreenWallpapers || {};
        let currentWallpaper = "";
        
        if (currentScreenName !== "" && perScreen[currentScreenName] !== undefined) {
            currentWallpaper = perScreen[currentScreenName];
        } else {
            currentWallpaper = GlobalStates.wallpaperManager.currentWallpaper;
        }

        if (!currentWallpaper) {
            return -1;
        }

        return filteredWallpapers.indexOf(currentWallpaper);
    }

    Component.onCompleted: {
        revealTimer.start();
    }

    onVisibleChanged: {
        if (visible) {
            if (GlobalStates.wallpaperManager) {
                console.log("WallpapersTab became visible, updating subfolders");
                GlobalStates.wallpaperManager.scanSubfolders();
            }
            revealTimer.restart();
        }
    }

    Timer {
        id: revealTimer
        interval: 50
        repeat: false
        onTriggered: {
            revealCurrentWallpaper();
            focusSearch();
        }
    }

    property var filteredWallpapers: {
        if (!GlobalStates.wallpaperManager)
            return [];

        let wallpapers = GlobalStates.wallpaperManager.wallpaperPaths;

        if (searchText.length > 0) {
            wallpapers = wallpapers.filter(function (path) {
                const fileName = GlobalStates.wallpaperManager.getDisplayName(path).toLowerCase();
                return fileName.includes(searchText.toLowerCase());
            });
        }

        if (activeFilters.length > 0) {
            wallpapers = wallpapers.filter(function (path) {
                const fileType = GlobalStates.wallpaperManager.getFileType(path);
                const subfolder = GlobalStates.wallpaperManager.getSubfolderFromPath(path);

                for (var i = 0; i < activeFilters.length; i++) {
                    var filter = activeFilters[i];
                    if (filter === fileType) {
                        return true;
                    }
                    if (filter.startsWith("subfolder_") && subfolder === filter.replace("subfolder_", "")) {
                        return true;
                    }
                }
                return false;
            });
        }

        return wallpapers;
    }

    onFilteredWallpapersChanged: {
        const previous = filteredWallpapers.indexOf(selectedPath);
        const current = findCurrentWallpaperIndex();
        setSelectedIndex(previous >= 0 ? previous : current >= 0 ? current : filteredWallpapers.length ? 0 : -1);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            spacing: 8
            z: 1000  // keep the dropdown above the grid

            SearchInput {
                id: wallpaperSearchInput
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: searchText
                placeholderText: "Search wallpapers..."
                iconText: ""
                clearOnEscape: false
                handleTabNavigation: true
                disableCursorNavigation: true
                radius: Styling.radius(4)

                onSearchTextChanged: text => searchText = text

                onEscapePressed: {
                    Visibilities.setActiveModule("");
                }

                onTabPressed: {
                    focusNextElement();
                }

                onShiftTabPressed: {
                    focusPreviousElement();
                }

                onDownPressed: {
                    if (filteredWallpapers.length > 0) {
                        if (selectedIndex < filteredWallpapers.length - 1) {
                            let newIndex = selectedIndex + wallpapersTabRoot.gridColumns;
                            if (newIndex >= filteredWallpapers.length) {
                                newIndex = filteredWallpapers.length - 1;
                            }
                            setSelectedIndex(newIndex);
                        } else if (selectedIndex === -1) {
                            setSelectedIndex(0);
                        }
                    }
                }
                onUpPressed: {
                    if (filteredWallpapers.length > 0) {
                        if (selectedIndex === -1) {
                            setSelectedIndex(0);
                        } else if (selectedIndex >= wallpapersTabRoot.gridColumns) {
                            setSelectedIndex(selectedIndex - wallpapersTabRoot.gridColumns);
                        }
                    }
                }
                onLeftPressed: {
                    if (filteredWallpapers.length > 0) {
                        if (selectedIndex === -1) {
                            setSelectedIndex(0);
                        } else if (selectedIndex > 0) {
                            setSelectedIndex(selectedIndex - 1);
                        }
                    }
                }
                onRightPressed: {
                    if (filteredWallpapers.length > 0) {
                        if (selectedIndex < filteredWallpapers.length - 1) {
                            setSelectedIndex(selectedIndex + 1);
                        } else if (selectedIndex === -1) {
                            setSelectedIndex(0);
                        }
                    }
                }
                onAccepted: {
                    if (selectedIndex >= 0 && selectedIndex < filteredWallpapers.length) {
                        let selectedWallpaper = filteredWallpapers[selectedIndex];
                        if (selectedWallpaper && GlobalStates.wallpaperManager) {
                            if (isPerScreen && currentScreenName !== "") {
                                GlobalStates.wallpaperManager.setWallpaper(selectedWallpaper, currentScreenName);
                            } else {
                                GlobalStates.wallpaperManager.setWallpaper(selectedWallpaper);
                            }
                        }
                    }
                }
            }

            Item {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 48

                SchemeSelector {
                    id: schemeSelector
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right

                    onSchemeSelectorClosed: {
                        wallpapersTabRoot.focusSearch();
                    }

                    onEscapePressedOnScheme: {
                        wallpapersTabRoot.focusSearch();
                    }

                    onTabPressed: {
                        wallpapersTabRoot.focusNextElement();
                    }

                    onShiftTabPressed: {
                        wallpapersTabRoot.focusPreviousElement();
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ControlChip {
                id: perScreenChip
                text: currentScreenName || "This screen"
                checked: isPerScreen
                enabled: currentScreenName !== ""
                Accessible.name: "Use a separate wallpaper for " + text
                onClicked: togglePerScreenMode()
                onTabPressed: focusNextElement()
                onShiftTabPressed: focusPreviousElement()
                onEscapePressed: focusSearch()
                StyledToolTip {
                    show: perScreenChip.hovered
                    tooltipText: "Separate wallpaper for this screen"
                }
            }

            ControlChip {
                id: oledChip
                text: "OLED black"
                checked: Config.theme.oledMode
                enabled: !Config.theme.lightMode
                onClicked: Config.theme.oledMode = !Config.theme.oledMode
                onTabPressed: focusNextElement()
                onShiftTabPressed: focusPreviousElement()
                onEscapePressed: focusSearch()
            }

            ControlChip {
                id: tintChip
                text: "Wallpaper tint"
                checked: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.tintEnabled : false
                onClicked: {
                    if (GlobalStates.wallpaperManager)
                        GlobalStates.wallpaperManager.tintEnabled = !GlobalStates.wallpaperManager.tintEnabled;
                }
                onTabPressed: focusNextElement()
                onShiftTabPressed: focusPreviousElement()
                onEscapePressed: focusSearch()
            }

            Item { Layout.fillWidth: true }
            Text {
                text: filteredWallpapers.length + (filteredWallpapers.length === 1 ? " wallpaper" : " wallpapers")
                color: Colors.overSurfaceVariant
                font.family: Config.theme.font
                font.pixelSize: Config.theme.fontSize - 1
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: wallpapersFilterBar.height

            FilterBar {
                id: wallpapersFilterBar
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, parent.width)
                activeFilters: wallpapersTabRoot.activeFilters

                onActiveFiltersChanged: {
                    wallpapersTabRoot.activeFilters = activeFilters;
                }

                onEscapePressedOnFilters: {
                    wallpapersTabRoot.focusSearch();
                }

                onTabPressed: {
                    wallpapersTabRoot.focusNextElement();
                }

                onShiftTabPressed: {
                    wallpapersTabRoot.focusPreviousElement();
                }
            }
        }

        ClippingRectangle {
            id: wallpaperGridContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"
            radius: Styling.radius(4)
            clip: true

            readonly property real gridWidth: width + (wallpapersTabRoot.wallpaperMargin * 2)
            readonly property real cellSize: gridWidth / wallpapersTabRoot.gridColumns

            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: filteredWallpapers.length === 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Icons.wallpapers
                    font.family: Icons.font
                    font.pixelSize: 32
                    color: Colors.overSurfaceVariant
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: searchText || activeFilters.length ? "No matching wallpapers" : "No wallpapers yet"
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: searchText || activeFilters.length ? "Try another search or clear the filters" : "Choose a wallpaper folder in Theme settings"
                    color: Colors.overSurfaceVariant
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                }
            }

            GridView {
                id: wallpaperGrid
                anchors.fill: parent
                anchors.margins: -wallpapersTabRoot.wallpaperMargin
                cellWidth: wallpaperGridContainer.cellSize
                cellHeight: wallpaperGridContainer.cellSize * 0.625 + (wallpapersTabRoot.showNames ? 36 : 12)
                flow: GridView.FlowLeftToRight
                boundsBehavior: Flickable.StopAtBounds
                model: filteredWallpapers
                currentIndex: selectedIndex
                keyNavigationEnabled: false

                property bool isScrolling: dragging || flicking

                highlightFollowsCurrentItem: !isScrolling

                cacheBuffer: cellHeight
                displayMarginBeginning: cellHeight
                displayMarginEnd: cellHeight
                reuseItems: true

                flickDeceleration: 5000
                maximumFlickVelocity: 8000

                highlight: null

                delegate: Rectangle {
                    id: wallpaperCard
                    required property string modelData
                    required property int index
                    width: wallpaperGrid.cellWidth
                    height: wallpaperGrid.cellHeight
                    color: "transparent"

                    property bool isCurrentWallpaper: {
                        if (!GlobalStates.wallpaperManager)
                            return false;
                            
                        let perScreen = GlobalStates.wallpaperManager.perScreenWallpapers || {};
                        let currentWall = "";
                        if (currentScreenName !== "" && perScreen[currentScreenName] !== undefined) {
                            currentWall = perScreen[currentScreenName];
                        } else {
                            currentWall = GlobalStates.wallpaperManager.currentWallpaper;
                        }
                        return currentWall === modelData;
                    }

                    property bool isHovered: false
                    property bool isSelected: selectedIndex === index

                    readonly property bool isInViewport: {
                        var gridTop = wallpaperGrid.contentY;
                        var gridBottom = gridTop + wallpaperGrid.height;
                        var itemTop = y;
                        var itemBottom = itemTop + height;

                        var buffer = wallpaperGrid.cellHeight;
                        return itemBottom + buffer >= gridTop && itemTop - buffer <= gridBottom;
                    }

                    StyledRect {
                        id: cardBackground
                        anchors.fill: parent
                        anchors.margins: wallpapersTabRoot.wallpaperMargin
                        variant: wallpaperCard.isSelected ? "focus" : "common"
                        radius: Styling.radius(2)

                        ClippingRectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 3
                            height: parent.height - (wallpapersTabRoot.showNames ? 30 : 6)
                            radius: Styling.radius(0)
                            color: Colors.surface

                            Loader {
                                anchors.fill: parent
                                sourceComponent: staticImageComponent
                                property string sourceFile: wallpaperCard.modelData
                                active: wallpaperCard.isInViewport && wallpapersTabRoot.visible && GlobalStates.dashboardOpen
                                asynchronous: true
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            radius: cardBackground.radius
                            border.width: wallpaperCard.isSelected || wallpaperCard.isCurrentWallpaper ? 2 : 1
                            border.color: wallpaperCard.isSelected || wallpaperCard.isCurrentWallpaper ? Colors.primary
                                : wallpaperCard.isHovered ? Colors.outline : "transparent"
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 9
                            text: GlobalStates.wallpaperManager?.getDisplayName(wallpaperCard.modelData) ?? ""
                            visible: wallpapersTabRoot.showNames
                            color: cardBackground.item
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: wallpaperCard.isCurrentWallpaper ? Font.DemiBold : Font.Normal
                            elide: Text.ElideMiddle
                        }

                        StyledRect {
                            id: currentBadge
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 8
                            width: 24
                            height: 24
                            radius: Styling.radius(-2)
                            variant: "primary"
                            visible: wallpaperCard.isCurrentWallpaper
                            Text {
                                anchors.centerIn: parent
                                text: Icons.accept
                                font.family: Icons.font
                                font.pixelSize: 14
                                color: currentBadge.item
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: !wallpaperGrid.isScrolling
                        cursorShape: Qt.PointingHandCursor

                        onEntered: {
                            if (wallpaperGrid.isScrolling)
                                return;
                            parent.isHovered = true;
                        }
                        onExited: {
                            parent.isHovered = false;
                        }
                        onPressed: {
                            if (!wallpaperGrid.isScrolling)
                                parent.scale = 0.95;
                        }
                        onReleased: parent.scale = 1.0
                        onCanceled: parent.scale = 1.0

                        onClicked: {
                            if (wallpaperGrid.isScrolling)
                                return;
                            setSelectedIndex(index);
                            if (GlobalStates.wallpaperManager) {
                                if (isPerScreen && currentScreenName !== "") {
                                    GlobalStates.wallpaperManager.setWallpaper(modelData, currentScreenName);
                                } else {
                                    GlobalStates.wallpaperManager.setWallpaper(modelData);
                                }
                            }
                        }
                    }

                    StyledToolTip {
                        show: wallpaperCard.isHovered && !wallpaperGrid.isScrolling
                        tooltipText: GlobalStates.wallpaperManager?.getDisplayName(wallpaperCard.modelData) ?? ""
                        description: wallpaperCard.isCurrentWallpaper ? "Current wallpaper" : "Click to apply"
                    }

                    Behavior on color {
                        enabled: Styling.animDuration > 0
                        ColorAnimation {
                            duration: Styling.animDuration / 2
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on scale {
                        enabled: Styling.animDuration > 0
                        NumberAnimation {
                            duration: Styling.animDuration / 3
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }

    Component {
        id: staticImageComponent
        Image {
            mipmap: true
            source: {
                if (!parent.sourceFile || !GlobalStates.wallpaperManager)
                    return "";

                var thumbnailPath = GlobalStates.wallpaperManager.getThumbnailPath(parent.sourceFile);
                var version = GlobalStates.wallpaperManager.thumbnailsVersion;
                return "file://" + thumbnailPath + "?v=" + version;
            }
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            cache: true
            sourceSize.width: wallpaperGridContainer.cellSize
            sourceSize.height: Math.round(wallpaperGridContainer.cellSize * 0.625)

            Text {
                anchors.centerIn: parent
                visible: parent.status === Image.Error || parent.status === Image.Null
                text: Icons.image
                font.family: Icons.font
                font.pixelSize: 28
                color: Colors.overSurfaceVariant
            }
        }
    }
}
