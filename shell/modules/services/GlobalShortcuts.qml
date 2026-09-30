pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.globals
import qs.modules.services
import qs.config

import Quickshell.Io

QtObject {
    id: root

    readonly property string appId: "pangu"

    readonly property real mediaSeekStep: 5

    function run(command) {
        if (command.startsWith("macros-run ")) {
            MacroService.run(command.slice(11).trim());
            return;
        }
        if (command.startsWith("macros-seq ")) {
            const parts = command.split(/\s+/);
            MacroService.sequenceStep(parts[1], parseInt(parts[2], 10));
            return;
        }
        switch (command) {
            case "launcher": toggleLauncher(); break;
            case "clipboard": toggleLauncherWithPrefix(1, Config.prefix.clipboard + " "); break;
            case "emoji": toggleLauncherWithPrefix(2, Config.prefix.emoji + " "); break;
            case "tmux": toggleLauncherWithPrefix(3, Config.prefix.tmux + " "); break;
            case "notes": toggleLauncherWithPrefix(4, Config.prefix.notes + " "); break;

            case "dashboard": toggleDashboardTab(0); break;
            case "wallpapers": toggleDashboardTab(1); break;
            case "dashboard-widgets": toggleDashboardTab(0); break;
            case "dashboard-wallpapers": toggleDashboardTab(1); break;
            case "dashboard-metrics": toggleDashboardTab(2); break;
            case "dashboard-controls": toggleSettings(); break;

            case "overview": toggleSimpleModule("overview"); break;
            case "powermenu": toggleSimpleModule("powermenu"); break;
            case "tools": toggleSimpleModule("tools"); break;
            case "config": toggleSettings(); break;
            case "settings": toggleSettings(); break;
            case "screenshot": Screenshot.initialize(); GlobalStates.screenshotToolVisible = true; break;
            case "screenrecord": ScreenRecorder.initialize(); GlobalStates.screenRecordReplayMode = false; GlobalStates.screenRecordToolVisible = true; break;
            case "lens": 
                Screenshot.initialize();
                Screenshot.captureMode = "lens";
                GlobalStates.screenshotToolVisible = true;
                break;
            case "mirror": GlobalStates.mirrorWindowVisible = !GlobalStates.mirrorWindowVisible; break;
            case "cheatsheet": GlobalStates.cheatsheetVisible = !GlobalStates.cheatsheetVisible; break;
            case "macros": toggleMacros(); break;
            case "macros-stop": MacroService.stop(); break;
            case "lockscreen": LockscreenService.lock(); break;
            case "gamemode": GameModeService.toggle(); break;
            case "dnd": Notifications.silent = !Notifications.silent; break;
            case "caffeine": CaffeineService.toggleInhibit(); break;
            case "nightlight": NightLightService.toggle(); break;
            case "slideshow": WallpaperSlideshowService.toggle(); break;
            case "wallpaper-next": WallpaperSlideshowService.next(); break;
            case "autotheme": AutoThemeService.toggle(); break;
            case "replay":
                if (ReplayService.active) {
                    ReplayService.stop();
                } else {
                    ScreenRecorder.initialize();
                    GlobalStates.screenRecordReplayMode = true;
                    GlobalStates.screenRecordToolVisible = true;
                }
                break;
            case "replay-quick": ReplayService.toggle(); break;
            case "replay-save": ReplayService.saveClip(); break;
            case "screen-on": Compositor.dispatch("dpms on"); break;
            case "screen-off": Compositor.dispatch("dpms off"); break;
            
            case "media-seek-backward": seekActivePlayer(-root.mediaSeekStep); break;
            case "media-seek-forward": seekActivePlayer(root.mediaSeekStep); break;
            case "media-play-pause": 
                if (MprisController.canTogglePlaying) MprisController.togglePlaying();
                break;
            case "media-next": MprisController.next(); break;
            case "media-prev": MprisController.previous(); break;
                
            default: console.warn("Unknown IPC command:", command);
        }
    }

    property IpcHandler ipcHandler: IpcHandler {
        target: "pangu"

        function run(command: string) {
            root.run(command);
        }
    }

    function toggleMacros(screenName) {
        const willOpen = !GlobalStates.macrosWindowVisible;
        if (willOpen) {
            const targetMonitor = screenName ? Compositor.monitorFor(screenName) : Compositor.focusedMonitor;
            GlobalStates.macrosTargetWorkspaceId = targetMonitor?.activeWorkspace?.id || Compositor.focusedMonitor?.activeWorkspace?.id || Compositor.focusedWorkspace?.id || 0;
            GlobalStates.macrosTargetScreenName = targetMonitor?.name || Compositor.focusedMonitor?.name || "";
            if (targetMonitor && targetMonitor.id !== Compositor.focusedMonitor?.id)
                Compositor.dispatch(`focusmonitor ${targetMonitor.id}`);
            Qt.callLater(() => Visibilities.setActiveModule(""));
        }
        GlobalStates.macrosWindowVisible = willOpen;
    }

    function toggleSettings(screenName) {
        const willOpen = !GlobalStates.settingsWindowVisible;
        if (willOpen) {
            const targetMonitor = screenName ? Compositor.monitorFor(screenName) : Compositor.focusedMonitor;
            GlobalStates.settingsTargetWorkspaceId = targetMonitor?.activeWorkspace?.id || Compositor.focusedMonitor?.activeWorkspace?.id || Compositor.focusedWorkspace?.id || 0;
            GlobalStates.settingsTargetScreenName = targetMonitor?.name || Compositor.focusedMonitor?.name || "";
            if (targetMonitor && targetMonitor.id !== Compositor.focusedMonitor?.id) {
                Compositor.dispatch(`focusmonitor ${targetMonitor.id}`);
            }
            Qt.callLater(() => Visibilities.setActiveModule(""));
        }
        GlobalStates.settingsWindowVisible = willOpen;
    }

    function toggleSimpleModule(moduleName) {
        if (Visibilities.isActiveOnFocusedScreen(moduleName)) {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule(moduleName);
        }
    }

    function toggleLauncher() {
        const isActive = Visibilities.isActiveOnFocusedScreen("launcher");
        if (isActive && GlobalStates.widgetsTabCurrentIndex === 0 && GlobalStates.launcherSearchText === "") {
            Visibilities.setActiveModule("");
        } else {
            GlobalStates.widgetsTabCurrentIndex = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("launcher");
            }
        }
    }

    function toggleLauncherWithPrefix(tabIndex, prefix) {
        const isActive = Visibilities.isActiveOnFocusedScreen("launcher");
        const currentTab = GlobalStates.widgetsTabCurrentIndex;
        const currentText = GlobalStates.launcherSearchText;

        if (isActive && currentTab === tabIndex && (currentText === prefix || currentText === "")) {
            Visibilities.setActiveModule("");
            GlobalStates.clearLauncherState();
            return;
        }

        GlobalStates.widgetsTabCurrentIndex = tabIndex;
        GlobalStates.launcherSearchText = prefix;
        
        if (!isActive) {
            Visibilities.setActiveModule("launcher");
        }
    }

    function toggleDashboardTab(tabIndex) {
        const isActive = Visibilities.isActiveOnFocusedScreen("dashboard");
        
        if (tabIndex === 0) {
            if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === "") {
                Visibilities.setActiveModule("");
                return;
            }
            
            GlobalStates.dashboardCurrentTab = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("dashboard");
            }
            return;
        }
        
        if (isActive && GlobalStates.dashboardCurrentTab === tabIndex) {
            Visibilities.setActiveModule("");
            return;
        }

        GlobalStates.dashboardCurrentTab = tabIndex;
        if (!isActive) {
            Visibilities.setActiveModule("dashboard");
        }
    }

    function seekActivePlayer(offset) {
        const player = MprisController.activePlayer;
        if (!player || !player.canSeek) {
            return;
        }

        const maxLength = typeof player.length === "number" && !isNaN(player.length)
                ? player.length
                : Number.MAX_SAFE_INTEGER;
        const clamped = Math.max(0, Math.min(maxLength, player.position + offset));
        player.position = clamped;
    }
}
