import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.config
import "../dashboard/clipboard"
import "../dashboard/emoji"
import "../dashboard/tmux"
import "../dashboard/notes"

Rectangle {
    id: root
    color: "transparent"
    
    readonly property bool isCompact: currentTab === 0 || currentTab === 2
    readonly property int configWidth: Config.launcher.width ?? 0
    readonly property int configHeight: Config.launcher.height ?? 0
    implicitWidth: configWidth > 0 ? configWidth : (isCompact ? 464 : 900)
    implicitHeight: configHeight > 0 ? configHeight : (isCompact ? 296 : 392)
    
    focus: true

    property int leftPanelWidth: isCompact ? 464 : 300
    property int currentTab: GlobalStates.widgetsTabCurrentIndex  // 0=launcher, 1=clip, 2=emoji, 3=tmux, 4=notes
    property bool prefixDisabled: false  // Flag to prevent re-activation after backspace

    onCurrentTabChanged: {
        GlobalStates.widgetsTabCurrentIndex = currentTab;
        focusSearchInput();
    }

    onActiveFocusChanged: {
        if (activeFocus) {
            focusSearchInput();
        }
    }

    Timer {
        id: focusRetryTimer
        interval: 50
        repeat: true
        running: false
        property int retries: 0
        onTriggered: {
            if (retries > 10) {
                running = false;
                return;
            }
            
            let focused = false;
            if (currentTab === 0) {
                appLauncher.focusSearchInput();
                focused = true;  // Apps launcher is usually always ready
            } else {
                let loader = internalStack.itemAt(currentTab - 1);
                if (loader && loader.item && loader.item.focusSearchInput) {
                    loader.item.focusSearchInput();
                    focused = true;
                }
            }
            
            if (focused) {
                running = false;
            }
            retries++;
        }
    }

    function focusSearchInput() {
        focusRetryTimer.retries = 0;
        focusRetryTimer.start();
    }

    Component.onCompleted: {
        focusSearchInput();
    }

    function detectPrefix(text) {
        let clipPrefix = Config.prefix.clipboard + " ";
        let emojiPrefix = Config.prefix.emoji + " ";
        let tmuxPrefix = Config.prefix.tmux + " ";
        let notesPrefix = Config.prefix.notes + " ";

        if (prefixDisabled) {
            if (text === clipPrefix || text === emojiPrefix || text === tmuxPrefix || text === notesPrefix) {
                return 0;
            } else if (!text.startsWith(clipPrefix) && !text.startsWith(emojiPrefix) && !text.startsWith(tmuxPrefix) && !text.startsWith(notesPrefix)) {
                prefixDisabled = false;
                return 0;
            } else {
                return 0;
            }
        }

        if (text === clipPrefix) {
            return 1;
        } else if (text === emojiPrefix) {
            return 2;
        } else if (text === tmuxPrefix) {
            return 3;
        } else if (text === notesPrefix) {
            return 4;
        }
        return 0;
    }

    Rectangle {
        id: appLauncher
        anchors.fill: parent
        visible: currentTab === 0
        color: "transparent"

        property string searchText: GlobalStates.launcherSearchText
        property bool showResults: searchText.length > 0
        property int selectedIndex: GlobalStates.launcherSelectedIndex

        property int expandedItemIndex: -1
        property int selectedOptionIndex: 0
        property bool keyboardNavigation: false

        property var filteredApps: []
        property var appsById: ({})

        property var pendingApps: []
        property int loadedCount: 0
        property int batchSize: 10

        Timer {
            id: incrementalLoader
            interval: 100
            repeat: true
            running: false
            onTriggered: {
                if (appLauncher.loadedCount >= appLauncher.pendingApps.length || appLauncher.batchSize <= 0) {
                    running = false;
                    return;
                }

                let endIndex = Math.min(appLauncher.loadedCount + appLauncher.batchSize, appLauncher.pendingApps.length);
                for (let i = appLauncher.loadedCount; i < endIndex; i++) {
                    let app = appLauncher.pendingApps[i];
                    appsModel.append({
                        appId: app.id,
                        appName: app.name,
                        appIcon: app.icon,
                        appComment: app.comment,
                        appExecString: app.execString,
                        appCategories: app.categories,
                        appRunInTerminal: app.runInTerminal
                    });
                }
                appLauncher.loadedCount = endIndex;
            }
        }

        property string calcExpr: ""
        property string calcResult: ""

        function calcExprFor(text) {
            const t = text.trim();
            if (t.startsWith("="))
                return t.slice(1).trim();
            if (/^[0-9(][0-9+\-*\/^%.,()!\s]*$/.test(t) && /[+\-*\/^%!]/.test(t))
                return t;
            return "";
        }

        function calcEntry() {
            const result = calcResult;
            return {
                id: "calc:" + calcExpr,
                name: result,
                icon: "font:" + Icons.sparkle,
                comment: calcExpr + "  =  " + result + "   (Enter copies)",
                execString: "",
                categories: [],
                runInTerminal: false,
                isAction: true,
                execute: () => Quickshell.execDetached(["wl-copy", result])
            };
        }

        Timer {
            id: calcDebounce
            interval: 150
            onTriggered: {
                calcProcess.running = false;
                calcProcess.command = ["qalc", "-t", appLauncher.calcExpr];
                calcProcess.running = true;
            }
        }

        Process {
            id: calcProcess
            stdout: StdioCollector {
                onStreamFinished: {
                    const result = text.trim();
                    if (result.length > 0 && result.length < 120 && result !== appLauncher.calcExpr && !result.startsWith("error")) {
                        appLauncher.calcResult = result;
                        appLauncher.updateFilteredApps();
                    }
                }
            }
        }

        function updateFilteredApps() {
            if (searchText.startsWith(">")) {
                filteredApps = LauncherActions.query(searchText.slice(1));
                return;
            }

            const expr = calcExprFor(searchText);
            if (expr !== calcExpr) {
                calcExpr = expr;
                calcResult = "";
                if (expr.length > 0)
                    calcDebounce.restart();
            }

            let apps = searchText.length > 0 ? AppSearch.fuzzyQuery(searchText) : AppSearch.getAllApps();
            if (calcExpr.length > 0 && calcResult.length > 0)
                apps = [calcEntry()].concat(apps);
            filteredApps = apps;
        }

        onFilteredAppsChanged: {
            resultsList.enableScrollAnimation = false;
            resultsList.contentY = 0;
            updateAppsModel();
            Qt.callLater(() => {
                resultsList.enableScrollAnimation = true;
            });
        }

        function updateAppsModel() {
            incrementalLoader.stop();
            
            let newApps = filteredApps;
            appLauncher.pendingApps = newApps;

            appsById = {};
            for (let i = 0; i < newApps.length; i++) {
                appsById[newApps[i].id] = newApps[i];
            }

            appsModel.clear();
            
            let initialBatch = Math.min(appLauncher.batchSize, newApps.length);
            for (let i = 0; i < initialBatch; i++) {
                let app = newApps[i];
                appsModel.append({
                    appId: app.id,
                    appName: app.name,
                    appIcon: app.icon,
                    appComment: app.comment,
                    appExecString: app.execString,
                    appCategories: app.categories,
                    appRunInTerminal: app.runInTerminal
                });
            }
            
            appLauncher.loadedCount = initialBatch;
            
            if (appLauncher.loadedCount < newApps.length) {
                incrementalLoader.start();
            }
        }

        function executeApp(appId) {
            let app = appsById[appId];
            if (!app || !app.execute)
                return;
            if (app.isAction) {
                const run = app.execute;
                Visibilities.setActiveModule("");
                Qt.callLater(run);
            } else {
                app.execute();
                Visibilities.setActiveModule("");
            }
        }

        ListModel {
            id: appsModel
        }

        Component.onCompleted: {
            initialLoadTimer.start();
            
        }

        Connections {
            target: AppSearch
            function onResultsChanged() {
                if (appLauncher.visible) appLauncher.updateFilteredApps();
            }
        }

        Timer {
            id: initialLoadTimer
            interval: 100
            repeat: false
            onTriggered: {
                appLauncher.updateFilteredApps();
                appLauncher.updateAppsModel();
                if (currentTab === 0) {
                    appLauncher.focusSearchInput();
                }
            }
        }

        onSearchTextChanged: {
            if (searchText === Config.prefix.wallpapers + " ") {
                GlobalStates.clearLauncherState();
                GlobalShortcuts.toggleDashboardTab(1);
                return;
            }
            updateFilteredApps();
            let detectedTab = detectPrefix(searchText);
            if (detectedTab !== currentTab) {
                if (detectedTab === 0) {
                    currentTab = 0;
                    prefixDisabled = false;
                    Qt.callLater(() => {
                        appLauncher.focusSearchInput();
                    });
                } else {
                    currentTab = detectedTab;

                    let prefixLength = 0;
                    if (searchText.startsWith(Config.prefix.clipboard + " "))
                        prefixLength = Config.prefix.clipboard.length + 1;
                    else if (searchText.startsWith(Config.prefix.emoji + " "))
                        prefixLength = Config.prefix.emoji.length + 1;
                    else if (searchText.startsWith(Config.prefix.tmux + " "))
                        prefixLength = Config.prefix.tmux.length + 1;
                    else if (searchText.startsWith(Config.prefix.notes + " "))
                        prefixLength = Config.prefix.notes.length + 1;

                    let remainingText = searchText.substring(prefixLength);

                    Qt.callLater(() => {
                        let targetItem = null;
                        let targetLoader = null;

                        if (detectedTab === 1) {
                            targetLoader = clipboardLoader;
                        } else if (detectedTab === 2) {
                            targetLoader = emojiLoader;
                        } else if (detectedTab === 3) {
                            targetLoader = tmuxLoader;
                        } else if (detectedTab === 4) {
                            targetLoader = notesLoader;
                        }

                        if (targetLoader && targetLoader.item) {
                            targetItem = targetLoader.item;
                            if (targetItem.searchText !== undefined) {
                                targetItem.searchText = remainingText;
                            }
                            root.focusSearchInput();
                        }
                    });
                }
            }
        }

        onSelectedIndexChanged: {
            if (selectedIndex === -1 && resultsList.count > 0) {
                resultsList.contentY = 0;
            }

            if (expandedItemIndex >= 0 && selectedIndex !== expandedItemIndex) {
                expandedItemIndex = -1;
                selectedOptionIndex = 0;
                keyboardNavigation = false;
            }
        }

        function clearSearch() {
            GlobalStates.clearLauncherState();
            searchInput.focusInput();
        }

        function focusSearchInput() {
            searchInput.focusInput();
        }

        function adjustScrollForExpandedItem(index) {
            if (index < 0 || index >= appsModel.count)
                return;

            var itemY = 0;
            for (var i = 0; i < index; i++) {
                itemY += 48;  // All items before are collapsed (base height)
            }

            var listHeight = 36 * 3;
            var expandedHeight = 48 + 4 + listHeight + 8;

            var maxContentY = Math.max(0, resultsList.contentHeight - resultsList.height);

            var viewportTop = resultsList.contentY;
            var viewportBottom = viewportTop + resultsList.height;

            var itemBottom = itemY + expandedHeight;

            if (itemY < viewportTop) {
                resultsList.contentY = itemY;
            } else if (itemBottom > viewportBottom) {
                resultsList.contentY = Math.min(itemBottom - resultsList.height, maxContentY);
            }
        }

        Behavior on height {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration
                easing.type: Easing.OutQuart
            }
        }

        Item {
            id: mainLayout
            anchors.fill: parent

            SearchInput {
                id: searchInput
                width: parent.width
                anchors.top: parent.top
                text: GlobalStates.launcherSearchText
                placeholderText: "Search apps  ·  > commands  ·  = math"
                iconText: ""

                onSearchTextChanged: text => {
                    GlobalStates.launcherSearchText = text;
                    appLauncher.searchText = text;

                    resultsList.enableScrollAnimation = false;

                    if (text.length > 0) {
                        GlobalStates.launcherSelectedIndex = 0;
                        appLauncher.selectedIndex = 0;
                        resultsList.currentIndex = 0;

                        resultsList.contentY = 0;
                    } else {
                        GlobalStates.launcherSelectedIndex = -1;
                        appLauncher.selectedIndex = -1;
                        resultsList.currentIndex = -1;

                        resultsList.contentY = 0;
                    }

                    Qt.callLater(() => {
                        resultsList.enableScrollAnimation = true;
                    });
                }

                onAccepted: {
                    if (appLauncher.expandedItemIndex >= 0) {
                        let selectedApp = appsModel.get(appLauncher.expandedItemIndex);
                        if (selectedApp) {
                            let options = [function () {
                                    appLauncher.executeApp(selectedApp.appId);
                                }, function () {
                                    TaskbarApps.togglePin(selectedApp.appId);
                                    appLauncher.expandedItemIndex = -1;
                                }];

                            if (appLauncher.selectedOptionIndex >= 0 && appLauncher.selectedOptionIndex < options.length) {
                                options[appLauncher.selectedOptionIndex]();
                            }
                        }
                    } else {
                        if (appLauncher.selectedIndex >= 0 && appLauncher.selectedIndex < appsModel.count) {
                            let selectedApp = appsModel.get(appLauncher.selectedIndex);
                            if (selectedApp) {
                                appLauncher.executeApp(selectedApp.appId);
                            }
                        }
                    }
                }

                onShiftAccepted: {
                    if (appLauncher.selectedIndex >= 0 && appLauncher.selectedIndex < resultsList.count) {
                        const selected = appsModel.get(appLauncher.selectedIndex);
                        if (selected && (appLauncher.appsById[selected.appId] || {}).isAction)
                            return;
                        if (appLauncher.expandedItemIndex === appLauncher.selectedIndex) {
                            appLauncher.expandedItemIndex = -1;
                            appLauncher.selectedOptionIndex = 0;
                            appLauncher.keyboardNavigation = false;
                        } else {
                            appLauncher.expandedItemIndex = appLauncher.selectedIndex;
                            appLauncher.selectedOptionIndex = 0;
                            appLauncher.keyboardNavigation = true;
                        }
                    }
                }

                onEscapePressed: {
                    if (appLauncher.expandedItemIndex >= 0) {
                        appLauncher.expandedItemIndex = -1;
                        appLauncher.selectedOptionIndex = 0;
                        appLauncher.keyboardNavigation = false;
                    } else {
                        Visibilities.setActiveModule("");
                    }
                }

                onDownPressed: {
                    if (appLauncher.expandedItemIndex >= 0) {
                        if (appLauncher.selectedOptionIndex < 2) {
                            appLauncher.selectedOptionIndex++;
                            appLauncher.keyboardNavigation = true;
                        }
                    } else if (resultsList.count > 0) {
                        if (appLauncher.selectedIndex === -1) {
                            GlobalStates.launcherSelectedIndex = 0;
                            appLauncher.selectedIndex = 0;
                            resultsList.currentIndex = 0;
                        } else if (appLauncher.selectedIndex < resultsList.count - 1) {
                            GlobalStates.launcherSelectedIndex++;
                            appLauncher.selectedIndex++;
                            resultsList.currentIndex = appLauncher.selectedIndex;
                        }
                    }
                }

                onUpPressed: {
                    if (appLauncher.expandedItemIndex >= 0) {
                        if (appLauncher.selectedOptionIndex > 0) {
                            appLauncher.selectedOptionIndex--;
                            appLauncher.keyboardNavigation = true;
                        }
                    } else if (appLauncher.selectedIndex > 0) {
                        GlobalStates.launcherSelectedIndex--;
                        appLauncher.selectedIndex--;
                        resultsList.currentIndex = appLauncher.selectedIndex;
                    } else if (appLauncher.selectedIndex === 0 && appLauncher.searchText.length === 0) {
                        GlobalStates.launcherSelectedIndex = -1;
                        appLauncher.selectedIndex = -1;
                        resultsList.currentIndex = -1;
                    }
                }

                onPageDownPressed: {
                    if (resultsList.count > 0) {
                        let visibleItems = Math.floor(resultsList.height / 48);
                        let newIndex = Math.min(appLauncher.selectedIndex + visibleItems, resultsList.count - 1);
                        if (appLauncher.selectedIndex === -1) {
                            newIndex = Math.min(visibleItems - 1, resultsList.count - 1);
                        }
                        GlobalStates.launcherSelectedIndex = newIndex;
                        appLauncher.selectedIndex = newIndex;
                        resultsList.currentIndex = appLauncher.selectedIndex;
                    }
                }

                onPageUpPressed: {
                    if (resultsList.count > 0) {
                        let visibleItems = Math.floor(resultsList.height / 48);
                        let newIndex = Math.max(appLauncher.selectedIndex - visibleItems, 0);
                        if (appLauncher.selectedIndex === -1) {
                            newIndex = Math.max(resultsList.count - visibleItems, 0);
                        }
                        GlobalStates.launcherSelectedIndex = newIndex;
                        appLauncher.selectedIndex = newIndex;
                        resultsList.currentIndex = appLauncher.selectedIndex;
                    }
                }

                onHomePressed: {
                    if (resultsList.count > 0) {
                        GlobalStates.launcherSelectedIndex = 0;
                        appLauncher.selectedIndex = 0;
                        resultsList.currentIndex = 0;
                    }
                }

                onEndPressed: {
                    if (resultsList.count > 0) {
                        GlobalStates.launcherSelectedIndex = resultsList.count - 1;
                        appLauncher.selectedIndex = resultsList.count - 1;
                        resultsList.currentIndex = appLauncher.selectedIndex;
                    }
                }
            }

            ListView {
                id: resultsList
                width: parent.width
                anchors.top: searchInput.bottom
                anchors.bottom: parent.bottom
                anchors.topMargin: 8
                visible: true

                clip: true
                interactive: appLauncher.expandedItemIndex === -1
                cacheBuffer: 96
                reuseItems: true

                property bool isScrolling: dragging || flicking

                model: appsModel
                currentIndex: appLauncher.selectedIndex

                property bool enableScrollAnimation: true

                Behavior on contentY {
                    enabled: Styling.animDuration > 0 && resultsList.enableScrollAnimation && !resultsList.moving
                    NumberAnimation {
                        duration: Styling.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }

                onCurrentIndexChanged: {
                    if (currentIndex !== appLauncher.selectedIndex) {
                        GlobalStates.launcherSelectedIndex = currentIndex;
                        appLauncher.selectedIndex = currentIndex;
                    }

                    if (currentIndex >= 0) {
                        var itemY = 0;
                        for (var i = 0; i < currentIndex && i < appsModel.count; i++) {
                            var itemHeight = 48;
                            if (i === appLauncher.expandedItemIndex) {
                                var listHeight = 36 * 3;
                                itemHeight = 48 + 4 + listHeight + 8;
                            }
                            itemY += itemHeight;
                        }

                        var currentItemHeight = 48;
                        if (currentIndex === appLauncher.expandedItemIndex) {
                            var listHeight = 36 * 3;
                            currentItemHeight = 48 + 4 + listHeight + 8;
                        }

                        var viewportTop = resultsList.contentY;
                        var viewportBottom = viewportTop + resultsList.height;

                        if (itemY < viewportTop) {
                            resultsList.contentY = itemY;
                        } else if (itemY + currentItemHeight > viewportBottom) {
                            resultsList.contentY = itemY + currentItemHeight - resultsList.height;
                        }
                    }
                }

                delegate: Rectangle {
                    required property string appId
                    required property string appName
                    required property string appIcon
                    required property string appComment
                    required property string appExecString
                    required property var appCategories
                    required property bool appRunInTerminal
                    required property int index

                    property bool isExpanded: index === appLauncher.expandedItemIndex

                    width: resultsList.width
                    height: {
                        let baseHeight = 48;
                        if (isExpanded) {
                            var listHeight = 36 * 3;
                            return baseHeight + 4 + listHeight + 8;
                        }
                        return baseHeight;
                    }
                    color: "transparent"
                    radius: 16

                    Behavior on height {
                        enabled: Styling.animDuration > 0
                        NumberAnimation {
                            duration: Styling.animDuration
                            easing.type: Easing.OutQuart
                        }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: isExpanded ? 48 : parent.height
                        hoverEnabled: !resultsList.isScrolling
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        onEntered: {
                            if (resultsList.isScrolling)
                                return;
                            if (appLauncher.expandedItemIndex === -1) {
                                GlobalStates.launcherSelectedIndex = index;
                                appLauncher.selectedIndex = index;
                                resultsList.currentIndex = index;
                            }
                        }

                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton) {
                                if (!isExpanded) {
                                    appLauncher.executeApp(appId);
                                }
                            } else if (mouse.button === Qt.RightButton) {
                                if ((appLauncher.appsById[appId] || {}).isAction)
                                    return;
                                if (appLauncher.expandedItemIndex === index) {
                                    appLauncher.expandedItemIndex = -1;
                                    appLauncher.selectedOptionIndex = 0;
                                    appLauncher.keyboardNavigation = false;
                                    GlobalStates.launcherSelectedIndex = index;
                                    appLauncher.selectedIndex = index;
                                    resultsList.currentIndex = index;
                                } else {
                                    appLauncher.expandedItemIndex = index;
                                    GlobalStates.launcherSelectedIndex = index;
                                    appLauncher.selectedIndex = index;
                                    resultsList.currentIndex = index;
                                    appLauncher.selectedOptionIndex = 0;
                                    appLauncher.keyboardNavigation = false;
                                }
                            }
                        }
                    }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        height: 32
                        spacing: 12

                        Item {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32

                            readonly property bool isFontIcon: appIcon.startsWith("font:")

                            Image {
                                mipmap: true
                                id: appIconImage
                                anchors.fill: parent
                                visible: !parent.isFontIcon
                                source: parent.isFontIcon ? "" : "image://icon/" + appIcon
                                fillMode: Image.PreserveAspectFit

                                onStatusChanged: {
                                    if (status === Image.Error) {
                                        source = "image://icon/image-missing";
                                    }
                                }
                            }

                            Tinted {
                                anchors.fill: parent
                                visible: !parent.isFontIcon
                                sourceItem: appIconImage
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: parent.isFontIcon
                                text: parent.isFontIcon ? appIcon.slice(5) : ""
                                font.family: Icons.font
                                font.pixelSize: 22
                                color: appLauncher.selectedIndex === index ? Styling.srItem("primary") : Colors.overBackground

                                Behavior on color {
                                    enabled: Styling.animDuration > 0
                                    ColorAnimation {
                                        duration: Styling.animDuration / 2
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                width: parent.width
                                text: appName
                                color: {
                                    if (isExpanded) {
                                        return Styling.srItem("pane");
                                    } else if (appLauncher.selectedIndex === index) {
                                        return Styling.srItem("primary");
                                    } else {
                                        return Colors.overBackground;
                                    }
                                }
                                font.family: Config.theme.font
                                font.pixelSize: Config.theme.fontSize
                                font.weight: Font.Bold
                                elide: Text.ElideRight

                                Behavior on color {
                                    enabled: Styling.animDuration > 0
                                    ColorAnimation {
                                        duration: Styling.animDuration / 2
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                text: appComment || ""
                                color: {
                                    if (isExpanded) {
                                        return Styling.srItem("pane");
                                    } else if (appLauncher.selectedIndex === index) {
                                        return Styling.srItem("primary");
                                    } else {
                                        return Colors.outline;
                                    }
                                }
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                elide: Text.ElideRight
                                visible: (Config.launcher.showAppComments ?? true) && text !== ""

                                Behavior on color {
                                    enabled: Styling.animDuration > 0
                                    ColorAnimation {
                                        duration: Styling.animDuration / 2
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.bottomMargin: 8
                        spacing: 4
                        visible: isExpanded
                        opacity: isExpanded ? 1 : 0

                        Behavior on opacity {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Styling.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }

                        ClippingRectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36 * 3
                            color: Colors.background
                            radius: Styling.radius(0)

                            ListView {
                                id: optionsListView
                                anchors.fill: parent
                                clip: true
                                interactive: false
                                boundsBehavior: Flickable.StopAtBounds
                                model: [
                                    {
                                        text: "Launch",
                                        icon: Icons.launch,
                                        highlightColor: Styling.srItem("overprimary"),
                                        textColor: Styling.srItem("primary"),
                                        action: function () {
                                            appLauncher.executeApp(appId);
                                        }
                                    },
                                    {
                                        text: TaskbarApps.isPinned(appId) ? "Unpin from Dock" : "Pin to Dock",
                                        icon: TaskbarApps.isPinned(appId) ? Icons.unpin : Icons.pin,
                                        highlightColor: TaskbarApps.isPinned(appId) ? Colors.error : Colors.tertiary,
                                        textColor: TaskbarApps.isPinned(appId) ? Styling.srItem("error") : Styling.srItem("tertiary"),
                                        action: function () {
                                            TaskbarApps.togglePin(appId);
                                            appLauncher.expandedItemIndex = -1;
                                        }
                                    }
                                ]
                                currentIndex: appLauncher.selectedOptionIndex
                                highlightFollowsCurrentItem: true
                                highlightRangeMode: ListView.ApplyRange
                                preferredHighlightBegin: 0
                                preferredHighlightEnd: height

                                highlight: StyledRect {
                                    variant: {
                                        if (optionsListView.currentIndex >= 0 && optionsListView.currentIndex < optionsListView.count) {
                                            var item = optionsListView.model[optionsListView.currentIndex];
                                            if (item && item.highlightColor) {
                                                if (item.highlightColor === Colors.secondary)
                                                    return "secondary";
                                                if (item.highlightColor === Colors.tertiary)
                                                    return "tertiary";
                                                if (item.highlightColor === Colors.error)
                                                    return "error";
                                                return "primary";
                                            }
                                        }
                                        return "primary";
                                    }
                                    radius: Styling.radius(0)
                                    visible: optionsListView.currentIndex >= 0
                                    z: -1
                                }

                                highlightMoveDuration: Styling.animDuration > 0 ? Styling.animDuration / 2 : 0
                                highlightMoveVelocity: -1
                                highlightResizeDuration: Styling.animDuration / 2
                                highlightResizeVelocity: -1

                                delegate: Item {
                                    required property var modelData
                                    required property int index

                                    width: optionsListView.width
                                    height: 36

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 8

                                            Text {
                                                text: modelData && modelData.icon ? modelData.icon : ""
                                                font.family: Icons.font
                                                font.pixelSize: 14
                                                font.weight: Font.Bold
                                                textFormat: Text.RichText
                                                color: {
                                                    if (optionsListView.currentIndex === index && modelData && modelData.textColor) {
                                                        return modelData.textColor;
                                                    }
                                                    return Colors.overSurface;
                                                }

                                                Behavior on color {
                                                    enabled: Styling.animDuration > 0
                                                    ColorAnimation {
                                                        duration: Styling.animDuration / 2
                                                        easing.type: Easing.OutQuart
                                                    }
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData && modelData.text ? modelData.text : ""
                                                font.family: Config.theme.font
                                                font.pixelSize: Config.theme.fontSize
                                                font.weight: optionsListView.currentIndex === index ? Font.Bold : Font.Normal
                                                color: {
                                                    if (optionsListView.currentIndex === index && modelData && modelData.textColor) {
                                                        return modelData.textColor;
                                                    }
                                                    return Colors.overSurface;
                                                }
                                                elide: Text.ElideRight
                                                maximumLineCount: 1

                                                Behavior on color {
                                                    enabled: Styling.animDuration > 0
                                                    ColorAnimation {
                                                        duration: Styling.animDuration / 2
                                                        easing.type: Easing.OutQuart
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor

                                            onEntered: {
                                                optionsListView.currentIndex = index;
                                                appLauncher.selectedOptionIndex = index;
                                                appLauncher.keyboardNavigation = false;
                                            }

                                            onClicked: {
                                                if (modelData && modelData.action) {
                                                    modelData.action();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                highlight: Item {
                    width: resultsList.width
                    height: {
                        let baseHeight = 48;
                        if (resultsList.currentIndex === appLauncher.expandedItemIndex) {
                            var listHeight = 36 * 3;
                            return baseHeight + 4 + listHeight + 8;
                        }
                        return baseHeight;
                    }

                    y: {
                        var yPos = 0;
                        for (var i = 0; i < resultsList.currentIndex && i < appsModel.count; i++) {
                            var itemHeight = 48;
                            if (i === appLauncher.expandedItemIndex) {
                                var listHeight = 36 * 3;
                                itemHeight = 48 + 4 + listHeight + 8;
                            }
                            yPos += itemHeight;
                        }
                        return yPos;
                    }

                    Behavior on y {
                        enabled: Styling.animDuration > 0
                        NumberAnimation {
                            duration: Styling.animDuration / 2
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on height {
                        enabled: Styling.animDuration > 0
                        NumberAnimation {
                            duration: Styling.animDuration
                            easing.type: Easing.OutQuart
                        }
                    }

                    onHeightChanged: {
                        if (appLauncher.expandedItemIndex >= 0 && height > 48) {
                            Qt.callLater(() => {
                                appLauncher.adjustScrollForExpandedItem(appLauncher.expandedItemIndex);
                            });
                        }
                    }

                    StyledRect {
                        anchors.fill: parent
                        variant: {
                            if (appLauncher.expandedItemIndex >= 0 && appLauncher.selectedIndex === appLauncher.expandedItemIndex) {
                                return "pane";
                            } else {
                                return "primary";
                            }
                        }
                        radius: Styling.radius(4)
                        visible: appLauncher.selectedIndex >= 0
                    }
                }

                highlightFollowsCurrentItem: false
            }
        }
    }

    StackLayout {
        id: internalStack
        anchors.fill: parent
        visible: currentTab !== 0
        currentIndex: currentTab - 1

        Loader {
            id: clipboardLoader
            active: currentTab === 1 || item !== null
            sourceComponent: Component {
                ClipboardTab {
                    leftPanelWidth: root.leftPanelWidth
                    prefixIcon: Icons.clipboard
                    onBackspaceOnEmpty: {
                        prefixDisabled = true;
                        currentTab = 0;
                        GlobalStates.launcherSearchText = Config.prefix.clipboard + " ";
                        root.focusSearchInput();
                    }
                    onRequestOpenItem: (itemId, items, currentContent, filePathGetter, urlChecker) => {
                        openItemInternal(itemId, items, currentContent, filePathGetter, urlChecker);
                    }
                }
            }
            onLoaded: {
                if (currentTab === 1 && item && item.focusSearchInput) {
                    root.focusSearchInput();
                }
            }
        }

        Loader {
            id: emojiLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            active: currentTab === 2 || item !== null
            sourceComponent: Component {
                EmojiTab {
                    anchors.fill: parent
                    leftPanelWidth: root.width
                    prefixIcon: Icons.emoji
                    onBackspaceOnEmpty: {
                        prefixDisabled = true;
                        currentTab = 0;
                        GlobalStates.launcherSearchText = Config.prefix.emoji + " ";
                        root.focusSearchInput();
                    }
                }
            }
            onLoaded: {
                if (currentTab === 2 && item && item.focusSearchInput) {
                    root.focusSearchInput();
                }
            }
        }

        Loader {
            id: tmuxLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            active: currentTab === 3 || item !== null
            sourceComponent: Component {
                TmuxTab {
                    leftPanelWidth: root.leftPanelWidth
                    prefixIcon: Icons.terminal
                    onBackspaceOnEmpty: {
                        prefixDisabled = true;
                        currentTab = 0;
                        GlobalStates.launcherSearchText = Config.prefix.tmux + " ";
                        root.focusSearchInput();
                    }
                }
            }
            onLoaded: {
                if (currentTab === 3 && item && item.focusSearchInput) {
                    root.focusSearchInput();
                }
            }
        }

        Loader {
            id: notesLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            active: currentTab === 4 || item !== null
            sourceComponent: Component {
                NotesTab {
                    anchors.fill: parent
                    leftPanelWidth: root.leftPanelWidth
                    prefixIcon: Icons.note
                    onBackspaceOnEmpty: {
                        prefixDisabled = true;
                        currentTab = 0;
                        GlobalStates.launcherSearchText = Config.prefix.notes + " ";
                        root.focusSearchInput();
                    }
                }
            }
            onLoaded: {
                if (currentTab === 4 && item && item.focusSearchInput) {
                    root.focusSearchInput();
                }
            }
        }
    }

    function openItemInternal(itemId, items, currentContent, getFilePathFromUri, isUrl) {
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === itemId) {
                var item = items[i];
                var content = currentContent || item.preview;

                if (item.isFile) {
                    var filePath = getFilePathFromUri(content);
                    if (filePath) {
                        ApplicationLauncher.launchCommand(["xdg-open", filePath]);
                    }
                } else if (item.isImage && item.binaryPath) {
                    ApplicationLauncher.launchCommand(["xdg-open", item.binaryPath]);
                } else if (isUrl(content)) {
                    ApplicationLauncher.launchCommand(["xdg-open", content.trim()]);
                }
                break;
            }
        }
    }
}
