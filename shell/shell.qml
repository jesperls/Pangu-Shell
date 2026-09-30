//@ pragma UseQApplication
//@ pragma ShellId pangu
//@ pragma DataDir $BASE/pangu
//@ pragma StateDir $BASE/pangu

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.bar
import qs.modules.bar.workspaces
import qs.modules.notifications

import qs.modules.notch
import qs.modules.widgets.overview
import qs.modules.widgets.cheatsheet
import qs.modules.widgets.dashboard.wallpapers
import qs.modules.services
import qs.modules.corners
import qs.modules.frame
import qs.modules.components
import qs.modules.lockscreen
import qs.modules.dock
import qs.modules.globals
import qs.modules.shell
import qs.config
import qs.modules.shell.osd
import qs.modules.widgets.macros
import "modules/tools"

ShellRoot {
    id: root

    ContextMenu {
        id: contextMenu
        screen: Quickshell.screens.find(s => Compositor.focusedMonitor && s.name === Compositor.focusedMonitor.name) ?? Quickshell.screens[0]
        Component.onCompleted: Visibilities.setContextMenu(contextMenu)
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: wallpaperLoader
            required property ShellScreen modelData
            sourceComponent: Wallpaper {
                screen: wallpaperLoader.modelData
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Item {
            id: screenShellContainer
            required property ShellScreen modelData

            UnifiedShellPanel {
                id: unifiedPanel
                targetScreen: screenShellContainer.modelData
            }

            Loader {
                active: screenShellContainer.modelData !== null && Config.theme.enableCorners && Config.roundness > 0
                sourceComponent: ScreenCorners {
                    screen: screenShellContainer.modelData
                }
            }

            ReservationWindows {
                screen: screenShellContainer.modelData

                barEnabled: {
                    const list = (Config.bar && Config.bar.screenList !== undefined ? Config.bar.screenList : []);
                    return screen !== null && (!list || list.length === 0 || list.indexOf(screen.name) !== -1);
                }
                barPosition: unifiedPanel.barPosition
                barPinned: unifiedPanel.pinned
                barSize: (unifiedPanel.barPosition === "left" || unifiedPanel.barPosition === "right") ? unifiedPanel.barTargetWidth : unifiedPanel.barTargetHeight
                barOuterMargin: unifiedPanel.barOuterMargin

                dockEnabled: {
                    if (!screenShellContainer.modelData || !Config.dockPanelEnabled)
                        return false;
                    return Config.enabledForScreen(Config.dock?.screenList, screenShellContainer.modelData.name);
                }
                dockPosition: unifiedPanel.dockPosition
                dockPinned: unifiedPanel.dockPinned
                dockHeight: unifiedPanel.dockHeight
                containBar: unifiedPanel.containBar

                frameEnabled: (Config.bar && Config.bar.frameEnabled !== undefined ? Config.bar.frameEnabled : false)
                frameThickness: (Config.bar && Config.bar.frameThickness !== undefined ? Config.bar.frameThickness : 6)

            }
        }
    }

    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = (Config.bar && Config.bar.screenList !== undefined ? Config.bar.screenList : []);
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.indexOf(screen.name) !== -1);
        }

        Loader {
            id: overviewLoader
            active: modelData !== null && ((Config.overview && Config.overview.enabled !== undefined ? Config.overview.enabled : true)) && SuspendManager.wakeReady && overviewEnabledFor(modelData.name)
            required property ShellScreen modelData
            sourceComponent: OverviewPopup {
                screen: overviewLoader.modelData
            }
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: GlobalStates.lockscreenVisible

        LockScreen {}
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: screenshotLoader
            active: GlobalStates.screenshotToolVisible
            required property ShellScreen modelData
            sourceComponent: ScreenshotTool {
                targetScreen: screenshotLoader.modelData
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: screenshotOverlayLoader
            active: SuspendManager.wakeReady
            required property ShellScreen modelData
            sourceComponent: ScreenshotOverlay {
                targetScreen: screenshotOverlayLoader.modelData
            }
        }
    }

    Loader {
        id: screenRecordLoader
        active: SuspendManager.wakeReady && GlobalStates.screenRecordToolVisible
        source: "modules/tools/ScreenrecordTool.qml"

        onLoaded: {
            if (GlobalStates.screenRecordToolVisible && item) {
                item.open();
            }
        }

        Connections {
            target: GlobalStates
            function onScreenRecordToolVisibleChanged() {
                if (screenRecordLoader.status === Loader.Ready) {
                    if (GlobalStates.screenRecordToolVisible) {
                        screenRecordLoader.item.open();
                    } else {
                        screenRecordLoader.item.close();
                    }
                }
            }
        }

        Connections {
            target: screenRecordLoader.item
            ignoreUnknownSignals: true
            function onVisibleChanged() {
                if (!screenRecordLoader.item.visible && GlobalStates.screenRecordToolVisible) {
                    GlobalStates.screenRecordToolVisible = false;
                }
            }
        }
    }

    Loader {
        id: mirrorLoader
        active: SuspendManager.wakeReady && GlobalStates.mirrorWindowVisible
        source: "modules/tools/MirrorWindow.qml"
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: cheatsheetLoader
            required property ShellScreen modelData
            active: GlobalStates.cheatsheetVisible && (Quickshell.screens.length === 1 || Compositor.focusedMonitor?.name === modelData.name)
            sourceComponent: CheatsheetPopup {
                screen: cheatsheetLoader.modelData
            }
        }
    }

    Loader {
        id: settingsWindowLoader
        active: SuspendManager.wakeReady && GlobalStates.settingsWindowVisible
        source: "modules/widgets/config/SettingsWindow.qml"
    }

    Loader {
        id: macrosWindowLoader
        active: SuspendManager.wakeReady && GlobalStates.macrosWindowVisible
        source: "modules/widgets/macros/MacrosWindow.qml"
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: mousePickLoader
            active: SuspendManager.wakeReady && GlobalStates.mousePickActive
            required property ShellScreen modelData
            sourceComponent: MousePickOverlay {
                targetScreen: mousePickLoader.modelData
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: osdLoader
            active: SuspendManager.wakeReady
            required property ShellScreen modelData
            sourceComponent: OSD {
                targetScreen: osdLoader.modelData
            }
        }
    }


    Component.onCompleted: Qt.callLater(() => {
        void CaffeineService.inhibit;
        void IdleService.lockCmd;
        void LockscreenService.ipc;
        void NightLightService.active;
        void GameModeService.workspaces;
        void GlobalShortcuts.appId;
        void ClipboardService.active;
        void CompositorTheme.outputPath;
        void WallpaperSlideshowService.enabled;
        void AutoThemeService.enabled;
        void ReplayService.active;
        void MacroService.enabled;
    })

    function overviewEnabledFor(screenName) {
        const v = Visibilities.getForScreen(screenName);
        return v ? v.overview : false;
    }
}
