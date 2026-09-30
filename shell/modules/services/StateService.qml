pragma Singleton

import QtQuick
import Quickshell
import qs.modules.components

Singleton {
    id: root

    property bool initialized: false
    property alias state: store.data

    signal stateLoaded

    function get(key, fallback) {
        return root.state[key] !== undefined ? root.state[key] : fallback;
    }

    function set(key, value) {
        if (!root.initialized)
            return;
        root.state[key] = value;
        store.save();
    }

    JsonStore {
        id: store
        filePath: Quickshell.statePath("states.json")
        onDataLoaded: {
            root.initialized = true;
            root.stateLoaded();
        }
    }
}
