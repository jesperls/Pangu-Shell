pragma Singleton

import QtQuick
import Quickshell
import qs.modules.components

Singleton {
    id: root

    property bool initialized: false
    property alias state: store.data
    property var _pending: ({})

    signal stateLoaded

    function get(key, fallback) {
        if (!root.initialized && Object.prototype.hasOwnProperty.call(root._pending, key))
            return root._pending[key];
        return root.state[key] !== undefined ? root.state[key] : fallback;
    }

    function set(key, value) {
        if (!root.initialized) {
            const queued = Object.assign({}, root._pending);
            queued[key] = value;
            root._pending = queued;
            return;
        }
        if (root.state[key] === value)
            return;
        const next = Object.assign({}, store.data);
        next[key] = value;
        store.data = next;
        saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 150
        onTriggered: store.save()
    }

    JsonStore {
        id: store
        filePath: Quickshell.statePath("states.json")
        onDataLoaded: {
            const pendingKeys = Object.keys(root._pending);
            if (pendingKeys.length > 0) {
                store.data = Object.assign({}, store.data, root._pending);
                root._pending = ({});
                store.save();
            }
            root.initialized = true;
            root.stateLoaded();
        }
    }
}
