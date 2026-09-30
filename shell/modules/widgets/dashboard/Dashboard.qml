import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.notch
import qs.modules.widgets.dashboard.widgets
import qs.modules.widgets.dashboard.controls
import qs.modules.widgets.dashboard.wallpapers
import qs.modules.widgets.dashboard.metrics
import qs.config

NotchAnimationBehavior {
    id: root

    property int leftPanelWidth
    property string screenName: ""
    property bool initialized: false

    property var state: QtObject {
        property int currentTab: 0
    }

    readonly property var tabDefs: [
        { icon: Icons.widgets },
        { icon: Icons.wallpapers },
        { icon: Icons.heartbeat }
    ]

    readonly property var tabIndices: {
        const out = [];
        if ((Config.dashboard.showWidgets ?? true)) out.push(0);
        if ((Config.dashboard.showWallpapers ?? true)) out.push(1);
        if ((Config.dashboard.showMetrics ?? true)) out.push(2);
        return out;
    }

    readonly property int tabCount: tabIndices.length
    readonly property int tabSpacing: 8

    readonly property int tabWidth: 48
    readonly property string tabPosition: Config.dashboard.tabPosition ?? "left"
    readonly property bool railVertical: tabPosition === "left" || tabPosition === "right"
    readonly property bool railFirst: tabPosition === "left" || tabPosition === "top"

    function componentIndexOf(visibleIndex) {
        return (visibleIndex >= 0 && visibleIndex < tabIndices.length) ? tabIndices[visibleIndex] : 0;
    }

    function visibleIndexOf(componentIndex) {
        return tabIndices.indexOf(componentIndex);
    }

    readonly property var tabModel: tabIndices.map(i => tabDefs[i].icon)

    readonly property int baseContentWidth: {
        const item = stack.currentItem;
        if (item && item.implicitWidth > 0)
            return item.implicitWidth;
        const idx = componentIndexOf(state.currentTab);
        return idx === 0 ? 760 : (idx === 1 ? 800 : 700);
    }
    readonly property int baseContentHeight: 430

    readonly property bool showTabRail: Config.dashboard.showTabRail ?? true
    readonly property int configWidth: Config.dashboard.width ?? 0
    readonly property int configHeight: Config.dashboard.height ?? 0
    readonly property int tabRailWidth: showTabRail ? tabWidth : 0
    readonly property int separatorWidth: showTabRail ? 2 : 0
    readonly property int layoutSpacing: showTabRail ? 16 : 0
    readonly property int railBlockSize: tabRailWidth + separatorWidth + layoutSpacing

    implicitWidth: configWidth > 0 ? configWidth : (railVertical ? baseContentWidth + railBlockSize : baseContentWidth)
    implicitHeight: configHeight > 0 ? configHeight : (railVertical ? baseContentHeight : baseContentHeight + railBlockSize)

    property var lruAccessOrder: [0]
    property var lruTabsLoaded: ({0: true})

    function updateLRUAccess(visibleIndex) {
        const cIdx = componentIndexOf(visibleIndex);
        const idx = lruAccessOrder.indexOf(cIdx);
        if (idx !== -1) {
            lruAccessOrder.splice(idx, 1);
        }
        lruAccessOrder.push(cIdx);
        updateLoadedTabs();
    }

    function updateLoadedTabs() {
        let newLoadedTabs = {};
        
        newLoadedTabs[0] = true;
        
        newLoadedTabs[componentIndexOf(root.state.currentTab)] = true;

        if (Config.performance.dashboardPersistTabs) {
            const maxTabs = Math.max(1, Config.performance.dashboardMaxPersistentTabs);
            const startIdx = Math.max(0, lruAccessOrder.length - maxTabs);
            for (let i = startIdx; i < lruAccessOrder.length; i++) {
                newLoadedTabs[lruAccessOrder[i]] = true;
            }
        }

        lruTabsLoaded = newLoadedTabs;
    }

    function shouldTabBeLoaded(componentIndex) {
        if (componentIndex === 0) return true;

        if (Config.performance.dashboardPersistTabs) {
            return lruTabsLoaded[componentIndex] === true;
        } else {
            return componentIndex === componentIndexOf(root.state.currentTab);
        }
    }

    focus: true

    isVisible: screenName ? (Visibilities.getForScreen(screenName)?.dashboard ?? false) : false

    Component.onCompleted: {
        root.state.currentTab = root.visibleIndexOf(GlobalStates.dashboardCurrentTab);
        initialized = true;
        root.clampCurrentTab();
    }

    onTabIndicesChanged: if (initialized) {
        root.state.currentTab = root.visibleIndexOf(GlobalStates.dashboardCurrentTab);
        root.clampCurrentTab();
    }

    function clampCurrentTab() {
        if (root.state.currentTab < 0)
            root.state.currentTab = 0;
        if (root.state.currentTab >= root.tabCount) {
            root.state.currentTab = Math.max(0, root.tabCount - 1);
        }
        if (isVisible)
            GlobalStates.dashboardCurrentTab = root.componentIndexOf(root.state.currentTab);
    }

    onIsVisibleChanged: {
        if (isVisible) {
            if (stack.currentItem && stack.currentItem.focusSearchInput) {
                focusUnifiedLauncherTimer.restart();
            } else if (GlobalStates.dashboardCurrentTab === 0) {
                Notifications.hideAllPopups();
                focusUnifiedLauncherTimer.restart();
            }
        } else {
            GlobalStates.clearLauncherState();
        }
    }

    Timer {
        id: focusUnifiedLauncherTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (stack.currentItem && stack.currentItem.focusSearchInput) {
                stack.currentItem.focusSearchInput();
            }
        }
    }

    Connections {
        target: GlobalStates
        function onDashboardCurrentTabChanged() {
            stack.navigateToTab(root.visibleIndexOf(GlobalStates.dashboardCurrentTab));
        }

        function onLauncherSearchTextChanged() {
            if (isVisible && GlobalStates.dashboardCurrentTab === 0) {
                focusUnifiedLauncherTimer.restart();
            }
        }
    }

    Item {
        id: mainLayout
        anchors.fill: parent

        Item {
            id: tabsContainer
            visible: root.showTabRail
            x: root.railVertical ? (root.railFirst ? 0 : parent.width - root.tabWidth) : 0
            y: root.railVertical ? 0 : (root.railFirst ? 0 : parent.height - root.tabWidth)
            width: root.railVertical ? root.tabWidth : parent.width
            height: root.railVertical ? parent.height : root.tabWidth

            WheelHandler {
                id: wheelHandler
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    let scrollUp = event.angleDelta.y > 0;
                    let newIndex = root.state.currentTab;

                    if (scrollUp && newIndex > 0) {
                        newIndex = newIndex - 1;
                    } else if (!scrollUp && newIndex < root.tabCount - 1) {
                        newIndex = newIndex + 1;
                    }

                    if (newIndex !== root.state.currentTab) {
                        stack.navigateToTab(newIndex);
                    }
                }
            }

            StyledRect {
                id: tabHighlight
                variant: "primary"
                radius: Styling.radius(4)
                z: 0

                property real idx1: root.state.currentTab
                property real idx2: root.state.currentTab

                function getOffsetForIndex(idx) {
                    return idx * (root.tabWidth + root.tabSpacing);
                }

                property real target1: getOffsetForIndex(idx1)
                property real target2: getOffsetForIndex(idx2)

                property real animated1: target1
                property real animated2: target2

                x: root.railVertical ? 0 : Math.min(animated1, animated2)
                y: root.railVertical ? Math.min(animated1, animated2) : 0
                width: root.railVertical ? parent.width : (Math.abs(animated2 - animated1) + root.tabWidth)
                height: root.railVertical ? (Math.abs(animated2 - animated1) + root.tabWidth) : parent.height

                Behavior on animated1 {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration / 3
                        easing.type: Easing.OutSine
                    }
                }
                Behavior on animated2 {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration
                        easing.type: Easing.OutSine
                    }
                }

                onTarget1Changed: animated1 = target1
                onTarget2Changed: animated2 = target2
            }

            Column {
                id: tabsColumn
                visible: root.railVertical
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: root.tabSpacing

                Repeater {
                    model: root.tabModel
                    delegate: tabButtonComponent
                }
            }

            Row {
                id: tabsRow
                visible: !root.railVertical
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                spacing: root.tabSpacing

                Repeater {
                    model: root.tabModel
                    delegate: tabButtonComponent
                }
            }

            StyledRect {
                id: controlsButtonContainer
                x: root.railVertical ? 0 : parent.width - root.tabWidth
                y: root.railVertical ? parent.height - root.tabWidth : 0
                width: root.tabWidth
                height: root.tabWidth
                radius: Styling.radius(4)
                variant: controlsButton.hovered ? "focus" : "common"
                z: -1

                opacity: GlobalStates.settingsWindowVisible ? 0 : 1

                Behavior on opacity {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Button {
                id: controlsButton
                x: root.railVertical ? 0 : parent.width - root.tabWidth
                y: root.railVertical ? parent.height - root.tabWidth : 0
                width: root.tabWidth
                height: root.tabWidth
                flat: true
                hoverEnabled: true
                z: 1

                background: Rectangle {
                    color: "transparent"
                }

                contentItem: Text {
                    text: Icons.gear
                    font.family: Icons.font
                    font.pixelSize: 20
                    font.weight: Font.Medium
                    color: GlobalStates.settingsWindowVisible ? Styling.srItem("primary") : Colors.overBackground
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter

                    Behavior on color {
                        enabled: Styling.animDuration > 0
                        ColorAnimation {
                            duration: Styling.animDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                onClicked: GlobalShortcuts.toggleSettings(root.screenName)
            }
        }

        Separator {
            id: railSeparator
            visible: root.showTabRail
            vert: root.railVertical
            x: root.railVertical ? (root.railFirst ? (root.tabWidth + 8) : (parent.width - root.tabWidth - 2 - 8)) : 0
            y: root.railVertical ? 0 : (root.railFirst ? (root.tabWidth + 8) : (parent.height - root.tabWidth - 2 - 8))
            width: root.railVertical ? 2 : parent.width
            height: root.railVertical ? parent.height : 2
        }

        Rectangle {
            id: viewWrapper

            color: "transparent"

            x: root.railVertical ? (root.railFirst ? root.railBlockSize : 0) : 0
            y: root.railVertical ? 0 : (root.railFirst ? root.railBlockSize : 0)
            width: root.railVertical ? (parent.width - root.railBlockSize) : parent.width
            height: root.railVertical ? parent.height : (parent.height - root.railBlockSize)

            clip: true

            Item {
                id: stack
                anchors.fill: parent

                property int currentIndex: root.state.currentTab

                Connections {
                    target: GlobalStates
                    function onDashboardCurrentTabChanged() {
                        stack.navigateToTab(root.visibleIndexOf(GlobalStates.dashboardCurrentTab));
                    }
                }

                function navigateToTab(index) {
                    if (index >= 0 && index < root.tabCount && index !== root.state.currentTab) {
                        if (root.componentIndexOf(root.state.currentTab) === 0 && root.componentIndexOf(index) !== 0) {
                            GlobalStates.clearLauncherState();
                        }

                        root.state.currentTab = index;
                        GlobalStates.dashboardCurrentTab = root.componentIndexOf(index);
                        
                        root.updateLRUAccess(index);

                        if (root.componentIndexOf(index) === 0) {
                            Notifications.hideAllPopups();
                            focusUnifiedLauncherTimer.restart();
                        }
                    }
                }

                component TabLoader : Loader {
                    anchors.fill: parent
                    active: root.shouldTabBeLoaded(index) || root.state.currentTab === root.visibleIndexOf(index)
                    
                    visible: root.state.currentTab === root.visibleIndexOf(index)
                    
                    opacity: visible ? 1 : 0
                    transform: Translate {
                        y: visible ? 0 : (root.state.currentTab > root.visibleIndexOf(index) ? -20 : 20)
                        Behavior on y {
                             enabled: Styling.animDuration > 0
                             NumberAnimation { duration: Styling.animDuration; easing.type: Easing.OutQuart }
                        }
                    }

                    Behavior on opacity {
                        enabled: Styling.animDuration > 0
                        NumberAnimation { duration: Styling.animDuration; easing.type: Easing.OutQuart }
                    }

                    onLoaded: {
                        if (visible && item && item.focusSearchInput) {
                            focusUnifiedLauncherTimer.restart();
                        }
                    }
                    
                    onVisibleChanged: {
                        if (visible && item && item.focusSearchInput) {
                            focusUnifiedLauncherTimer.restart();
                        }
                    }
                }

                TabLoader {
                    property int index: 0
                    sourceComponent: unifiedLauncherComponent
                    z: visible ? 1 : 0
                }

                TabLoader {
                    property int index: 1
                    sourceComponent: wallpapersComponent
                    z: visible ? 1 : 0
                }

                TabLoader {
                    property int index: 2
                    sourceComponent: metricsComponent
                    z: visible ? 1 : 0
                }
                
                property var currentItem: {
                    switch(root.componentIndexOf(root.state.currentTab)) {
                        case 0: return children[0].item;
                        case 1: return children[1].item;
                        case 2: return children[2].item;
                        default: return null;
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    property real startY: 0
                    property real startX: 0
                    property bool swiping: false
                    property real swipeThreshold: 50
                    
                    propagateComposedEvents: true
                    preventStealing: false

                    onPressed: mouse => {
                        startY = mouse.y;
                        startX = mouse.x;
                        swiping = false;
                        mouse.accepted = false;  // Let children handle clicks
                    }

                    onPositionChanged: mouse => {
                        let deltaY = mouse.y - startY;
                        let deltaX = Math.abs(mouse.x - startX);

                        if (Math.abs(deltaY) > 20 && deltaX < 30) {
                            swiping = true;
                        }
                    }

                    onReleased: mouse => {
                        if (swiping) {
                            let deltaY = mouse.y - startY;

                            if (deltaY < -swipeThreshold && root.state.currentTab < root.tabCount - 1) {
                                stack.navigateToTab(root.state.currentTab + 1);
                            } else if (deltaY > swipeThreshold && root.state.currentTab > 0) {
                                stack.navigateToTab(root.state.currentTab - 1);
                            }
                        }
                        swiping = false;
                        mouse.accepted = false;
                    }
                }
            }
        }
    }

    Shortcut {
        id: nextTabShortcut
        sequence: "Ctrl+Tab"
        enabled: GlobalStates.dashboardOpen

        onActivated: {
            let nextIndex = (root.state.currentTab + 1) % root.tabCount;
            stack.navigateToTab(nextIndex);
        }
    }

    Shortcut {
        id: prevTabShortcut
        sequence: "Ctrl+Shift+Tab"
        enabled: GlobalStates.dashboardOpen

        onActivated: {
            let prevIndex = root.state.currentTab - 1;
            if (prevIndex < 0) {
                prevIndex = root.tabCount - 1;
            }
            stack.navigateToTab(prevIndex);
        }
    }

    property real animatedWidth: implicitWidth
    property real animatedHeight: implicitHeight

    width: animatedWidth
    height: animatedHeight

    onImplicitWidthChanged: animatedWidth = implicitWidth
    onImplicitHeightChanged: animatedHeight = implicitHeight

    Behavior on animatedWidth {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration
            easing.type: Easing.OutBack
            easing.overshoot: 1.1
        }
    }

    Behavior on animatedHeight {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration
            easing.type: Easing.OutBack
            easing.overshoot: 1.1
        }
    }

    Component {
        id: tabButtonComponent
        Button {
            required property int index
            required property string modelData

            text: modelData
            flat: true
            width: root.tabWidth
            height: root.tabWidth

            background: Rectangle {
                color: "transparent"
                radius: Styling.radius(4)
            }

            contentItem: Text {
                text: parent.text
                textFormat: Text.RichText
                color: root.state.currentTab === index ? Styling.srItem("primary") : Colors.overBackground
                font.family: Icons.font
                font.pixelSize: 20
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                Behavior on color {
                    enabled: Styling.animDuration > 0
                    ColorAnimation {
                        duration: Styling.animDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }

            onClicked: stack.navigateToTab(index)
        }
    }

    Component {
        id: unifiedLauncherComponent
        WidgetsTab {
            leftPanelWidth: root.leftPanelWidth
        }
    }

    Component {
        id: metricsComponent
        MetricsTab {}
    }

    Component {
        id: wallpapersComponent
        WallpapersTab {}
    }
}
