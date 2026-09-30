pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool inhibit: false

    Process {
        command: ["systemd-inhibit", "--what=idle", "--who=Pangu", "--why=Caffeine enabled", "--mode=block", "sleep", "infinity"]
        running: root.inhibit
    }

    function toggleInhibit() {
        root.inhibit = !root.inhibit;
    }

    onInhibitChanged: if (StateService.initialized) StateService.set("caffeine", root.inhibit)

    Component.onCompleted: if (StateService.initialized) restore()

    function restore() {
        root.inhibit = StateService.get("caffeine", false);
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            root.restore();
        }
    }
}
