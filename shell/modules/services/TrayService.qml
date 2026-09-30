pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Singleton {
    id: root

    property var hiddenIds: []
    property var pendingChanges: ({})
    property bool restored: false
    readonly property var items: SystemTray.items.values
    readonly property var visibleItems: items.filter(item => !isHidden(item))
    readonly property var hiddenItems: items.filter(item => isHidden(item))

    function isHidden(item) {
        return !!item?.id && hiddenIds.includes(item.id);
    }

    function setHidden(item, hidden) {
        if (!item?.id)
            return;
        if (!restored)
            pendingChanges = Object.assign({}, pendingChanges, {[item.id]: hidden});
        const next = hiddenIds.filter(id => id !== item.id);
        hiddenIds = hidden ? next.concat([item.id]) : next;
    }

    function restore() {
        if (restored)
            return;
        const saved = StateService.get("trayHiddenIds", []);
        let next = Array.isArray(saved) ? saved.filter((id, index) => typeof id === "string"
            && id.length > 0 && saved.indexOf(id) === index).slice(0, 1024) : [];
        for (const id of Object.keys(pendingChanges)) {
            next = next.filter(entry => entry !== id);
            if (pendingChanges[id]) next.push(id);
        }
        hiddenIds = next;
        restored = true;
        if (Object.keys(pendingChanges).length) StateService.set("trayHiddenIds", hiddenIds);
        pendingChanges = ({});
    }

    onHiddenIdsChanged: if (restored) StateService.set("trayHiddenIds", hiddenIds)
    Component.onCompleted: if (StateService.initialized) restore()

    Connections {
        target: StateService
        function onStateLoaded() { root.restore(); }
    }
}
