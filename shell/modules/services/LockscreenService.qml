pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.globals
import qs.config

QtObject {
    id: root

    property bool _firstStartOfSession: false

    property Process bootProbe: Process {
        running: true
        command: ["mkdir", "--", (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/pangu-session-started"]
        onExited: code => {
            root._firstStartOfSession = code === 0;
            root.maybeBootLock();
        }
    }

    property Connections configReady: Connections {
        target: Config
        function onInitialLoadCompleteChanged() {
            root.maybeBootLock();
        }
    }

    function maybeBootLock() {
        if (root._firstStartOfSession && Config.initialLoadComplete && Config.lockscreen.lockOnBoot) {
            root._firstStartOfSession = false;
            root.lock();
        }
    }

    function toggle() {
        root.lock();
    }

    function lock() {
        GlobalStates.lockscreenVisible = true;
    }

    property IpcHandler ipc: IpcHandler {
        target: "lockscreen"

        function toggle() {
            root.toggle();
        }

        function lock() {
            root.lock();
        }

    }
}
