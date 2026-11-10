pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import qs.config
import qs.modules.services

Singleton {
    id: root

    property bool isRunning: false
    property bool isWorkSession: true
    property bool alarmActive: false
    property int completedCycles: 0
    property bool blinkPhase: false

    property int timeLeft: Config.system.pomodoro.workTime
    property int totalTime: Config.system.pomodoro.workTime
    property double _deadlineMs: 0

    readonly property real visualProgress: alarmActive ? 0 : (totalTime > 0 ? Math.max(0, Math.min(1, timeLeft / totalTime)) : 0)
    readonly property bool isResuming: !isRunning && !alarmActive && timeLeft > 0
        && timeLeft < (isWorkSession ? Config.system.pomodoro.workTime : Config.system.pomodoro.restTime)
    readonly property string formattedTime: {
        const m = Math.floor(Math.max(0, root.timeLeft) / 60);
        const s = Math.max(0, root.timeLeft) % 60;
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0");
    }

    signal requestPopupOpen()

    readonly property var spotifyPlayer: {
        for (const player of MprisController.filteredPlayers) {
            if ((player.dbusName || "").toLowerCase().includes("spotify"))
                return player;
        }
        return null;
    }

    function updateSpotify() {
        if (!Config.system.pomodoro.syncSpotify || !root.spotifyPlayer)
            return;
        const spotify = root.spotifyPlayer;
        if (root.isRunning && root.isWorkSession) {
            if (!spotify.isPlaying && spotify.canPlay)
                spotify.play();
        } else {
            if (spotify.isPlaying && spotify.canPause)
                spotify.pause();
        }
    }

    onIsRunningChanged: updateSpotify()
    onIsWorkSessionChanged: updateSpotify()

    Connections {
        target: Config.system.pomodoro
        function onSyncSpotifyChanged() {
            root.updateSpotify();
        }
        function onWorkTimeChanged() {
            if (!root.isRunning && !root.alarmActive && root.isWorkSession && !root.isResuming) {
                root.timeLeft = Config.system.pomodoro.workTime;
                root.totalTime = root.timeLeft;
            }
        }
        function onRestTimeChanged() {
            if (!root.isRunning && !root.alarmActive && !root.isWorkSession && !root.isResuming) {
                root.timeLeft = Config.system.pomodoro.restTime;
                root.totalTime = root.timeLeft;
            }
        }
    }

    function start() {
        if (root.isRunning)
            return;
        if (root.alarmActive) {
            root.stopAlarm();
            root.nextSession();
            return;
        }
        const configTime = root.isWorkSession ? Config.system.pomodoro.workTime : Config.system.pomodoro.restTime;
        if (root.timeLeft <= 0)
            root.timeLeft = configTime;
        if (root.timeLeft === configTime || root.totalTime <= 0)
            root.totalTime = root.timeLeft;
        root._deadlineMs = Date.now() + root.timeLeft * 1000;
        root.isRunning = true;
    }

    function pause() {
        if (!root.isRunning)
            return;
        root.timeLeft = Math.max(0, Math.ceil((root._deadlineMs - Date.now()) / 1000));
        root._deadlineMs = 0;
        root.isRunning = false;
    }

    function toggleTimer() {
        if (root.alarmActive) {
            root.stopAlarm();
            root.nextSession();
            return;
        }
        if (root.isRunning)
            root.pause();
        else
            root.start();
    }

    function resetTimer() {
        root.stopAlarm();
        root.isRunning = false;
        root._deadlineMs = 0;
        root.isWorkSession = true;
        root.timeLeft = Config.system.pomodoro.workTime;
        root.totalTime = root.timeLeft;
    }

    function switchSession() {
        if (root.isRunning || root.alarmActive)
            return;
        root.isWorkSession = !root.isWorkSession;
        const configTime = root.isWorkSession ? Config.system.pomodoro.workTime : Config.system.pomodoro.restTime;
        root.timeLeft = configTime;
        root.totalTime = configTime;
    }

    function setSeconds(seconds: int) {
        const clamped = Math.max(0, Math.min(5999, seconds));
        root.timeLeft = clamped;
        if (root.isRunning) {
            root._deadlineMs = Date.now() + clamped * 1000;
        } else {
            root.totalTime = clamped;
            if (clamped > 0) {
                if (root.isWorkSession)
                    Config.system.pomodoro.workTime = clamped;
                else
                    Config.system.pomodoro.restTime = clamped;
            }
        }
    }

    function adjustSeconds(delta: int) {
        const next = root.timeLeft + delta;
        if (next < 0)
            return;
        root.setSeconds(next);
    }

    function startAlarm() {
        const finishedWork = root.isWorkSession;
        const finishedLabel = finishedWork ? "Work" : "Rest";
        if (finishedWork)
            root.completedCycles++;
        root.isRunning = false;
        root._deadlineMs = 0;
        root.alarmActive = true;
        root.blinkPhase = true;

        alarmSound.loops = Config.system.pomodoro.autoStart ? 2 : SoundEffect.Infinite;
        if (finishedWork || !(Config.system.pomodoro.syncSpotify && root.spotifyPlayer)) {
            alarmSound.play();
        } else if (Config.system.pomodoro.autoStart) {
            root.alarmActive = false;
        }

        if (Config.system.pomodoro.autoStart)
            root.nextSession();

        Notifications.notifyInternal({
            appName: "Pomodoro",
            summary: "Pomodoro",
            body: finishedLabel + " session finished!",
            replaceKey: "pomodoro-session",
            actions: [
                { identifier: "check", text: "Check" },
                { identifier: "stop", text: "Stop" }
            ],
            actionHandlers: {
                check: () => root.requestPopupOpen(),
                stop: () => {
                    root.stopAlarm();
                    root.pause();
                }
            }
        });
    }

    function stopAlarm() {
        alarmSound.stop();
        root.alarmActive = false;
        root.blinkPhase = false;
    }

    function nextSession() {
        root.isWorkSession = !root.isWorkSession;
        const configTime = root.isWorkSession ? Config.system.pomodoro.workTime : Config.system.pomodoro.restTime;
        root.timeLeft = configTime;
        root.totalTime = configTime;
        if (Config.system.pomodoro.autoStart) {
            root._deadlineMs = Date.now() + configTime * 1000;
            root.isRunning = true;
        }
    }

    SoundEffect {
        id: alarmSound
        source: Paths.assetUrl("sound/polite-warning-tone.wav")
        onPlayingChanged: {
            if (!playing && root.alarmActive && Config.system.pomodoro.autoStart)
                root.stopAlarm();
        }
    }

    Timer {
        interval: 250
        running: root.isRunning
        repeat: true
        onTriggered: {
            const remaining = Math.max(0, Math.ceil((root._deadlineMs - Date.now()) / 1000));
            if (remaining !== root.timeLeft)
                root.timeLeft = remaining;
            if (remaining <= 0)
                root.startAlarm();
        }
    }

    Timer {
        interval: 500
        running: root.alarmActive
        repeat: true
        onTriggered: root.blinkPhase = !root.blinkPhase
    }
}
