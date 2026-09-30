import QtQuick
import Quickshell.Io
import qs.config

FileView {
    id: root

    required property string name
    property string pathOverride: ""
    property bool ready: false
    property bool reloading: true
    property bool reloadPending: false

    property Timer reloadWatchdog: Timer { // reload() during a write can leave reloading latched.
        interval: 3000
        running: root.reloading
        onTriggered: {
            root.reloading = false;
            root.ready = true;
        }
    }

    path: root.pathOverride !== "" ? root.pathOverride : Config.configDir + "/" + root.name + ".json"
    atomicWrites: true
    watchChanges: true

    function reloadConfig() {
        if (ready && Config.isPaused(name)) {
            reloadPending = true;
            return;
        }
        reloadPending = false;
        reloading = true;
        reload();
    }

    property Connections editWatcher: Connections {
        target: Config
        function onEditGroupsChanged() { if (root.reloadPending) root.reloadConfig(); }
        function onPauseAutoSaveChanged() { if (root.reloadPending) root.reloadConfig(); }
    }

    onLoaded: {
        ready = true;
        reloading = false;
    }
    onLoadFailed: error => {
        reloading = false;
        ready = true;
        if (error === FileViewError.FileNotFound) {
            writeAdapter();
        }
    }
    onFileChanged: reloadConfig()
    onAdapterUpdated: if (ready && !reloading && !Config.isPaused(name)) writeAdapter()
}
