import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services

PanelWindow {
    id: contextWindow

    property var menuHandle: null
    property var customItems: []
    property int menuWidth: 160
    property int itemHeight: 32
    property string menuType: ""

    screen: Quickshell.screens[0] ?? null

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    exclusiveZone: 0

    mask: Region {
        item: menuContainer
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            menu.hoveredIndex = -1;
            menu.previousHoveredIndex = -1;
            contextWindow.close();
        }
    }

    FocusScope {
        id: menuContainer
        anchors.fill: parent
        focus: contextWindow.visible
        Keys.onEscapePressed: contextWindow.close()

        OptionsMenu {
            id: menu

            menuWidth: contextWindow.menuWidth
            itemHeight: contextWindow.itemHeight

            function cleanMenuText(text) {
                if (!text || text === "") return "";
                
                text = String(text);
                
                if (text.startsWith(":/// ")) {
                    text = text.substring(5);
                }
                
                return text.trim();
            }

            function isValidIcon(icon) {
                if (!icon || icon === "") return false;
                
                if (icon.length > 4) return false;
                if (icon.includes("/") || icon.includes(".") || icon.includes(":")) return false;
                
                return true;
            }

            function isImageIcon(icon) {
                if (!icon || icon === "") return false;
                
                if (icon.includes("/") || icon.includes(".")) return true;
                if (icon.startsWith("file://") || icon.startsWith("http")) return true;
                if (icon.length > 10) return true;
                
                return false;
            }

            QsMenuOpener {
                id: menuOpener
                menu: contextWindow.menuHandle
            }

            items: {
                if (contextWindow.customItems && contextWindow.customItems.length > 0) {
                    return contextWindow.customItems.map(item => ({
                        text: item.text || "",
                        icon: item.icon || "",
                        isImageIcon: item.isImageIcon || false,
                        enabled: item.enabled !== false,
                        isSeparator: item.isSeparator || false,
                        highlightColor: item.highlightColor,
                        textColor: item.textColor,
                        onTriggered: function() {
                            let callback = item.onTriggered;
                            contextWindow.close();
                            if (callback) {
                                Qt.callLater(callback);
                            }
                        }
                    }));
                }

                if (!contextWindow.menuHandle) {
                    return [];
                }

                if (!menuOpener.children || !menuOpener.children.values) {
                    return [];
                }

                let menuItems = [];

                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    let entry = menuOpener.children.values[i];

                    if (entry) {
                        if (entry.isSeparator) {
                            menuItems.push({
                                text: "",
                                icon: "",
                                enabled: false,
                                isSeparator: true,
                                onTriggered: function () {}
                            });
                        } else {
                            let originalText = entry.text;
                            let cleanText = menu.cleanMenuText(originalText);
                            
                            let iconToUse = "";
                            let useImageIcon = false;
                            
                            if (entry.icon) {
                                if (menu.isValidIcon(entry.icon)) {
                                    iconToUse = entry.icon;
                                    useImageIcon = false;
                                } else if (menu.isImageIcon(entry.icon)) {
                                    iconToUse = entry.icon;
                                    useImageIcon = true;
                                }
                            }

                            if (cleanText === "" && iconToUse === "") {
                                continue;
                            }

                            menuItems.push({
                                text: cleanText,
                                icon: iconToUse,
                                isImageIcon: useImageIcon,
                                enabled: entry.enabled !== false,
                                isSeparator: false,
                                onTriggered: function () {
                                    let callback = entry.triggered;
                                    contextWindow.close();
                                    if (callback) {
                                        Qt.callLater(callback);
                                    }
                                }
                            });
                        }
                    }
                }
                return menuItems;
            }
        }
    }

    function placeAtCursor() {
        Compositor.request("j/cursorpos", reply => {
            let pos;
            try {
                pos = JSON.parse(reply);
            } catch (e) {
                console.warn("ContextMenu: could not read cursor position:", reply);
                return;
            }
            let monX = 0;
            let monY = 0;
            let monW = contextWindow.width || 1920;
            let monH = contextWindow.height || 1080;
            const monitors = Compositor.monitors?.values ?? [];
            let matchedMon = null;
            for (let i = 0; i < monitors.length; i++) {
                const m = monitors[i];
                const scale = m.scale > 0 ? m.scale : 1;
                const lw = m.width / scale;
                const lh = m.height / scale;
                if (pos.x >= m.x && pos.x < m.x + lw && pos.y >= m.y && pos.y < m.y + lh) {
                    matchedMon = m;
                    monX = m.x;
                    monY = m.y;
                    monW = lw;
                    monH = lh;
                    break;
                }
            }
            if (!matchedMon && Compositor.focusedMonitor) {
                matchedMon = Compositor.focusedMonitor;
                const scale = matchedMon.scale > 0 ? matchedMon.scale : 1;
                monX = matchedMon.x;
                monY = matchedMon.y;
                monW = matchedMon.width / scale;
                monH = matchedMon.height / scale;
            }
            if (matchedMon) {
                const targetScreen = Quickshell.screens.find(s => s.name === matchedMon.name);
                if (targetScreen && contextWindow.screen !== targetScreen) {
                    contextWindow.screen = targetScreen;
                }
            }
            const estHeight = Math.max(48, (menu.items?.length ?? 1) * contextWindow.itemHeight + 16);
            const localX = pos.x - monX;
            const localY = pos.y - monY;
            menu.x = Math.max(8, Math.min(localX, monW - menu.menuWidth - 8));
            menu.y = Math.max(8, Math.min(localY, monH - estHeight - 8));
            menu.visible = false;
            contextWindow.visible = true;
            contextWindow.WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive;
            Qt.callLater(() => {
                menuContainer.forceActiveFocus();
                menu.popup();
            });
        });
    }

    function openCustomMenu(items, width, height, type) {
        menuHandle = null;
        customItems = items;
        menuType = type || "";
        menuWidth = width !== undefined ? width : 160;
        itemHeight = height !== undefined ? height : 32;
        if (menuType === "player") {
            Visibilities.playerMenuOpen = true;
        }
        contextWindow.placeAtCursor();
    }

    function close() {
        menu.hoveredIndex = -1;
        menu.previousHoveredIndex = -1;
        menu.close();
        visible = false;
        WlrLayershell.keyboardFocus = WlrKeyboardFocus.None;
        if (menuType === "player") {
            Visibilities.playerMenuOpen = false;
        }
        Qt.callLater(() => {
            menuHandle = null;
            customItems = [];
            menuType = "";
            menuWidth = 160;
            itemHeight = 32;
        });
    }

    onVisibleChanged: {
        if (!visible) {
            menu.hoveredIndex = -1;
            menu.previousHoveredIndex = -1;
            menu.close();
            WlrLayershell.keyboardFocus = WlrKeyboardFocus.None;
            if (menuType === "player") {
                Visibilities.playerMenuOpen = false;
            }
            Qt.callLater(() => {
                menuHandle = null;
                customItems = [];
                menuType = "";
                menuWidth = 160;
                itemHeight = 32;
            });
        }
    }

    Connections {
        target: menu
        function onClosed() {
            contextWindow.close();
        }
    }
}
