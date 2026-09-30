import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.config

Item {
    id: root
    focus: true

    property string prefixIcon: ""
    signal backspaceOnEmpty

    property int leftPanelWidth: 0

    ListDetailController {
        id: detail
        refresh: root.updateFilteredSessions
        focusSearch: root.focusSearchInput
        setResultsCurrentIndex: value => {
            resultsList.currentIndex = value;
        }
        prepareRename: id => id
    }

    property alias selectedIndex: detail.selectedIndex

    property string searchText: ""
    property bool showResults: searchText.length > 0
    property var tmuxSessions: []
    property var filteredSessions: []

    ListModel {
        id: sessionsModel
    }

    property alias deleteMode: detail.deleteMode
    property alias sessionToDelete: detail.pendingDeleteId
    property alias originalSelectedIndex: detail.originalSelectedIndex
    property alias deleteButtonIndex: detail.deleteButtonIndex

    property alias renameMode: detail.renameMode
    property alias sessionToRename: detail.pendingRenameId
    property alias newSessionName: detail.pendingRenameName
    property alias renameSelectedIndex: detail.renameSelectedIndex
    property alias renameButtonIndex: detail.renameButtonIndex
    property alias pendingRenamedSession: detail.pendingRenamedId

    property int expandedItemIndex: -1
    property int selectedOptionIndex: 0
    property bool keyboardNavigation: false

    TmuxSessionInfo { id: sessionInfo }
    readonly property var sessionWindows: sessionInfo.windows
    readonly property var sessionPanes: sessionInfo.panes
    readonly property bool loadingSessionInfo: sessionInfo.loading


    onVisibleChanged: {
        if (visible) {
            refreshTmuxSessions();
        }
    }


    onSelectedIndexChanged: {
        if (selectedIndex === -1 && resultsList.count > 0) {
            resultsList.positionViewAtIndex(0, ListView.Beginning);
        }

        if (expandedItemIndex >= 0 && selectedIndex !== expandedItemIndex) {
            expandedItemIndex = -1;
            selectedOptionIndex = 0;
            keyboardNavigation = false;
        }

        if (selectedIndex >= 0 && selectedIndex < filteredSessions.length) {
            let session = filteredSessions[selectedIndex];
            if (session && !session.isCreateButton && !session.isCreateSpecificButton) {
                loadSessionInfo(session.name);
            } else {
                loadSessionInfo("");
            }
        } else {
            loadSessionInfo("");
        }
    }

    onSearchTextChanged: {
        updateFilteredSessions();
    }

    function clearSearch() {
        searchText = "";
        selectedIndex = -1;
        searchInput.focusInput();
        updateFilteredSessions();
    }

    function focusSearchInput() {
        searchInput.focusInput();
    }

    function cancelDeleteModeFromExternal() {
        detail.cancelModes();
    }

    function updateFilteredSessions() {
        var newFilteredSessions = [];

        var createButtonText = "Create new session";
        var isCreateSpecific = false;
        var sessionNameToCreate = "";

        if (searchText.length === 0) {
            newFilteredSessions = tmuxSessions.slice();
        } else {
            newFilteredSessions = tmuxSessions.filter(function (session) {
                return session.name.toLowerCase().includes(searchText.toLowerCase());
            });

            let exactMatch = tmuxSessions.find(function (session) {
                return session.name.toLowerCase() === searchText.toLowerCase();
            });

            if (!exactMatch && searchText.length > 0) {
                createButtonText = `Create session "${searchText}"`;
                isCreateSpecific = true;
                sessionNameToCreate = searchText;
            }
        }

        if (!deleteMode && !renameMode) {
            newFilteredSessions.unshift({
                name: createButtonText,
                isCreateButton: !isCreateSpecific,
                isCreateSpecificButton: isCreateSpecific,
                sessionNameToCreate: sessionNameToCreate,
                icon: "terminal"
            });
        }

        filteredSessions = newFilteredSessions;
        resultsList.enableScrollAnimation = false;
        resultsList.contentY = 0;

        sessionsModel.clear();
        for (var i = 0; i < newFilteredSessions.length; i++) {
            var session = newFilteredSessions[i];
            var sessionId = (session.isCreateButton || session.isCreateSpecificButton) ? "__create__" : session.name;

            sessionsModel.append({
                sessionId: sessionId,
                sessionData: session
            });
        }

        Qt.callLater(() => {
            resultsList.enableScrollAnimation = true;
        });

        if (!deleteMode && !renameMode) {
            if (searchText.length > 0 && newFilteredSessions.length > 0) {
                selectedIndex = 0;
                resultsList.currentIndex = 0;
            } else if (searchText.length === 0) {
                selectedIndex = -1;
                resultsList.currentIndex = -1;
            }
        }

        if (pendingRenamedSession !== "") {
            for (let i = 0; i < newFilteredSessions.length; i++) {
                if (newFilteredSessions[i].name === pendingRenamedSession) {
                    selectedIndex = i;
                    resultsList.currentIndex = i;
                    pendingRenamedSession = "";
                    break;
                }
            }
            if (pendingRenamedSession !== "") {
                pendingRenamedSession = "";
            }
        }
    }

    function enterDeleteMode(sessionName) {
        detail.enterDeleteMode(sessionName);
        root.forceActiveFocus();
    }

    function cancelDeleteMode() {
        detail.cancelDeleteMode();
    }

    function confirmDeleteSession() {
        killProcess.command = ["tmux", "kill-session", "-t", sessionToDelete];
        killProcess.running = true;
        cancelDeleteMode();
    }

    function enterRenameMode(sessionName) {
        detail.enterRenameMode(sessionName);
        root.forceActiveFocus();
    }

    function cancelRenameMode() {
        detail.cancelRenameMode();
    }

    function confirmRenameSession() {
        if (newSessionName.trim() !== "" && newSessionName !== sessionToRename) {
            renameProcess.command = ["tmux", "rename-session", "-t", sessionToRename, newSessionName.trim()];
            renameProcess.running = true;
        } else {
            cancelRenameMode();
        }
    }

    function refreshTmuxSessions() {
        tmuxProcess.running = true;
    }

    function loadSessionInfo(sessionName) {
        if (sessionInfo.sessionName !== sessionName)
            sessionInfo.sessionName = sessionName;
        else
            sessionInfo.refresh();
    }

    function createTmuxSession(sessionName) {
        const command = ["xdg-terminal-exec", "tmux"];
        if (sessionName) command.push("new", "-s", sessionName);
        ApplicationLauncher.launchCommand(command);
        Visibilities.setActiveModule("");
    }

    function attachToSession(sessionName) {
        ApplicationLauncher.launchCommand(["xdg-terminal-exec", "tmux", "attach-session", "-t", sessionName]);
        Visibilities.setActiveModule("");
    }

    function switchToWindow(sessionName, windowIndex) {
        if (!sessionName || windowIndex === undefined)
            return;
        switchWindowProcess.command = ["tmux", "select-window", "-t", `${sessionName}:${windowIndex}`];
        switchWindowProcess.running = true;
    }

    function focusPane(sessionName, paneIndex) {
        if (!sessionName || paneIndex === undefined)
            return;
        focusPaneProcess.command = ["tmux", "select-pane", "-t", `${sessionName}:.${paneIndex}`];
        focusPaneProcess.running = true;
    }

    implicitWidth: 400
    implicitHeight: 392

    MouseArea {
        anchors.fill: parent
        enabled: root.deleteMode || root.renameMode
        z: -10

        onClicked: {
            if (root.deleteMode) {
                root.cancelDeleteMode();
            } else if (root.renameMode) {
                root.cancelRenameMode();
            }
        }
    }

    Behavior on height {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration
            easing.type: Easing.OutQuart
        }
    }

    Process {
        id: tmuxProcess
        command: ["tmux", "list-sessions", "-F", "#{session_name}"]
        running: false

        stdout: StdioCollector {
            id: tmuxCollector
            waitForEnd: true

            onStreamFinished: {
                let sessions = [];
                let lines = text.trim().split('\n');
                for (let line of lines) {
                    if (line.trim().length > 0) {
                        sessions.push({
                            name: line.trim(),
                            isCreateButton: false,
                            icon: "terminal"
                        });
                    }
                }
                root.tmuxSessions = sessions;
                root.updateFilteredSessions();
            }
        }

        onExited: function (exitCode) {
            if (exitCode !== 0) {
                root.tmuxSessions = [];
                root.updateFilteredSessions();
            }
        }
    }

    Process {
        id: killProcess
        running: false

        onExited: function (code) {
            if (code === 0) {
                root.refreshTmuxSessions();
            }
        }
    }

    Process {
        id: renameProcess
        running: false

        onExited: function (code) {
            if (code === 0) {
                root.pendingRenamedSession = root.newSessionName;
                root.refreshTmuxSessions();
            }
            root.cancelRenameMode();
        }
    }

    Process {
        id: switchWindowProcess
        running: false

        onExited: function (code) {
            if (code === 0) {
                let currentSession = root.selectedIndex >= 0 && root.selectedIndex < root.filteredSessions.length ? root.filteredSessions[root.selectedIndex] : null;
                if (currentSession && !currentSession.isCreateButton && !currentSession.isCreateSpecificButton) {
                    root.loadSessionInfo(currentSession.name);
                }
            }
        }
    }

    Process {
        id: focusPaneProcess
        running: false

        onExited: function (code) {
            if (code === 0) {
                let currentSession = root.selectedIndex >= 0 && root.selectedIndex < root.filteredSessions.length ? root.filteredSessions[root.selectedIndex] : null;
                if (currentSession && !currentSession.isCreateButton && !currentSession.isCreateSpecificButton) {
                    root.loadSessionInfo(currentSession.name);
                }
            }
        }
    }

    RowLayout {
        id: mainLayout
        anchors.fill: parent
        spacing: 8

        Item {
            Layout.preferredWidth: root.leftPanelWidth
            Layout.fillHeight: true

            SearchInput {
                id: searchInput
                width: parent.width
                height: 48
                anchors.top: parent.top
                text: root.searchText
                placeholderText: "Search or create tmux session..."
                iconText: ""
                prefixIcon: root.prefixIcon

                onSearchTextChanged: text => {
                    root.searchText = text;
                }

                onBackspaceOnEmpty: {
                    root.backspaceOnEmpty();
                }

                onAccepted: {
                    if (root.deleteMode) {
                        root.cancelDeleteMode();
                    } else if (root.expandedItemIndex >= 0) {
                        let session = root.filteredSessions[root.expandedItemIndex];
                        if (session && !session.isCreateButton && !session.isCreateSpecificButton) {
                            let options = [function () {
                                    root.attachToSession(session.name);
                                }, function () {
                                    root.enterRenameMode(session.name);
                                    root.expandedItemIndex = -1;
                                }, function () {
                                    root.enterDeleteMode(session.name);
                                    root.expandedItemIndex = -1;
                                }];

                            if (root.selectedOptionIndex >= 0 && root.selectedOptionIndex < options.length) {
                                options[root.selectedOptionIndex]();
                            }
                        }
                    } else {
                        if (root.selectedIndex >= 0 && root.selectedIndex < resultsList.count) {
                            let selectedSession = root.filteredSessions[root.selectedIndex];
                            if (selectedSession) {
                                if (selectedSession.isCreateSpecificButton) {
                                    root.createTmuxSession(selectedSession.sessionNameToCreate);
                                } else if (selectedSession.isCreateButton) {
                                    root.createTmuxSession();
                                } else {
                                    root.attachToSession(selectedSession.name);
                                }
                            }
                        } else {
                        }
                    }
                }

                onShiftAccepted: {
                    if (!root.deleteMode && !root.renameMode) {
                        if (root.selectedIndex >= 0 && root.selectedIndex < resultsList.count) {
                            let selectedSession = root.filteredSessions[root.selectedIndex];
                            if (selectedSession && !selectedSession.isCreateButton && !selectedSession.isCreateSpecificButton) {
                                if (root.expandedItemIndex === root.selectedIndex) {
                                    root.expandedItemIndex = -1;
                                    root.selectedOptionIndex = 0;
                                    root.keyboardNavigation = false;
                                } else {
                                    root.expandedItemIndex = root.selectedIndex;
                                    root.selectedOptionIndex = 0;
                                    root.keyboardNavigation = true;
                                }
                            }
                        }
                    }
                }

                onCtrlRPressed: {
                    if (!root.deleteMode && !root.renameMode && root.selectedIndex >= 0 && root.selectedIndex < resultsList.count) {
                        let selectedSession = root.filteredSessions[root.selectedIndex];
                        if (selectedSession && !selectedSession.isCreateButton && !selectedSession.isCreateSpecificButton) {
                            root.enterRenameMode(selectedSession.name);
                        }
                    }
                }

                onEscapePressed: {
                    if (root.expandedItemIndex >= 0) {
                        root.expandedItemIndex = -1;
                        root.selectedOptionIndex = 0;
                        root.keyboardNavigation = false;
                    } else if (!root.deleteMode && !root.renameMode) {
                        Visibilities.setActiveModule("");
                    }
                }

                onDownPressed: {
                    if (root.expandedItemIndex >= 0) {
                        if (root.selectedOptionIndex < 2) {
                            root.selectedOptionIndex++;
                            root.keyboardNavigation = true;
                        }
                    } else if (!root.deleteMode && !root.renameMode && resultsList.count > 0) {
                        if (root.selectedIndex === -1) {
                            root.selectedIndex = 0;
                            resultsList.currentIndex = 0;
                        } else if (root.selectedIndex < resultsList.count - 1) {
                            root.selectedIndex++;
                            resultsList.currentIndex = root.selectedIndex;
                        }
                    }
                }

                onUpPressed: {
                    if (root.expandedItemIndex >= 0) {
                        if (root.selectedOptionIndex > 0) {
                            root.selectedOptionIndex--;
                            root.keyboardNavigation = true;
                        }
                    } else if (!root.deleteMode && !root.renameMode) {
                        if (root.selectedIndex > 0) {
                            root.selectedIndex--;
                            resultsList.currentIndex = root.selectedIndex;
                        } else if (root.selectedIndex === 0 && root.searchText.length === 0) {
                            root.selectedIndex = -1;
                            resultsList.currentIndex = -1;
                        }
                    }
                }

                onPageDownPressed: {
                    if (!root.deleteMode && !root.renameMode && resultsList.count > 0) {
                        let visibleItems = Math.floor(resultsList.height / 28);
                        let newIndex = Math.min(root.selectedIndex + visibleItems, resultsList.count - 1);
                        if (root.selectedIndex === -1) {
                            newIndex = Math.min(visibleItems - 1, resultsList.count - 1);
                        }
                        root.selectedIndex = newIndex;
                        resultsList.currentIndex = root.selectedIndex;
                    }
                }

                onPageUpPressed: {
                    if (!root.deleteMode && !root.renameMode && resultsList.count > 0) {
                        let visibleItems = Math.floor(resultsList.height / 28);
                        let newIndex = Math.max(root.selectedIndex - visibleItems, 0);
                        if (root.selectedIndex === -1) {
                            newIndex = Math.max(resultsList.count - visibleItems, 0);
                        }
                        root.selectedIndex = newIndex;
                        resultsList.currentIndex = root.selectedIndex;
                    }
                }

                onHomePressed: {
                    if (!root.deleteMode && !root.renameMode && resultsList.count > 0) {
                        root.selectedIndex = 0;
                        resultsList.currentIndex = 0;
                    }
                }

                onEndPressed: {
                    if (!root.deleteMode && !root.renameMode && resultsList.count > 0) {
                        root.selectedIndex = resultsList.count - 1;
                        resultsList.currentIndex = root.selectedIndex;
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
                interactive: !root.deleteMode && !root.renameMode && root.expandedItemIndex === -1
                cacheBuffer: 96
                reuseItems: false

                property bool isScrolling: dragging || flicking

                model: sessionsModel
                currentIndex: root.selectedIndex

                property bool enableScrollAnimation: true

                Behavior on contentY {
                    enabled: Styling.animDuration > 0 && resultsList.enableScrollAnimation && !resultsList.moving
                    NumberAnimation {
                        duration: Styling.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }

                onCurrentIndexChanged: {
                    if (currentIndex !== root.selectedIndex) {
                        root.selectedIndex = currentIndex;
                    }

                    if (currentIndex >= 0) {
                        var itemY = 0;
                        for (var i = 0; i < currentIndex && i < sessionsModel.count; i++) {
                            var itemHeight = 48;
                            if (i === root.expandedItemIndex && !root.deleteMode && !root.renameMode) {
                                var listHeight = 36 * 3;
                                itemHeight = 48 + 4 + listHeight + 8;
                            }
                            itemY += itemHeight;
                        }

                        var currentItemHeight = 48;
                        if (currentIndex === root.expandedItemIndex && !root.deleteMode && !root.renameMode) {
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
                    required property string sessionId
                    required property var sessionData
                    required property int index

                    property var modelData: sessionData

                    width: resultsList.width
                    height: {
                        let baseHeight = 48;
                        if (index === root.expandedItemIndex && !isInDeleteMode && !isInRenameMode) {
                            var listHeight = 36 * 3;
                            return baseHeight + 4 + listHeight + 8;
                        }
                        return baseHeight;
                    }
                    color: "transparent"
                    radius: 16

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
                    clip: true

                    property bool isInDeleteMode: root.deleteMode && modelData.name === root.sessionToDelete
                    property bool isInRenameMode: root.renameMode && modelData.name === root.sessionToRename
                    property bool isExpanded: index === root.expandedItemIndex
                    property color textColor: {
                        if (isInDeleteMode) {
                            return Styling.srItem("error");
                        } else if (isInRenameMode) {
                            return Styling.srItem("secondary");
                        } else if (isExpanded) {
                            return Styling.srItem("pane");
                        } else if (root.selectedIndex === index) {
                            return Styling.srItem("primary");
                        } else {
                            return Colors.overSurface;
                        }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: isExpanded ? 48 : parent.height
                        hoverEnabled: !resultsList.isScrolling
                        enabled: !isInDeleteMode && !isInRenameMode
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        property real startX: 0
                        property real startY: 0
                        property bool isDragging: false
                        property bool longPressTriggered: false

                        onEntered: {
                            if (resultsList.isScrolling)
                                return;
                            if (!root.deleteMode && !root.renameMode && root.expandedItemIndex === -1) {
                                root.selectedIndex = index;
                                resultsList.currentIndex = index;
                            }
                        }

                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton) {
                                if (root.deleteMode && modelData.name !== root.sessionToDelete) {
                                    root.cancelDeleteMode();
                                    return;
                                } else if (root.renameMode && modelData.name !== root.sessionToRename) {
                                    root.cancelRenameMode();
                                    return;
                                }

                                if (!root.deleteMode && !root.renameMode && !isExpanded) {
                                    if (modelData.isCreateSpecificButton) {
                                        root.createTmuxSession(modelData.sessionNameToCreate);
                                    } else if (modelData.isCreateButton) {
                                        root.createTmuxSession();
                                    } else {
                                        root.attachToSession(modelData.name);
                                    }
                                }
                            } else if (mouse.button === Qt.RightButton) {
                                if (root.deleteMode) {
                                    root.cancelDeleteMode();
                                    return;
                                } else if (root.renameMode) {
                                    root.cancelRenameMode();
                                    return;
                                }

                                if (!modelData.isCreateButton && !modelData.isCreateSpecificButton) {
                                    if (root.expandedItemIndex === index) {
                                        root.expandedItemIndex = -1;
                                        root.selectedOptionIndex = 0;
                                        root.keyboardNavigation = false;
                                        root.selectedIndex = index;
                                        resultsList.currentIndex = index;
                                    } else {
                                        root.expandedItemIndex = index;
                                        root.selectedIndex = index;
                                        resultsList.currentIndex = index;
                                        root.selectedOptionIndex = 0;
                                        root.keyboardNavigation = false;
                                    }
                                }
                            }
                        }

                        onPressed: mouse => {
                            startX = mouse.x;
                            startY = mouse.y;
                            isDragging = false;
                            longPressTriggered = false;

                            if (mouse.button !== Qt.RightButton) {
                                longPressTimer.start();
                            }
                        }

                        onPositionChanged: mouse => {
                            if (pressed && mouse.button !== Qt.RightButton) {
                                let deltaX = mouse.x - startX;
                                let deltaY = mouse.y - startY;
                                let distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);

                                if (distance > 10) {
                                    isDragging = true;
                                    longPressTimer.stop();

                                    if (deltaX < -50 && Math.abs(deltaY) < 30 && !modelData.isCreateButton && !modelData.isCreateSpecificButton) {
                                        if (!longPressTriggered) {
                                            root.enterDeleteMode(modelData.name);
                                            longPressTriggered = true;
                                        }
                                    }
                                }
                            }
                        }

                        onReleased: mouse => {
                            longPressTimer.stop();
                            isDragging = false;
                            longPressTriggered = false;
                        }

                        Timer {
                            id: longPressTimer
                            interval: 800
                            repeat: false
                            onTriggered: {
                                if (!mouseArea.isDragging && !modelData.isCreateButton && !modelData.isCreateSpecificButton) {
                                    root.enterRenameMode(modelData.name);
                                    mouseArea.longPressTriggered = true;
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
                        visible: isExpanded && !isInDeleteMode && !isInRenameMode
                        opacity: (isExpanded && !isInDeleteMode && !isInRenameMode) ? 1 : 0

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

                            Behavior on Layout.preferredHeight {
                                enabled: Styling.animDuration > 0
                                NumberAnimation {
                                    duration: Styling.animDuration
                                    easing.type: Easing.OutQuart
                                }
                            }

                            OptionsListView {
                                id: optionsListView
                                anchors.fill: parent
                                interactive: false
                                selectedIndex: root.selectedOptionIndex
                                onIndexHovered: index => {
                                    root.selectedOptionIndex = index;
                                    root.keyboardNavigation = false;
                                }
                                model: [
                                    {
                                        text: "Open",
                                        icon: Icons.popOpen,
                                        highlightColor: Styling.srItem("overprimary"),
                                        textColor: Styling.srItem("primary"),
                                        action: function () {
                                            root.attachToSession(modelData.name);
                                        }
                                    },
                                    {
                                        text: "Rename",
                                        icon: Icons.edit,
                                        highlightColor: Colors.secondary,
                                        textColor: Styling.srItem("secondary"),
                                        action: function () {
                                            root.enterRenameMode(modelData.name);
                                            root.expandedItemIndex = -1;
                                        }
                                    },
                                    {
                                        text: "Quit",
                                        icon: Icons.alert,
                                        highlightColor: Colors.error,
                                        textColor: Styling.srItem("error"),
                                        action: function () {
                                            root.enterDeleteMode(modelData.name);
                                            root.expandedItemIndex = -1;
                                        }
                                    }
                                ]
                            }
                        }
                    }

                    ActionBar {
                        tone: "secondary"
                        active: isInRenameMode
                        buttonIndex: root.renameButtonIndex
                        alignTop: true
                        onButtonIndexRequested: index => root.renameButtonIndex = index
                        onCancelRequested: root.cancelRenameMode()
                        onConfirmRequested: root.confirmRenameSession()
                    }

                    RowLayout {
                        id: mainContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        anchors.rightMargin: isInRenameMode ? 84 : 8
                        height: 32
                        spacing: 8

                        Behavior on anchors.rightMargin {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Styling.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }

                        StyledRect {
                            id: iconBackground
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            variant: {
                                if (isInDeleteMode) {
                                    return "overerror";
                                } else if (isInRenameMode) {
                                    return "oversecondary";
                                } else if (root.selectedIndex === index) {
                                    return "overprimary";
                                } else if (modelData.isCreateButton) {
                                    return "primary";
                                } else {
                                    return "common";
                                }
                            }
                            radius: Styling.radius(-4)

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    if (isInDeleteMode) {
                                        return Icons.alert;
                                    } else if (isInRenameMode) {
                                        return Icons.edit;
                                    } else if (modelData.isCreateButton || modelData.isCreateSpecificButton) {
                                        return Icons.plus;
                                    } else {
                                        return Icons.terminalWindow;
                                    }
                                }
                                color: iconBackground.item
                                font.family: Icons.font
                                font.pixelSize: 16
                                textFormat: Text.RichText
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Loader {
                                Layout.fillWidth: true
                                sourceComponent: {
                                    if (root.renameMode && modelData.name === root.sessionToRename) {
                                        return renameTextInput;
                                    } else {
                                        return normalText;
                                    }
                                }
                            }

                            Component {
                                id: normalText
                                Text {
                                    text: {
                                        if (isInDeleteMode && !modelData.isCreateButton && !modelData.isCreateSpecificButton) {
                                            return `Quit "${root.sessionToDelete}"?`;
                                        } else {
                                            return modelData.name;
                                        }
                                    }
                                    color: textColor
                                    font.family: Config.theme.font
                                    font.pixelSize: Config.theme.fontSize
                                    font.weight: isInDeleteMode ? Font.Bold : (modelData.isCreateButton ? Font.Medium : Font.Bold)
                                    elide: Text.ElideRight
                                }
                            }

                            Component {
                                id: renameTextInput
                                TextField {
                                    text: root.newSessionName
                                    color: Colors.overSecondary
                                    selectionColor: Colors.overSecondary
                                    selectedTextColor: Colors.secondary
                                    font.family: Config.theme.font
                                    font.pixelSize: Config.theme.fontSize
                                    font.weight: Font.Bold
                                    background: Rectangle {
                                        color: "transparent"
                                        border.width: 0
                                    }
                                    selectByMouse: true

                                    onTextChanged: {
                                        root.newSessionName = text;
                                    }

                                    Component.onCompleted: {
                                        Qt.callLater(() => {
                                            forceActiveFocus();
                                            selectAll();
                                        });
                                    }

                                    Keys.onPressed: event => {
                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            root.confirmRenameSession();
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Escape) {
                                            root.cancelRenameMode();
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Left) {
                                            root.renameButtonIndex = 0;
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Right) {
                                            root.renameButtonIndex = 1;
                                            event.accepted = true;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ActionBar {
                        active: isInDeleteMode
                        buttonIndex: root.deleteButtonIndex
                        alignTop: true
                        onButtonIndexRequested: index => root.deleteButtonIndex = index
                        onCancelRequested: root.cancelDeleteMode()
                        onConfirmRequested: root.confirmDeleteSession()
                    }
                }

                highlight: ResultsHighlight {
                    view: resultsList
                    expandedIndex: root.expandedItemIndex
                    variant: root.deleteMode ? "error" : root.renameMode ? "secondary"
                        : root.expandedItemIndex >= 0 && root.selectedIndex === root.expandedItemIndex ? "pane" : "primary"
                }

                highlightFollowsCurrentItem: false

                MouseArea {
                    anchors.fill: parent
                    enabled: root.deleteMode || root.renameMode || root.expandedItemIndex >= 0
                    z: 1000
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    function isClickInsideActiveItem(mouseY) {
                        var activeIndex = -1;
                        var isExpanded = false;

                        if (root.deleteMode || root.renameMode) {
                            activeIndex = root.selectedIndex;
                        } else if (root.expandedItemIndex >= 0) {
                            activeIndex = root.expandedItemIndex;
                            isExpanded = true;
                        }

                        if (activeIndex < 0)
                            return false;

                        var itemY = activeIndex * 48;

                        var itemHeight = 48;
                        if (isExpanded) {
                            var listHeight = 36 * 3;
                            itemHeight = 48 + 4 + listHeight + 8;
                        }

                        var clickY = mouseY + resultsList.contentY;
                        return clickY >= itemY && clickY < itemY + itemHeight;
                    }

                    onClicked: mouse => {
                        if (root.deleteMode) {
                            if (!isClickInsideActiveItem(mouse.y)) {
                                root.cancelDeleteMode();
                            }
                            mouse.accepted = true;
                        } else if (root.renameMode) {
                            if (!isClickInsideActiveItem(mouse.y)) {
                                root.cancelRenameMode();
                            }
                            mouse.accepted = true;
                        } else if (root.expandedItemIndex >= 0) {
                            if (!isClickInsideActiveItem(mouse.y)) {
                                root.expandedItemIndex = -1;
                                root.selectedOptionIndex = 0;
                                root.keyboardNavigation = false;
                                mouse.accepted = true;
                            }
                        }
                    }

                    onPressed: mouse => {
                        if (isClickInsideActiveItem(mouse.y)) {
                            mouse.accepted = false;
                        } else {
                            mouse.accepted = true;
                        }
                    }

                    onReleased: mouse => {
                        if (isClickInsideActiveItem(mouse.y)) {
                            mouse.accepted = false;
                        } else {
                            mouse.accepted = true;
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 2
            Layout.fillHeight: true
            radius: Styling.radius(0)
            color: Colors.surface
        }

        Item {
            id: previewPanel
            Layout.fillWidth: true
            Layout.fillHeight: true

            property var currentSession: root.selectedIndex >= 0 && root.selectedIndex < root.filteredSessions.length ? root.filteredSessions[root.selectedIndex] : null

            Item {
                anchors.fill: parent
                visible: {
                    if (!previewPanel.currentSession)
                        return false;
                    if (previewPanel.currentSession.isCreateButton === true)
                        return false;
                    if (previewPanel.currentSession.isCreateSpecificButton === true)
                        return false;
                    return true;
                }

                Item {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: separator.top
                    anchors.bottomMargin: 8

                    Item {
                        anchors.fill: parent

                        property real totalWidth: root.sessionPanes.length > 0 ? root.sessionPanes[0].totalWidth || 1 : 1
                        property real totalHeight: root.sessionPanes.length > 0 ? root.sessionPanes[0].totalHeight || 1 : 1

                        property real scaleX: width / totalWidth
                        property real scaleY: height / totalHeight

                        Repeater {
                            model: root.sessionPanes
                            delegate: StyledRect {
                                id: paneRect
                                required property var modelData
                                property bool hovered: false
                                variant: hovered ? "focus" : "pane"

                                x: Math.floor(modelData.left * parent.scaleX)
                                y: Math.floor(modelData.top * parent.scaleY)
                                width: Math.floor(modelData.width * parent.scaleX)
                                height: Math.floor(modelData.height * parent.scaleY)

                                radius: Styling.radius(-2)

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    onEntered: {
                                        paneRect.hovered = true;
                                    }

                                    onExited: {
                                        paneRect.hovered = false;
                                    }

                                    onClicked: {
                                        let currentSession = previewPanel.currentSession;
                                        if (currentSession && !currentSession.isCreateButton && !currentSession.isCreateSpecificButton) {
                                            root.focusPane(currentSession.name, modelData.index);
                                        }
                                    }

                                    onDoubleClicked: {
                                        let currentSession = previewPanel.currentSession;
                                        if (currentSession && !currentSession.isCreateButton && !currentSession.isCreateSpecificButton) {
                                            root.attachToSession(currentSession.name);
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    border.width: modelData.active ? 2 : 0
                                    border.color: modelData.active ? Styling.srItem("overprimary") : "transparent"
                                    radius: paneRect.radius

                                    Behavior on border.width {
                                        enabled: Styling.animDuration > 0
                                        NumberAnimation {
                                            duration: Styling.animDuration / 2
                                            easing.type: Easing.OutQuart
                                        }
                                    }

                                    Behavior on border.color {
                                        enabled: Styling.animDuration > 0
                                        ColorAnimation {
                                            duration: Styling.animDuration / 2
                                            easing.type: Easing.OutQuart
                                        }
                                    }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    width: parent.width - 16

                                    Text {
                                        width: parent.width
                                        text: modelData.command
                                        font.family: Config.theme.font
                                        font.pixelSize: Config.theme.fontSize
                                        font.weight: Font.Bold
                                        color: Colors.overSurfaceVariant
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideMiddle
                                        visible: parent.parent.height > 35

                                        Behavior on color {
                                            enabled: Styling.animDuration > 0
                                            ColorAnimation {
                                                duration: Styling.animDuration / 2
                                                easing.type: Easing.OutQuart
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.width + "×" + modelData.height
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-2)
                                        color: Colors.outline
                                        opacity: 0.7
                                        visible: parent.parent.height > 70

                                        Behavior on color {
                                            enabled: Styling.animDuration > 0
                                            ColorAnimation {
                                                duration: Styling.animDuration / 2
                                                easing.type: Easing.OutQuart
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            visible: root.sessionPanes.length === 0 && !root.loadingSessionInfo

                            Text {
                                text: Icons.terminalWindow
                                font.family: Icons.font
                                font.pixelSize: 32
                                color: Colors.outline
                                anchors.horizontalCenter: parent.horizontalCenter
                                textFormat: Text.RichText
                            }

                            Text {
                                text: "No panes to display"
                                font.family: Config.theme.font
                                font.pixelSize: Config.theme.fontSize
                                color: Colors.outline
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Colors.background
                            visible: root.loadingSessionInfo

                            Row {
                                anchors.centerIn: parent
                                spacing: 12

                                Text {
                                    text: Icons.spinnerGap
                                    font.family: Icons.font
                                    font.pixelSize: 20
                                    color: Styling.srItem("overprimary")
                                    textFormat: Text.RichText

                                    RotationAnimator on rotation {
                                        from: 0
                                        to: 360
                                        duration: 1000
                                        loops: Animation.Infinite
                                        running: root.loadingSessionInfo
                                    }
                                }

                                Text {
                                    text: "Loading panes..."
                                    font.family: Config.theme.font
                                    font.pixelSize: Config.theme.fontSize
                                    color: Colors.outline
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: separator
                    anchors.bottom: windowsSection.top
                    anchors.bottomMargin: 8
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 2
                    radius: Styling.radius(0)
                    color: Colors.surface
                }

                Item {
                    id: windowsSection
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 32

                    Flickable {
                        anchors.fill: parent
                        contentWidth: windowsRow.width
                        contentHeight: height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Row {
                            id: windowsRow
                            spacing: 4
                            height: parent.height

                            Repeater {
                                model: root.sessionWindows
                                delegate: StyledRect {
                                    id: windowRect
                                    required property var modelData
                                    property bool hovered: false
                                    variant: {
                                        if (modelData.active) {
                                            return hovered ? "primaryfocus" : "primary";
                                        } else {
                                            return hovered ? "focus" : "common";
                                        }
                                    }
                                    width: Math.ceil(windowText.width) + 16
                                    height: parent.height
                                    radius: Styling.radius(-4)

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        onEntered: {
                                            windowRect.hovered = true;
                                        }

                                        onExited: {
                                            windowRect.hovered = false;
                                        }

                                        onClicked: {
                                            let currentSession = previewPanel.currentSession;
                                            if (currentSession && !currentSession.isCreateButton && !currentSession.isCreateSpecificButton) {
                                                root.switchToWindow(currentSession.name, modelData.index);
                                            }
                                        }

                                        onDoubleClicked: {
                                            let currentSession = previewPanel.currentSession;
                                            if (currentSession && !currentSession.isCreateButton && !currentSession.isCreateSpecificButton) {
                                                root.attachToSession(currentSession.name);
                                            }
                                        }
                                    }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            id: windowText
                                            text: modelData.index + ": " + modelData.name
                                            font.family: Config.theme.font
                                            font.pixelSize: Config.theme.fontSize
                                            font.weight: modelData.active ? Font.Bold : Font.Normal
                                            color: modelData.active ? Colors.overPrimary : Colors.overSurface

                                            Behavior on color {
                                                enabled: Styling.animDuration > 0
                                                ColorAnimation {
                                                    duration: Styling.animDuration / 2
                                                    easing.type: Easing.OutQuart
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

            Column {
                anchors.centerIn: parent
                spacing: 8
                visible: {
                    if (!previewPanel.currentSession)
                        return true;
                    if (previewPanel.currentSession.isCreateButton === true)
                        return true;
                    if (previewPanel.currentSession.isCreateSpecificButton === true)
                        return true;
                    return false;
                }

                Text {
                    text: Icons.terminalWindow
                    font.family: Icons.font
                    font.pixelSize: 48
                    color: Colors.surfaceBright
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.RichText
                }

                Text {
                    text: "No session selected"
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    font.weight: Font.Bold
                    color: Colors.overBackground
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Text {
                    text: "Select a session to preview"
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    color: Colors.outline
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Component.onCompleted: {
        refreshTmuxSessions();
        Qt.callLater(() => {
            focusSearchInput();
        });
    }

    Keys.onPressed: event => {
        if (root.deleteMode) {
            if (event.key === Qt.Key_Left) {
                root.deleteButtonIndex = 0;
                event.accepted = true;
            } else if (event.key === Qt.Key_Right) {
                root.deleteButtonIndex = 1;
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
                if (root.deleteButtonIndex === 0) {
                    root.cancelDeleteMode();
                } else {
                    root.confirmDeleteSession();
                }
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                root.cancelDeleteMode();
                event.accepted = true;
            }
        } else if (root.renameMode) {
            if (event.key === Qt.Key_Left) {
                root.renameButtonIndex = 0;
                event.accepted = true;
            } else if (event.key === Qt.Key_Right) {
                root.renameButtonIndex = 1;
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
                if (root.renameButtonIndex === 0) {
                    root.cancelRenameMode();
                } else {
                    root.confirmRenameSession();
                }
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                root.cancelRenameMode();
                event.accepted = true;
            }
        }
    }

    onDeleteModeChanged: {
        if (!deleteMode) {}
    }

    onRenameModeChanged: {
        if (!renameMode) {}
    }
}
