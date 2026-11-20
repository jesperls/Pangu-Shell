pragma Singleton

import QtQuick
import Quickshell
import qs.modules.globals
import qs.modules.services
import qs.modules.theme
import qs.config

Singleton {
    id: root

    property string pendingConfirmId: ""

    Timer {
        id: confirmResetTimer
        interval: 5000
        repeat: false
        onTriggered: root.pendingConfirmId = ""
    }

    function clearConfirm() {
        confirmResetTimer.stop();
        root.pendingConfirmId = "";
    }

    function runWithConfirm(actionId, fn) {
        if (root.pendingConfirmId === actionId) {
            root.clearConfirm();
            fn();
            return false;
        }
        root.pendingConfirmId = actionId;
        confirmResetTimer.restart();
        return true; // Keep launcher open until confirmed.
    }

    function ocrLangString() {
        const cfg = Config.system.ocr;
        const langs = [];
        if (cfg.eng !== false)
            langs.push("eng");
        if (cfg.spa !== false)
            langs.push("spa");
        if (cfg.lat === true)
            langs.push("lat");
        if (cfg.jpn === true)
            langs.push("jpn");
        if (cfg.chi_sim === true)
            langs.push("chi_sim");
        if (cfg.chi_tra === true)
            langs.push("chi_tra");
        if (cfg.kor === true)
            langs.push("kor");
        if (langs.length === 0)
            langs.push("eng");
        return langs.join("+");
    }

    function buildActions() {
        const clipUrl = MediaGrabberService.clipboardMediaUrl;
        const mediaActions = clipUrl !== "" ? [
            {
                name: "Open Clipboard Link in PiP",
                icon: Icons.pictureInPicture,
                comment: "Float & pin " + MediaGrabberService.shortHost(clipUrl) + " in mpv",
                keywords: ["pip", "mpv", "video", "stream", "watch", "clipboard"],
                run: () => MediaGrabberService.openInPip(clipUrl)
            },
            {
                name: "Download Clipboard Video (MP4)",
                icon: Icons.downloadSimple,
                comment: "Save " + MediaGrabberService.shortHost(clipUrl) + " video to ~/Downloads",
                keywords: ["download", "yt-dlp", "mp4", "video", "grab", "save"],
                run: () => MediaGrabberService.downloadVideo(clipUrl)
            },
            {
                name: "Extract Clipboard Audio (MP3)",
                icon: Icons.musicNotes,
                comment: "Save " + MediaGrabberService.shortHost(clipUrl) + " audio to ~/Downloads",
                keywords: ["download", "yt-dlp", "mp3", "audio", "music", "extract"],
                run: () => MediaGrabberService.downloadAudio(clipUrl)
            }
        ] : [];
        return [
            ...mediaActions,
            {
                name: Notifications.silent ? "Do Not Disturb: Off" : "Do Not Disturb: On",
                icon: Icons.bellZ,
                comment: Notifications.silent ? "Resume notification popups" : "Silence notification popups",
                keywords: ["dnd", "silent", "mute", "notifications", "quiet"],
                run: () => Notifications.silent = !Notifications.silent
            },
            {
                name: CaffeineService.inhibit ? "Caffeine: Off" : "Caffeine: On",
                icon: Icons.caffeine,
                comment: CaffeineService.inhibit ? "Re-enable idle timeouts" : "Keep the system awake",
                keywords: ["idle", "inhibit", "awake", "coffee"],
                run: () => CaffeineService.toggleInhibit()
            },
            {
                name: NightLightService.active ? "Night Light: Off" : "Night Light: On",
                icon: Icons.nightLight,
                comment: "Toggle warm screen tint",
                keywords: ["warm", "redshift", "wlsunset", "blue light"],
                run: () => NightLightService.toggle()
            },
            {
                name: GameModeService.toggled ? "Game Mode: Off" : "Game Mode: On",
                icon: Icons.gameMode,
                comment: "Toggle game mode for the current workspace",
                keywords: ["gaming", "performance", "animations"],
                run: () => GameModeService.toggle()
            },
            {
                name: Config.theme.lightMode ? "Dark Mode" : "Light Mode",
                icon: Config.theme.lightMode ? Icons.moon : Icons.sun,
                comment: "Switch the theme and re-run matugen",
                keywords: ["theme", "dark", "light", "color"],
                run: () => {
                    Config.theme.lightMode = !Config.theme.lightMode;
                    Config.save("theme");
                }
            },
            {
                name: "Screenshot",
                icon: Icons.regionScreenshot,
                comment: "Capture a region, window or screen",
                keywords: ["capture", "grab", "print"],
                run: () => Screenshot.startCapture()
            },
            {
                name: ScreenRecorder.isRecording ? "Stop Recording" : "Screen Recorder",
                icon: ScreenRecorder.isRecording ? Icons.stop : Icons.recordScreen,
                comment: ScreenRecorder.isRecording ? "Recording " + ScreenRecorder.duration : "Record the screen",
                keywords: ["record", "video", "capture"],
                run: () => {
                    if (ScreenRecorder.isRecording) {
                        ScreenRecorder.toggleRecording();
                    } else {
                        ScreenRecorder.initialize();
                        GlobalStates.screenRecordReplayMode = false;
                        GlobalStates.screenRecordToolVisible = true;
                    }
                }
            },
            {
                name: ReplayService.active ? "Stop Replay Buffer" : "Replay Buffer",
                icon: ReplayService.active ? Icons.stop : Icons.rewind,
                comment: ReplayService.active ? "Stop the " + ReplayService.activeSeconds + "s replay buffer" : "Pick source, audio and length, then arm the buffer",
                keywords: ["replay", "buffer", "instant", "record"],
                run: () => {
                    if (ReplayService.active) {
                        ReplayService.stop();
                    } else {
                        ScreenRecorder.initialize();
                        GlobalStates.screenRecordReplayMode = true;
                        GlobalStates.screenRecordToolVisible = true;
                    }
                }
            },
            ...(ReplayService.active ? [{
                name: "Save Replay",
                icon: Icons.clip,
                comment: "Save the last " + ReplayService.activeSeconds + "s to a clip",
                keywords: ["clip", "replay", "save", "record"],
                run: () => ReplayService.saveClip()
            }] : []),
            {
                name: "Color Picker",
                icon: Icons.picker,
                comment: "Pick a color from the screen",
                keywords: ["pick", "hex", "eyedropper"],
                run: () => ApplicationLauncher.launchCommand(["python3", Paths.script("colorpicker.py")])
            },
            {
                name: "OCR",
                icon: Icons.textT,
                comment: "Copy text from a screen region",
                keywords: ["text", "tesseract", "read"],
                run: () => Screenshot.startCapture("ocr")
            },
            {
                name: "Scan QR Code",
                icon: Icons.qrCode,
                comment: "Decode a QR code from the screen",
                keywords: ["qr", "barcode", "scan"],
                run: () => Screenshot.startCapture("qr")
            },
            {
                name: "Google Lens",
                icon: Icons.google,
                comment: "Search a screen region with Lens",
                keywords: ["lens", "image search"],
                run: () => Screenshot.startCapture("lens")
            },
            {
                name: GlobalStates.mirrorWindowVisible ? "Close Mirror" : "Camera Mirror",
                icon: GlobalStates.mirrorWindowVisible ? Icons.webcamSlash : Icons.webcam,
                comment: "Toggle the webcam mirror window",
                keywords: ["webcam", "camera", "selfie"],
                run: () => GlobalStates.mirrorWindowVisible = !GlobalStates.mirrorWindowVisible
            },
            {
                name: "Settings",
                icon: Icons.gear,
                comment: "Open Pangu settings",
                keywords: ["config", "preferences", "options"],
                run: () => GlobalShortcuts.toggleSettings()
            },
            {
                name: "Macros & Hotkeys",
                icon: Icons.keyboard,
                comment: "Open the macro and hotkey editor",
                keywords: ["macros", "hotkeys", "automation", "uinput", "triggers"],
                run: () => GlobalShortcuts.toggleMacros()
            },
            {
                name: "Keybinds Cheatsheet",
                icon: Icons.keyboard,
                comment: "View active compositor keybinds",
                keywords: ["keybinds", "shortcuts", "cheatsheet", "help"],
                run: () => { GlobalStates.cheatsheetVisible = !GlobalStates.cheatsheetVisible; }
            },
            {
                name: "Workspace Overview",
                icon: Icons.overview,
                comment: "Show all workspaces and windows",
                keywords: ["overview", "expose", "windows", "workspaces"],
                run: () => GlobalShortcuts.toggleSimpleModule("overview")
            },
            {
                name: PomodoroService.isRunning ? "Pomodoro: Pause" : (PomodoroService.alarmActive ? "Pomodoro: Stop Alarm" : "Pomodoro: Start"),
                icon: Icons.timer,
                comment: (PomodoroService.isWorkSession ? "Work" : "Rest") + " · " + PomodoroService.formattedTime,
                keywords: ["pomodoro", "timer", "focus", "break", "work"],
                run: () => PomodoroService.toggleTimer()
            },
            {
                name: "Wallpapers",
                icon: Icons.wallpapers,
                comment: "Open the wallpaper browser",
                keywords: ["background", "theme"],
                run: () => GlobalShortcuts.toggleDashboardTab(1)
            },
            {
                name: "System Metrics",
                icon: Icons.heartbeat,
                comment: "CPU, GPU, RAM and disk usage",
                keywords: ["monitor", "cpu", "gpu", "ram", "usage"],
                run: () => GlobalShortcuts.toggleDashboardTab(2)
            },
            {
                name: "Clear Notifications",
                icon: Icons.broom,
                comment: "Dismiss the entire notification history",
                keywords: ["dismiss", "clean"],
                run: () => Notifications.discardAllNotifications()
            },
            ...PowerProfile.availableProfiles.map(profile => ({
                name: "Profile: " + PowerProfile.getProfileDisplayName(profile),
                icon: PowerProfile.getProfileIcon(profile),
                comment: PowerProfile.currentProfile === profile ? "Active power profile" : "Switch power profile",
                keywords: ["power", "profile", profile, ...(profile === "performance" ? ["fast"] : profile === "power-saver" ? ["battery", "save"] : [])],
                run: () => PowerProfile.setProfile(profile)
            })),
            {
                name: WallpaperSlideshowService.enabled ? "Slideshow: Off" : "Slideshow: On",
                icon: Icons.wallpapers,
                comment: WallpaperSlideshowService.enabled ? "Stop cycling wallpapers" : "Cycle wallpapers every " + WallpaperSlideshowService.intervalMinutes + " min",
                keywords: ["wallpaper", "slideshow", "cycle", "rotate", "auto"],
                run: () => WallpaperSlideshowService.toggle()
            },
            {
                name: "Next Wallpaper",
                icon: Icons.shuffle,
                comment: "Advance to another wallpaper",
                keywords: ["wallpaper", "next", "shuffle", "random"],
                run: () => WallpaperSlideshowService.next()
            },
            {
                name: AutoThemeService.enabled ? "Auto Theme: Off" : "Auto Theme: On",
                icon: Icons.circleHalf,
                comment: "Switch light and dark with the sun",
                keywords: ["theme", "auto", "sunrise", "sunset", "light", "dark"],
                run: () => AutoThemeService.toggle()
            },
            {
                name: "Lock Screen",
                icon: Icons.lock,
                comment: "Lock the session",
                keywords: ["lock", "away"],
                run: () => LockscreenService.lock()
            },
            {
                name: "Suspend",
                icon: Icons.suspend,
                comment: "Suspend to RAM",
                keywords: ["sleep", "zzz"],
                run: () => Quickshell.execDetached(["systemctl", "suspend"])
            },
            {
                name: "Reload Shell",
                icon: Icons.arrowCounterClockwise,
                comment: "Restart pangu.service",
                keywords: ["restart", "pangu", "shell"],
                run: () => Quickshell.execDetached(["systemctl", "--user", "restart", "pangu.service"])
            },
            {
                id: "reboot",
                name: root.pendingConfirmId === "reboot" ? "Confirm Reboot" : "Reboot",
                icon: Icons.reboot,
                comment: root.pendingConfirmId === "reboot" ? "Press Enter again to reboot now" : "Restart the system",
                keywords: ["restart", "system", "reboot"],
                confirm: true,
                run: () => root.runWithConfirm("reboot", () => Quickshell.execDetached(["systemctl", "reboot"]))
            },
            {
                id: "poweroff",
                name: root.pendingConfirmId === "poweroff" ? "Confirm Power Off" : "Power Off",
                icon: Icons.shutdown,
                comment: root.pendingConfirmId === "poweroff" ? "Press Enter again to shut down now" : "Shut the system down",
                keywords: ["shutdown", "halt", "poweroff"],
                confirm: true,
                run: () => root.runWithConfirm("poweroff", () => Quickshell.execDetached(["systemctl", "poweroff"]))
            }
        ];
    }

    function score(action, query) {
        const name = action.name.toLowerCase();
        if (name.startsWith(query))
            return 100;
        if (name.includes(query))
            return 70;
        for (const keyword of action.keywords) {
            if (keyword.startsWith(query))
                return 50;
            if (keyword.includes(query))
                return 40;
        }
        if (action.comment.toLowerCase().includes(query))
            return 20;
        return 0;
    }

    function query(text) {
        const q = text.toLowerCase().trim();
        let actions = buildActions();
        if (q.length > 0) {
            actions = actions.map(action => ({
                action,
                rank: score(action, q)
            })).filter(scored => scored.rank > 0).sort((a, b) => b.rank - a.rank).map(scored => scored.action);
        }
        return actions.map(action => ({
            id: "action:" + (action.id || action.name),
            name: action.name,
            icon: "font:" + action.icon,
            comment: action.comment,
            execString: "",
            categories: [],
            runInTerminal: false,
            isAction: true,
            confirm: action.confirm === true,
            execute: action.run
        }));
    }
}
