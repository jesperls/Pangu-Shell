pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "SettingsData.js" as SettingsData

Singleton {
    id: root

    readonly property string version: Quickshell.env("PANGU_VERSION") || "dev"

    readonly property string configDir: Paths.configPath("config")

    property var nixOverridePaths: []

    FileView {
        path: Quickshell.env("PANGU_NIX_OVERRIDES") || ""
        onLoaded: {
            try {
                const paths = JSON.parse(text() || "[]");
                root.nixOverridePaths = Array.isArray(paths) ? paths.filter(p => typeof p === "string") : [];
            } catch (error) {
                root.nixOverridePaths = [];
            }
        }
        onLoadFailed: root.nixOverridePaths = []
    }

    property bool pauseAutoSave: false
    property var editGroups: ({})

    function beginEdit(group, names) {
        root.editGroups = Object.assign({}, root.editGroups, {[group]: names.slice()});
    }

    function endEdit(group) {
        const groups = Object.assign({}, root.editGroups);
        delete groups[group];
        root.editGroups = groups;
    }

    function isPaused(name) {
        return root.pauseAutoSave || Object.values(root.editGroups).some(names => names.includes(name));
    }

    readonly property var files: ({
        theme: themeFile,
        bar: barFile,
        workspaces: workspacesFile,
        overview: overviewFile,
        notch: notchFile,
        compositor: compositorFile,
        performance: performanceFile,
        weather: weatherFile,
        lockscreen: lockscreenFile,
        prefix: prefixFile,
        system: systemFile,
        dock: dockFile,
        pinnedapps: pinnedAppsFile,
        osd: osdFile,
        dashboard: dashboardFile,
        launcher: launcherFile,
        macros: macrosFile
    })

    readonly property bool initialLoadComplete: themeFile.ready && barFile.ready && workspacesFile.ready && overviewFile.ready && notchFile.ready && compositorFile.ready && performanceFile.ready && weatherFile.ready && lockscreenFile.ready && prefixFile.ready && systemFile.ready && dockFile.ready && pinnedAppsFile.ready && osdFile.ready && dashboardFile.ready && launcherFile.ready && macrosFile.ready

    readonly property bool barReady: barFile.ready
    readonly property bool dockReady: dockFile.ready

    function adapterKeys(name) {
        const section = root.files[name]?.adapter;
        if (!section) return [];
        return SettingsData.keys(section);
    }

    function snapshot(name) {
        return SettingsData.copy(root.files[name]?.adapter || {});
    }

    function restore(name, values) {
        SettingsData.assign(values, root.files[name]?.adapter);
    }

    function save(name) {
        const file = root.files[name];
        if (file)
            file.writeAdapter();
    }

    Process {
        command: ["mkdir", "-p", root.configDir, Paths.dataDir, Paths.cacheDir]
        running: true
        onExited: exitCode => {
            if (exitCode !== 0) return;
            for (const name in root.files)
                root.files[name].reloadConfig();
        }
    }

    ConfigFile {
        id: themeFile
        name: "theme"

        adapter: JsonAdapter {
            property bool oledMode: false
            property bool lightMode: false
            property bool dynamicColors: true
            property int roundness: 16
            property string font: "Inter"
            property int fontSize: 14
            property string monoFont: "Iosevka Nerd Font Mono"
            property int monoFontSize: 14
            property bool tintIcons: false
            property bool enableCorners: true
            property int animDuration: 300
            property real shadowOpacity: 0.5
            property string shadowColor: "shadow"
            property int shadowXOffset: 0
            property int shadowYOffset: 0
            property real shadowBlur: 1

            property JsonObject srBg: JsonObject {
                property string label: "Background"
                property list<var> gradient: [["background", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "surface"
                property string halftoneBackgroundColor: "background"
                property list<var> border: ["surfaceBright", 0]
                property string itemColor: "overBackground"
                property real opacity: 1.0
            }

            property JsonObject srPopup: JsonObject {
                property string label: "Popup"
                property list<var> gradient: [["surface", 0.0], ["surfaceDim", 1.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "surface"
                property string halftoneBackgroundColor: "background"
                property list<var> border: ["surfaceBright", 2]
                property string itemColor: "overBackground"
                property real opacity: 1.0
            }

            property JsonObject srInternalBg: JsonObject {
                property string label: "Internal BG"
                property list<var> gradient: [["background", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "surface"
                property string halftoneBackgroundColor: "background"
                property list<var> border: ["surfaceBright", 0]
                property string itemColor: "overBackground"
                property real opacity: 1.0
            }

            property JsonObject srBarBg: JsonObject {
                property string label: "Bar BG"
                property list<var> gradient: [["surfaceDim", 0.0], ["surfaceContainerLow", 1.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "surface"
                property string halftoneBackgroundColor: "surfaceDim"
                property list<var> border: ["surfaceBright", 0]
                property string itemColor: "overBackground"
                property real opacity: 1.0
            }

            property JsonObject srPane: JsonObject {
                property string label: "Pane"
                property list<var> gradient: [["surface", 0.0], ["surfaceContainerLow", 1.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "surfaceBright"
                property string halftoneBackgroundColor: "surface"
                property list<var> border: ["surfaceBright", 0]
                property string itemColor: "overBackground"
                property real opacity: 1.0
            }

            property JsonObject srCommon: JsonObject {
                property string label: "Common"
                property list<var> gradient: [["surface", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "background"
                property string halftoneBackgroundColor: "surface"
                property list<var> border: ["surfaceBright", 0]
                property string itemColor: "overBackground"
                property real opacity: 1.0
            }

            property JsonObject srFocus: JsonObject {
                property string label: "Focus"
                property list<var> gradient: [["surfaceBright", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "surfaceVariant"
                property string halftoneBackgroundColor: "surfaceBright"
                property list<var> border: ["surfaceBright", 0]
                property string itemColor: "overBackground"
                property real opacity: 1.0
            }

            property JsonObject srPrimary: JsonObject {
                property string label: "Primary"
                property list<var> gradient: [["primary", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "overPrimaryContainer"
                property string halftoneBackgroundColor: "primary"
                property list<var> border: ["primary", 0]
                property string itemColor: "overPrimary"
                property real opacity: 1.0
            }

            property JsonObject srPrimaryFocus: JsonObject {
                property string label: "Primary Focus"
                property list<var> gradient: [["overPrimaryContainer", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "primary"
                property string halftoneBackgroundColor: "overPrimaryContainer"
                property list<var> border: ["overBackground", 0]
                property string itemColor: "overPrimary"
                property real opacity: 1.0
            }

            property JsonObject srOverPrimary: JsonObject {
                property string label: "Over Primary"
                property list<var> gradient: [["overPrimary", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "primaryContainer"
                property string halftoneBackgroundColor: "overPrimary"
                property list<var> border: ["overPrimary", 0]
                property string itemColor: "primary"
                property real opacity: 1.0
            }

            property JsonObject srSecondary: JsonObject {
                property string label: "Secondary"
                property list<var> gradient: [["secondary", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "overSecondaryContainer"
                property string halftoneBackgroundColor: "secondary"
                property list<var> border: ["secondary", 0]
                property string itemColor: "overSecondary"
                property real opacity: 1.0
            }

            property JsonObject srSecondaryFocus: JsonObject {
                property string label: "Secondary Focus"
                property list<var> gradient: [["overSecondaryContainer", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "secondary"
                property string halftoneBackgroundColor: "overSecondaryContainer"
                property list<var> border: ["overBackground", 0]
                property string itemColor: "overSecondary"
                property real opacity: 1.0
            }

            property JsonObject srOverSecondary: JsonObject {
                property string label: "Over Secondary"
                property list<var> gradient: [["overSecondary", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "secondaryContainer"
                property string halftoneBackgroundColor: "overSecondary"
                property list<var> border: ["overSecondary", 0]
                property string itemColor: "secondary"
                property real opacity: 1.0
            }

            property JsonObject srTertiary: JsonObject {
                property string label: "Tertiary"
                property list<var> gradient: [["tertiary", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "overTertiaryContainer"
                property string halftoneBackgroundColor: "tertiary"
                property list<var> border: ["tertiary", 0]
                property string itemColor: "overTertiary"
                property real opacity: 1.0
            }

            property JsonObject srTertiaryFocus: JsonObject {
                property string label: "Tertiary Focus"
                property list<var> gradient: [["overTertiaryContainer", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "tertiary"
                property string halftoneBackgroundColor: "overTertiaryContainer"
                property list<var> border: ["overBackground", 0]
                property string itemColor: "overTertiary"
                property real opacity: 1.0
            }

            property JsonObject srOverTertiary: JsonObject {
                property string label: "Over Tertiary"
                property list<var> gradient: [["overTertiary", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "tertiaryContainer"
                property string halftoneBackgroundColor: "overTertiary"
                property list<var> border: ["overTertiary", 0]
                property string itemColor: "tertiary"
                property real opacity: 1.0
            }

            property JsonObject srError: JsonObject {
                property string label: "Error"
                property list<var> gradient: [["error", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "overErrorContainer"
                property string halftoneBackgroundColor: "error"
                property list<var> border: ["error", 0]
                property string itemColor: "overError"
                property real opacity: 1.0
            }

            property JsonObject srErrorFocus: JsonObject {
                property string label: "Error Focus"
                property list<var> gradient: [["overBackground", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "error"
                property string halftoneBackgroundColor: "overErrorContainer"
                property list<var> border: ["overBackground", 0]
                property string itemColor: "overError"
                property real opacity: 1.0
            }

            property JsonObject srOverError: JsonObject {
                property string label: "Over Error"
                property list<var> gradient: [["overError", 0.0]]
                property string gradientType: "linear"
                property int gradientAngle: 0
                property real gradientCenterX: 0.5
                property real gradientCenterY: 0.5
                property real halftoneDotMin: 0.0
                property real halftoneDotMax: 2.0
                property real halftoneStart: 0.0
                property real halftoneEnd: 1.0
                property string halftoneDotColor: "errorContainer"
                property string halftoneBackgroundColor: "overError"
                property list<var> border: ["overError", 0]
                property string itemColor: "error"
                property real opacity: 1.0
            }
        }
    }

    ConfigFile {
        id: barFile
        name: "bar"

        adapter: JsonAdapter {
            property string position: "top"
            property int height: 0
            property string style: "floating"
            property int margin: 4
            property int spacing: 4
            property int padding: 4
            property string launcherIcon: ""
            property bool launcherIconTint: false
            property bool launcherIconFullTint: false
            property int launcherIconSize: 24
            property string pillStyle: "default"
            property string clockPosition: "right"
            property string launcherPosition: "start"
            property bool flatButtons: false
            property bool showWorkspaces: true
            property list<string> screenList: []
            property bool enableFirefoxPlayer: false
            property bool frameEnabled: false
            property int frameThickness: 6
            property bool pinnedOnStartup: true
            property bool hoverToReveal: true
            property int hoverRegionHeight: 8
            property int hideDelay: 1000
            property bool showPinButton: true
            property bool availableOnFullscreen: false
            property bool use12hFormat: false
            property bool showSeconds: false
            property bool showDate: false
            property bool containBar: false
            property bool keepBarShadow: false
            property bool keepBarBorder: false
            property bool splitOnCenteredLayout: true
            property int splitGapPadding: 4
        }
    }

    ConfigFile {
        id: workspacesFile
        name: "workspaces"

        adapter: JsonAdapter {
            property int shown: 10
            property bool showAppIcons: true
            property bool alwaysShowNumbers: false
            property bool showNumbers: false
            property bool dynamic: false
        }
    }

    ConfigFile {
        id: overviewFile
        name: "overview"

        adapter: JsonAdapter {
            property bool enabled: true
            property string layout: "standard"
            property int rows: 2
            property int columns: 5
            property real scale: 0.1
            property real workspaceSpacing: 4
        }
    }

    ConfigFile {
        id: notchFile
        name: "notch"

        adapter: JsonAdapter {
            property string theme: "default"
            property string position: "top"
            property int hoverRegionHeight: 8
            property int hideDelay: 1000
            property int hoverExpansionDelay: 400
            property bool showUser: true
            property bool showMedia: true
            property bool showNotificationIndicator: true
            property bool keepHidden: false
            property string noMediaDisplay: "userHost"
            property string customText: "Pangu"
            property bool disableHoverExpansion: false
            property string splitSide: "left"
        }
    }

    ConfigFile {
        id: compositorFile
        name: "compositor"

        adapter: JsonAdapter {
            property var activeBorderColor: ["primary"]
            property int borderAngle: 45
            property var inactiveBorderColor: ["surface"]
            property int inactiveBorderAngle: 45
            property int borderSize: 2
            property int rounding: 16
            property bool syncRoundness: true
            property bool syncBorderWidth: false
            property bool syncBorderColor: false
            property bool syncShadowOpacity: false
            property bool syncShadowColor: false
            property int gapsIn: 2
            property int gapsOut: 4
            property bool shadowEnabled: true
            property int shadowRange: 8
            property int shadowRenderPower: 3
            property bool shadowSharp: false
            property string shadowColor: "shadow"
            property string shadowColorInactive: "shadow"
            property real shadowOpacity: 0.5
            property string shadowOffset: "0 0"
            property real shadowScale: 1.0
            property bool blurEnabled: true
            property int blurSize: 4
            property int blurPasses: 2
            property bool blurIgnoreOpacity: true
            property bool blurExplicitIgnoreAlpha: false
            property real blurIgnoreAlphaValue: 0.2
            property bool blurNewOptimizations: true
            property bool blurXray: false
            property real blurNoise: 0.0
            property real blurContrast: 1.0
            property real blurBrightness: 1.0
            property real blurVibrancy: 0.0
            property real blurVibrancyDarkness: 0.0
            property bool blurSpecial: true
            property bool blurPopups: false
            property real blurPopupsIgnorealpha: 0.2
            property bool blurInputMethods: false
            property real blurInputMethodsIgnorealpha: 0.2
        }
    }

    ConfigFile {
        id: performanceFile
        name: "performance"

        adapter: JsonAdapter {
            property bool blurTransition: true
            property bool windowPreview: true
            property bool wavyLine: true
            property bool rotateCoverArt: true
            property bool audioVisualizer: true
            property bool dashboardPersistTabs: true
            property int dashboardMaxPersistentTabs: 2
        }
    }

    ConfigFile {
        id: weatherFile
        name: "weather"

        adapter: JsonAdapter {
            property string location: ""
            property string unit: "C"
        }
    }

    ConfigFile {
        id: lockscreenFile
        name: "lockscreen"

        adapter: JsonAdapter {
            property string position: "bottom"
            property bool lockOnBoot: false
            property bool showClock: true
            property bool showDate: true
            property bool showMediaPlayer: true
            property bool showAvatar: true
            property bool showUsername: true
            property bool blurWallpaper: true
            property int dimOpacity: 25
        }
    }

    ConfigFile {
        id: prefixFile
        name: "prefix"

        adapter: JsonAdapter {
            property string clipboard: "cc"
            property string emoji: "ee"
            property string tmux: "tt"
            property string wallpapers: "ww"
            property string notes: "nn"
        }
    }

    ConfigFile {
        id: systemFile
        name: "system"

        adapter: JsonAdapter {
            property list<string> disks: ["/"]
            property JsonObject idle: JsonObject {
                property bool enabled: false
                property JsonObject general: JsonObject {
                    property string lock_cmd: "pangu lock"
                    property string before_sleep_cmd: "loginctl lock-session"
                    property string after_sleep_cmd: "pangu screen on"
                }
                property JsonObject lock: JsonObject {
                    property bool enabled: true
                    property int timeout: 300
                }
                property JsonObject screenOff: JsonObject {
                    property bool enabled: true
                    property int timeout: 330
                }
                property JsonObject suspend: JsonObject {
                    property bool enabled: false
                    property int timeout: 1800
                }
                property list<var> listeners: []
            }
            property JsonObject ocr: JsonObject {
                property bool eng: true
                property bool spa: true
                property bool lat: false
                property bool jpn: false
                property bool chi_sim: false
                property bool chi_tra: false
                property bool kor: false
            }
            property JsonObject pomodoro: JsonObject {
                property int workTime: 1500
                property int restTime: 300
                property bool autoStart: false
                property bool syncSpotify: false
            }
            property JsonObject replay: JsonObject {
                property int seconds: 60
            }
            property JsonObject nightLight: JsonObject {
                property int temperature: 4500
            }
            property JsonObject slideshow: JsonObject {
                property int minutes: 30
            }
            property JsonObject autoTheme: JsonObject {
                property bool useSunriseSunset: true
                property string dayStart: "08:00"
                property string nightStart: "20:00"
            }
        }
    }

    ConfigFile {
        id: dockFile
        name: "dock"

        adapter: JsonAdapter {
            property bool enabled: false
            property string theme: "default"
            property string position: "bottom"
            property int height: 56
            property int iconSize: 40
            property int spacing: 4
            property int margin: 8
            property int hoverRegionHeight: 8
            property int hideDelay: 1000
            property bool pinnedOnStartup: false
            property bool hoverToReveal: true
            property bool availableOnFullscreen: false
            property bool showRunningIndicators: true
            property bool showPinButton: true
            property bool showOverviewButton: true
            property list<string> ignoredAppRegexes: ["quickshell.*", "xdg-desktop-portal.*"]
            property list<string> screenList: []
            property bool keepHidden: false
        }
    }

    ConfigFile {
        id: pinnedAppsFile
        name: "pinnedapps"
        path: Paths.dataPath("pinnedapps.json")

        adapter: JsonAdapter {
            property list<string> apps: ["kitty"]
        }
    }

    ConfigFile {
        id: osdFile
        name: "osd"

        adapter: JsonAdapter {
            property string position: "bottom"
            property bool showPercentage: true
            property bool showSlider: true
            property string iconStyle: "chip"
            property int width: 260
        }
    }

    ConfigFile {
        id: dashboardFile
        name: "dashboard"

        adapter: JsonAdapter {
            property int width: 0
            property int height: 0
            property bool showTabRail: true
            property string tabPosition: "left"
            property bool showWidgets: true
            property bool showWallpapers: true
            property bool showMetrics: true
            property real backgroundOpacity: 1.0
        }
    }

    ConfigFile {
        id: launcherFile
        name: "launcher"

        adapter: JsonAdapter {
            property int width: 0
            property int height: 0
            property bool showAppComments: true
            property bool sortByUsage: true
        }
    }

    ConfigFile {
        id: macrosFile
        name: "macros"

        adapter: JsonAdapter {
            property bool enabled: true
            property list<var> macros: []
        }
    }

    readonly property QtObject theme: themeFile.adapter
    readonly property QtObject bar: barFile.adapter
    readonly property QtObject workspaces: workspacesFile.adapter
    readonly property QtObject overview: overviewFile.adapter
    readonly property QtObject notch: notchFile.adapter
    readonly property QtObject compositor: compositorFile.adapter
    readonly property QtObject performance: performanceFile.adapter
    readonly property QtObject weather: weatherFile.adapter
    readonly property QtObject lockscreen: lockscreenFile.adapter
    readonly property QtObject prefix: prefixFile.adapter
    readonly property QtObject system: systemFile.adapter
    readonly property QtObject dock: dockFile.adapter
    readonly property QtObject pinnedApps: pinnedAppsFile.adapter
    readonly property QtObject osd: osdFile.adapter
    readonly property QtObject dashboard: dashboardFile.adapter
    readonly property QtObject launcher: launcherFile.adapter
    readonly property QtObject macros: macrosFile.adapter

    readonly property bool lightMode: theme.lightMode
    readonly property bool oledMode: lightMode ? false : theme.oledMode
    readonly property int roundness: theme.roundness
    readonly property string defaultFont: theme.font
    readonly property bool tintIcons: theme.tintIcons
    readonly property bool showBackground: theme.srBarBg.opacity > 0
    readonly property bool blurTransition: performance.blurTransition
    readonly property string notchTheme: notch.theme
    readonly property string notchPosition: notch.position

    readonly property bool dockPanelEnabled: (dock.enabled ?? false) && (dock.theme ?? "default") !== "integrated"
    readonly property bool integratedDockEnabled: (dock.enabled ?? false) && (dock.theme ?? "default") === "integrated"

    function enabledForScreen(screenList, screenName) {
        return !screenList || screenList.length === 0 || screenList.indexOf(screenName) !== -1;
    }

    readonly property int compositorRounding: compositor.syncRoundness ? roundness : compositor.rounding
    readonly property int compositorBorderSize: compositor.syncBorderWidth ? (theme.srBg.border[1] || 0) : compositor.borderSize
    readonly property string compositorBorderColor: compositor.syncBorderColor ? (theme.srBg.border[0] || "primary") : (compositor.activeBorderColor.length > 0 ? compositor.activeBorderColor[0] : "primary")
    readonly property real compositorShadowOpacity: compositor.syncShadowOpacity ? theme.shadowOpacity : compositor.shadowOpacity
    readonly property string compositorShadowColor: compositor.syncShadowColor ? theme.shadowColor : compositor.shadowColor
    readonly property string compositorShadowColorInactive: compositor.syncShadowColor ? theme.shadowColor : compositor.shadowColorInactive
}
