pragma Singleton

import QtQuick
import Quickshell
import qs.modules.globals
import qs.config

Singleton {
    id: root

    property bool enabled: false
    property bool shuffle: true
    readonly property int intervalMinutes: Config.system.slideshow?.minutes ?? 30

    function toggle() {
        root.enabled = !root.enabled;
    }

    function next() {
        advance();
        if (root.enabled)
            slideTimer.restart();
    }

    function advance() {
        var manager = GlobalStates.wallpaperManager;
        if (!manager || !manager.initialLoadCompleted || manager.wallpaperPaths.length < 2)
            return;
        if (root.shuffle) {
            var index = Math.floor(Math.random() * (manager.wallpaperPaths.length - 1));
            if (index >= manager.currentIndex)
                index++;
            manager.setWallpaperByIndex(index);
        } else {
            manager.nextWallpaper();
        }
    }

    onEnabledChanged: {
        if (StateService.initialized)
            StateService.set("slideshow", root.enabled);
        if (root.enabled)
            slideTimer.restart();
        else
            slideTimer.stop();
    }

    onShuffleChanged: if (StateService.initialized) StateService.set("slideshowShuffle", root.shuffle)

    Timer {
        id: slideTimer
        interval: Math.max(1, root.intervalMinutes) * 60000
        repeat: true
        onTriggered: {
            if (!root.enabled || SuspendManager.isSuspending)
                return;
            root.advance();
        }
    }

    Connections {
        target: SuspendManager
        function onPreparingForSleep() {
            slideTimer.stop();
        }
        function onWakingUp() {
            if (root.enabled)
                slideTimer.restart();
        }
    }

    Component.onCompleted: if (StateService.initialized) restore()

    function restore() {
        root.enabled = StateService.get("slideshow", false);
        root.shuffle = StateService.get("slideshowShuffle", true);
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            root.restore();
        }
    }
}
