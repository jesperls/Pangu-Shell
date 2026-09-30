pragma Singleton

import QtQuick
import Quickshell
import qs.config

Singleton {
    id: root

    property bool enabled: false

    function toggle() {
        root.enabled = !root.enabled;
    }

    function minutesOf(timeStr, fallback) {
        const match = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(String(timeStr));
        return match ? Number(match[1]) * 60 + Number(match[2]) : fallback;
    }

    readonly property var schedule: boundaries()
    onScheduleChanged: if (enabled) apply()

    function boundaries() {
        const settings = Config.system.autoTheme;
        const useSun = settings?.useSunriseSunset ?? true;
        return {
            day: minutesOf(useSun && WeatherService.sunrise ? WeatherService.sunrise : settings?.dayStart, 480),
            night: minutesOf(useSun && WeatherService.sunset ? WeatherService.sunset : settings?.nightStart, 1200)
        };
    }

    function isLightAt(minute, day, night) {
        return day < night ? minute >= day && minute < night : day > night && (minute >= day || minute < night);
    }

    function nextBoundary(now, day, night) {
        return Math.min(...[day, night].map(minute => {
            let date = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, minute);
            if (date <= now)
                date = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, minute);
            return date.getTime();
        }));
    }

    function apply() {
        if (!root.enabled || SuspendManager.isSuspending)
            return;
        const now = new Date();
        const b = schedule;
        const wantLight = isLightAt(now.getHours() * 60 + now.getMinutes(), b.day, b.night);
        if (Config.initialLoadComplete && !Config.isPaused("theme") && !Config.isPaused("system") && Config.theme.lightMode !== wantLight) {
            Config.theme.lightMode = wantLight;
            Config.save("theme");
        }
        boundaryTimer.interval = Math.max(1000, nextBoundary(now, b.day, b.night) - now.getTime() + 1000);
        boundaryTimer.restart();
    }

    onEnabledChanged: {
        if (StateService.initialized)
            StateService.set("autoTheme", root.enabled);
        if (root.enabled)
            apply();
        else
            boundaryTimer.stop();
    }

    Timer {
        id: boundaryTimer
        repeat: false
        onTriggered: root.apply()
    }

    Connections {
        target: SuspendManager
        function onPreparingForSleep() {
            boundaryTimer.stop();
        }
        function onWakingUp() {
            if (root.enabled)
                root.apply();
        }
    }

    Connections {
        target: Config
        function onEditGroupsChanged() { root.apply(); }
        function onPauseAutoSaveChanged() { root.apply(); }
        function onInitialLoadCompleteChanged() {
            if (Config.initialLoadComplete && root.enabled)
                root.apply();
        }
    }

    Component.onCompleted: if (StateService.initialized) restore()

    function restore() {
        root.enabled = StateService.get("autoTheme", false);
        if (root.enabled)
            apply();
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            root.restore();
        }
    }
}
