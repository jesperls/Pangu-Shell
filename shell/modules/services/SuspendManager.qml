pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool isSuspending: false
    
    property bool wakeReady: true

    property var wakeReadyTimer: Timer {
        id: wakeReadyTimer
        interval: 3000  // 3s delay for stability
        repeat: false
        onTriggered: root.wakeReady = true
    }

    signal preparingForSleep()
    signal wakingUp()

    function onPrepareForSleep() {
        console.log("SuspendManager: Preparing for sleep...");
        wakeReadyTimer.stop();
        root.isSuspending = true;
        root.wakeReady = false;
        root.preparingForSleep();
    }

    function onWakingUp() {
        console.log("SuspendManager: Waking up...");
        root.isSuspending = false;
        root.wakingUp();
        
        wakeReadyTimer.restart();
    }
}
