pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.services

Singleton {
    id: root

    property var screens: ({})
    property var barPanels: ({})
    property var notches: ({})
    property var notchPanels: ({})
    property var dockPanels: ({})
    property string currentActiveModule: ""
    property string lastFocusedScreen: ""
    property var contextMenu: null
    property bool playerMenuOpen: false
    readonly property var moduleNames: ["launcher", "dashboard", "overview", "powermenu", "tools"]

    property var barPopupGroups: ({})

    function isNotchOpen(screenProps) {
        return screenProps ? (screenProps.launcher || screenProps.dashboard || screenProps.powermenu || screenProps.tools) : false;
    }

    function setContextMenu(menu) {
        contextMenu = menu;
    }

    function getForScreen(screenName) {
        return screens[screenName] || null;
    }

    function syncScreens() {
        const names = Quickshell.screens.map(screen => screen.name);
        const next = {};
        const removed = [];
        for (const name of names)
            next[name] = screens[name] || screenPropertiesComponent.createObject(root, {screenName: name});
        for (const name in screens)
            if (!names.includes(name)) removed.push(screens[name]);
        screens = next;
        if (!names.includes(lastFocusedScreen)) {
            clearAll();
            currentActiveModule = "";
            lastFocusedScreen = "";
        }
        for (const properties of removed) properties.destroy();
    }

    Component.onCompleted: syncScreens()

    function getForActive() {
        // An open surface stays on its original screen when monitor focus changes.
        if (!lastFocusedScreen) {
            return null;
        }
        return getForScreen(lastFocusedScreen);
    }

    function _updateMap(map, key, value) {
        var newMap = {};
        for (var k in map) {
            newMap[k] = map[k];
        }
        if (value === null) {
            delete newMap[key];
        } else {
            newMap[key] = value;
        }
        return newMap;
    }

    function registerBarPanel(screenName, barPanel) {
        barPanels = _updateMap(barPanels, screenName, barPanel);
    }

    function unregisterBarPanel(screenName) {
        barPanels = _updateMap(barPanels, screenName, null);
    }

    function getBarPanelForScreen(screenName) {
        return barPanels[screenName] || null;
    }

    function registerNotch(screenName, notchContainer) {
        notches = _updateMap(notches, screenName, notchContainer);
    }

    function unregisterNotch(screenName) {
        notches = _updateMap(notches, screenName, null);
    }

    function getNotchForScreen(screenName) {
        return notches[screenName] || null;
    }

    function registerNotchPanel(screenName, notchPanel) {
        notchPanels = _updateMap(notchPanels, screenName, notchPanel);
    }

    function unregisterNotchPanel(screenName) {
        notchPanels = _updateMap(notchPanels, screenName, null);
    }

    function registerDockPanel(screenName, dockPanel) {
        dockPanels = _updateMap(dockPanels, screenName, dockPanel);
    }

    function unregisterDockPanel(screenName) {
        dockPanels = _updateMap(dockPanels, screenName, null);
    }

    function registerBarPopup(popup) {
        if (!popup || !popup.groupId) return;
        const groups = Object.assign({}, barPopupGroups);
        const list = groups[popup.groupId] || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i] !== popup && list[i] !== null && list[i].visible) {
                list[i].close();
            }
        }
        groups[popup.groupId] = [popup];
        barPopupGroups = groups;
    }

    function unregisterBarPopup(popup) {
        if (!popup || !popup.groupId) return;
        const groups = Object.assign({}, barPopupGroups);
        const list = (groups[popup.groupId] || []).filter(p => p !== popup && p !== null);
        if (list.length === 0) {
            delete groups[popup.groupId];
        } else {
            groups[popup.groupId] = list;
        }
        barPopupGroups = groups;
    }

    function setActiveModule(moduleName) {
        const focusedMonitor = Compositor.focusedMonitor;
        if (!focusedMonitor)
            return;

        const focusedScreenName = focusedMonitor.name;

        clearAll();

        if (moduleName) {
            currentActiveModule = moduleName;
            applyActiveModuleToScreen(focusedScreenName);
        } else {
            currentActiveModule = "";
        }

        lastFocusedScreen = focusedScreenName;
    }

    function isActiveOnFocusedScreen(moduleName) {
        return currentActiveModule === moduleName && lastFocusedScreen === Compositor.focusedMonitor?.name;
    }

    Component {
        id: screenPropertiesComponent
        QtObject {
            property string screenName
            property bool launcher: false
            property bool dashboard: false
            property bool overview: false
            property bool powermenu: false
            property bool tools: false
        }
    }

    function clearAll() {
        for (const screenName in screens) {
            const screenProps = screens[screenName];
            for (let i = 0; i < moduleNames.length; i++) {
                screenProps[moduleNames[i]] = false;
            }
        }
    }

    function applyActiveModuleToScreen(screenName) {
        if (!currentActiveModule)
            return;

        const screenProps = getForScreen(screenName);
        if (screenProps && moduleNames.indexOf(currentActiveModule) !== -1) {
            screenProps[currentActiveModule] = true;
        }
    }

    Connections {
        target: Quickshell
        function onScreensChanged() { root.syncScreens(); }
    }
}
