pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.components

Singleton {
    id: root

    readonly property string lockCmd: Config.system.idle.general.lock_cmd
    readonly property string beforeSleepCmd: Config.system.idle.general.before_sleep_cmd
    readonly property string settings: JSON.stringify(Config.system.idle)
    property var activeListeners: []
    property var pendingListeners: []
    property var triggered: ({})
    property int generation: 0
    property bool writing: false
    property bool configReady: false
    property string writtenSettings: ""

    readonly property var effectiveListeners: {
        const idle = Config.system.idle;
        if (idle.enabled !== true)
            return [];
        const composed = [];
        if (idle.lock.enabled && idle.lock.timeout > 0)
            composed.push({
                timeout: idle.lock.timeout,
                onTimeout: root.lockCmd
            });
        if (idle.screenOff.enabled && idle.screenOff.timeout > 0)
            composed.push({
                timeout: idle.screenOff.timeout,
                onTimeout: "pangu screen off",
                onResume: "pangu screen on"
            });
        if (idle.suspend.enabled && idle.suspend.timeout > 0)
            composed.push({
                timeout: idle.suspend.timeout,
                onTimeout: "pangu suspend"
            });
        return composed.concat(idle.listeners || []);
    }

    function executeCommand(command) {
        if (typeof command === "string" && command) Quickshell.execDetached(["sh", "-c", command]);
    }

    function renderConfig(listeners, revision) {
        let text = "general {\n  lock_cmd = pangu idle lock\n"
            + "  before_sleep_cmd = pangu idle beforeSleep\n"
            + "  after_sleep_cmd = pangu idle afterSleep\n"
            + "  inhibit_sleep = 3\n}\n";
        listeners.forEach((listener, index) => {
            text += "listener {\n  timeout = " + listener.timeout
                + "\n  on-timeout = pangu idle timeout " + revision + " " + index
                + "\n  on-resume = pangu idle resume " + revision + " " + index + "\n}\n";
        });
        return text;
    }

    function resumeAll() {
        const commands = root.triggered;
        root.triggered = {};
        Object.keys(commands).reverse().forEach(index => root.executeCommand(commands[index]));
    }

    function handleTimeout(revision, index) {
        if (revision !== root.generation || CaffeineService.inhibit || SuspendManager.isSuspending) return;
        const listener = root.activeListeners[index];
        if (!listener || Object.prototype.hasOwnProperty.call(root.triggered, index)) return;
        root.triggered[index] = listener.onResume || "";
        root.executeCommand(listener.onTimeout);
    }

    function handleResume(revision, index) {
        if (revision !== root.generation || !Object.prototype.hasOwnProperty.call(root.triggered, index)) return;
        const command = root.triggered[index];
        delete root.triggered[index];
        root.executeCommand(command);
    }

    function configure() {
        if (!Config.initialLoadComplete || Config.isPaused("system") || root.writing) return;
        root.pendingListeners = root.effectiveListeners.filter(listener =>
            listener && Number.isInteger(listener.timeout) && listener.timeout > 0 && listener.timeout <= 2147483)
            .map(listener => ({timeout: listener.timeout, onTimeout: listener.onTimeout, onResume: listener.onResume}));
        root.writtenSettings = root.settings;
        root.writing = true;
        configFile.write(root.renderConfig(root.pendingListeners, root.generation + 1));
    }

    onSettingsChanged: Qt.callLater(root.configure)
    Connections {
        target: Config
        function onInitialLoadCompleteChanged() { root.configure(); }
        function onEditGroupsChanged() {
            if (!Config.isPaused("system") && root.settings !== root.writtenSettings) root.configure();
        }
        function onPauseAutoSaveChanged() {
            if (!Config.isPaused("system") && root.settings !== root.writtenSettings) root.configure();
        }
    }
    Connections {
        target: CaffeineService
        function onInhibitChanged() { if (CaffeineService.inhibit) root.resumeAll(); }
    }
    Component.onCompleted: configure()

    GeneratedFile {
        id: configFile
        path: Paths.runtimePath("hypridle.conf")
        onWritten: {
            root.writing = false;
            if (root.settings !== root.writtenSettings) {
                root.configure();
                return;
            }
            root.resumeAll();
            root.activeListeners = root.pendingListeners;
            root.generation++;
            root.configReady = true;
            if (daemon.running) daemon.running = false;
            else daemon.running = true;
        }
        onFailed: root.writing = false
    }
    Process {
        id: daemon
        command: ["hypridle", "-q", "-c", configFile.path]
        onExited: {
            root.resumeAll();
            restartTimer.restart();
        }
    }
    Timer {
        id: restartTimer
        interval: 1000
        onTriggered: if (root.configReady) daemon.running = true
    }

    IpcHandler {
        target: "idle"
        function lock(): void { root.executeCommand(root.lockCmd); }
        function beforeSleep(): void {
            SuspendManager.onPrepareForSleep();
            const command = root.beforeSleepCmd.trim();
            if (["loginctl lock-session", "loginctl lock-sessions", "pangu lock"].includes(command))
                LockscreenService.lock();
            else
                root.executeCommand(command);
        }
        function afterSleep(): void {
            SuspendManager.onWakingUp();
            root.executeCommand(Config.system.idle.general.after_sleep_cmd);
        }
        function timeout(revision: int, index: int): void { root.handleTimeout(revision, index); }
        function resume(revision: int, index: int): void { root.handleResume(revision, index); }
    }
}
