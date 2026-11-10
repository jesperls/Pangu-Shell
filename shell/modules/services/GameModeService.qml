pragma Singleton

import QtQuick
import Quickshell
import qs.config
import qs.modules.components
import qs.modules.services

Singleton {
    id: root

    property var workspaces: []
    property bool _reloadPending: false

    readonly property int activeWorkspace: Compositor.focusedWorkspace ? Compositor.focusedWorkspace.id : 0
    readonly property bool toggled: workspaces.indexOf(activeWorkspace) !== -1

    function toggle() {
        const id = root.activeWorkspace;
        if (id <= 0)
            return;
        root.workspaces = root.toggled ? root.workspaces.filter(w => w !== id) : root.workspaces.concat(id);
        StateService.set("gameModeWorkspaces", root.workspaces);
        root._reloadPending = true;
        root.publish();
    }

    function restore() {
        const saved = StateService.get("gameModeWorkspaces", []);
        root.workspaces = Array.isArray(saved) ? saved.filter((id, index) => Number.isInteger(id) && id > 0 && saved.indexOf(id) === index) : [];
        if (root.workspaces.length > 0)
            root._reloadPending = true;
        root.publish();
    }

    function publish() {
        file.write(`return { ${root.workspaces.join(", ")} }\n`);
    }

    GeneratedFile {
        id: file
        path: Paths.dataPath("gamemode.lua")
        onWritten: {
            if (root._reloadPending) {
                root._reloadPending = false;
                Compositor.reloadConfig();
            }
        }
    }

    Component.onCompleted: if (StateService.initialized) restore()

    Connections {
        target: StateService
        function onStateLoaded() {
            root.restore();
        }
    }
}
