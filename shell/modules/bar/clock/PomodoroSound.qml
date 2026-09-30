import QtQuick
import QtMultimedia
import Quickshell
import qs.config

SoundEffect {
    id: alarmSound
    source: Paths.assetUrl("sound/polite-warning-tone.wav")
    
    signal stopAlarmRequested()
    
    property bool alarmActive: false
    property bool autoStart: false
    
    onPlayingChanged: {
        if (!playing && alarmActive && autoStart) {
            stopAlarmRequested();
        }
    }
}
