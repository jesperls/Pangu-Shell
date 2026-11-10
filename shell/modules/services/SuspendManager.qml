pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property bool isSuspending: false
    property bool wakeReady: true

    Timer {
        id: wakeReadyTimer
        interval: 3000
        repeat: false
        onTriggered: root.wakeReady = true
    }

    Timer {
        id: suspendWatchdog
        interval: 30000
        running: root.isSuspending
        onTriggered: root.onWakingUp()
    }

    signal preparingForSleep()
    signal wakingUp()

    function onPrepareForSleep() {
        wakeReadyTimer.stop();
        root.isSuspending = true;
        root.wakeReady = false;
        root.preparingForSleep();
    }

    function onWakingUp() {
        root.isSuspending = false;
        root.wakingUp();
        wakeReadyTimer.restart();
    }
}
