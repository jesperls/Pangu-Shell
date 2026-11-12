pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.globals

FileView {
    id: colors
    path: Paths.cachePath("colors.json")
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: generationTimer.restart()

    readonly property string exportSettings: JSON.stringify([
        Config.oledMode,
        Config.theme.lightMode,
        Config.theme.font,
        Config.theme.monoFont ?? "",
        Config.theme.dynamicColors ?? true,
        Config.theme.srBg.opacity,
        Config.theme.exports?.qt ?? true,
        Config.theme.exports?.gtk ?? true,
        Config.theme.exports?.pywal ?? true,
        Config.theme.exports?.kitty ?? true,
        Config.theme.exports?.nvchad ?? true,
        Config.theme.exports?.discord ?? true,
        Config.theme.exports?.firefox ?? true,
        Config.theme.exports?.spicetify ?? true,
        GlobalStates.wallpaperManager?.currentWallpaper ?? ""
    ])
    onExportSettingsChanged: generationTimer.restart()

    property Connections configWatcher: Connections {
        target: Config
        function onInitialLoadCompleteChanged() { generationTimer.restart(); }
    }

    property QtCtGenerator qtCtGenerator: QtCtGenerator {
        id: qtCtGenerator
    }

    property GtkGenerator gtkGenerator: GtkGenerator {
        id: gtkGenerator
    }

    property PywalGenerator pywalGenerator: PywalGenerator {
        id: pywalGenerator
    }

    property KittyGenerator kittyGenerator: KittyGenerator {
        id: kittyGenerator
    }

    property NvChadGenerator nvChadGenerator: NvChadGenerator {
        id: nvChadGenerator
    }

    property DiscordGenerator discordGenerator: DiscordGenerator {
        id: discordGenerator
    }

    property FirefoxGenerator firefoxGenerator: FirefoxGenerator {
        id: firefoxGenerator
    }

    property SpicetifyGenerator spicetifyGenerator: SpicetifyGenerator {
        id: spicetifyGenerator
    }

    property Timer generationTimer: Timer {
        id: generationTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (!colors.loaded || !Config.initialLoadComplete) return;
            if (Config.theme.exports?.qt ?? true)
                qtCtGenerator.generate(colors);
            if (Config.theme.exports?.gtk ?? true)
                gtkGenerator.generate(colors);
            if (Config.theme.exports?.pywal ?? true)
                pywalGenerator.generate(colors);
            if (Config.theme.exports?.kitty ?? true)
                kittyGenerator.generate(colors);
            if (Config.theme.exports?.nvchad ?? true)
                nvChadGenerator.generate(colors);
            if (Config.theme.exports?.discord ?? true)
                discordGenerator.generate(colors);
            if (Config.theme.exports?.firefox ?? true)
                firefoxGenerator.generate(colors);
            if (Config.theme.exports?.spicetify ?? true)
                spicetifyGenerator.generate(colors);
        }
    }

    adapter: JsonAdapter {
        property color background: "#0c0d11"
        property color blue: "#b6c4ff"
        property color blueContainer: "#354479"
        property color blueSource: "#0000ff"
        property color blueValue: "#0000ff"
        property color cyan: "#82d3e2"
        property color cyanContainer: "#004e59"
        property color cyanSource: "#00ffff"
        property color cyanValue: "#00ffff"
        property color error: "#ffb4ab"
        property color errorContainer: "#93000a"
        property color green: "#95d5a7"
        property color greenContainer: "#10512f"
        property color greenSource: "#00ff00"
        property color greenValue: "#00ff00"
        property color inverseOnSurface: "#2f3036"
        property color inversePrimary: "#445e91"
        property color inverseSurface: "#e2e2e9"
        property color lightBlue: "#d0d9ff"
        property color lightCyan: "#97dae7"
        property color lightGreen: "#a7dcb6"
        property color lightMagenta: "#eccdf7"
        property color lightRed: "#ffccd0"
        property color lightYellow: "#c3d696"
        property color magenta: "#e4b7f3"
        property color magentaContainer: "#5c386b"
        property color magentaSource: "#ff00ff"
        property color magentaValue: "#ff00ff"
        property color overBackground: "#e2e2e9"
        property color overBlue: "#1d2d61"
        property color overBlueContainer: "#dce1ff"
        property color overCyan: "#00363e"
        property color overCyanContainer: "#9eefff"
        property color overError: "#690005"
        property color overErrorContainer: "#ffdad6"
        property color overGreen: "#00391d"
        property color overGreenContainer: "#b0f1c2"
        property color overMagenta: "#442253"
        property color overMagentaContainer: "#f7d8ff"
        property color overPrimary: "#102f60"
        property color overPrimaryContainer: "#d8e2ff"
        property color overPrimaryFixed: "#001a41"
        property color overPrimaryFixedVariant: "#2b4678"
        property color overRed: "#561d26"
        property color overRedContainer: "#ffdadc"
        property color overSecondary: "#293041"
        property color overSecondaryContainer: "#dbe2f9"
        property color overSecondaryFixed: "#141b2c"
        property color overSecondaryFixedVariant: "#3f4759"
        property color overSurface: "#e2e2e9"
        property color overSurfaceVariant: "#c4c6d0"
        property color overTertiary: "#402843"
        property color overTertiaryContainer: "#fbd7fc"
        property color overTertiaryFixed: "#29132d"
        property color overTertiaryFixedVariant: "#583e5b"
        property color overWhite: "#00363d"
        property color overWhiteContainer: "#9eeffd"
        property color overYellow: "#263500"
        property color overYellowContainer: "#d4ec9d"
        property color outline: "#8e9099"
        property color outlineVariant: "#44474f"
        property color primary: "#adc6ff"
        property color primaryContainer: "#2b4678"
        property color primaryFixed: "#d8e2ff"
        property color primaryFixedDim: "#adc6ff"
        property color red: "#ffb2b9"
        property color redContainer: "#72333b"
        property color redSource: "#ff0000"
        property color redValue: "#ff0000"
        property color scrim: "#000000"
        property color secondary: "#bfc6dc"
        property color secondaryContainer: "#3f4759"
        property color secondaryFixed: "#dbe2f9"
        property color secondaryFixedDim: "#bfc6dc"
        property color shadow: "#000000"
        property color surface: "#111318"
        property color surfaceBright: "#37393e"
        property color surfaceContainer: "#1e1f25"
        property color surfaceContainerHigh: "#282a2f"
        property color surfaceContainerHighest: "#33353a"
        property color surfaceContainerLow: "#1a1b20"
        property color surfaceContainerLowest: "#0c0e13"
        property color surfaceDim: "#111318"
        property color surfaceTint: "#adc6ff"
        property color surfaceVariant: "#44474f"
        property color tertiary: "#debcdf"
        property color tertiaryContainer: "#583e5b"
        property color tertiaryFixed: "#fbd7fc"
        property color tertiaryFixedDim: "#debcdf"
        property color white: "#82d3e0"
        property color whiteContainer: "#004f58"
        property color whiteSource: "#ffffff"
        property color whiteValue: "#ffffff"
        property color yellow: "#b8cf84"
        property color yellowContainer: "#3b4d0f"
        property color yellowSource: "#ffff00"
        property color yellowValue: "#ffff00"
        property color sourceColor: "#203f74"
    }

    function _oledTint(alpha) {
        const r = adapter.overBackground.r * 0.65 + adapter.primary.r * 0.35;
        const g = adapter.overBackground.g * 0.65 + adapter.primary.g * 0.35;
        const b = adapter.overBackground.b * 0.65 + adapter.primary.b * 0.35;
        return Qt.tint("#000000", Qt.rgba(r, g, b, alpha));
    }

    property color background: Config.oledMode ? "#000000" : adapter.background

    property color surface: Config.oledMode ? _oledTint(0.08) : Qt.tint(background, Qt.rgba(adapter.overBackground.r, adapter.overBackground.g, adapter.overBackground.b, 0.1))
    property color surfaceBright: Config.oledMode ? _oledTint(0.18) : Qt.tint(background, Qt.rgba(adapter.overBackground.r, adapter.overBackground.g, adapter.overBackground.b, 0.2))
    property color surfaceContainer: Config.oledMode ? _oledTint(0.07) : adapter.surfaceContainer
    property color surfaceContainerHigh: Config.oledMode ? _oledTint(0.11) : adapter.surfaceContainerHigh
    property color surfaceContainerHighest: Config.oledMode ? _oledTint(0.15) : adapter.surfaceContainerHighest
    property color surfaceContainerLow: Config.oledMode ? _oledTint(0.04) : adapter.surfaceContainerLow
    property color surfaceContainerLowest: Config.oledMode ? "#000000" : adapter.surfaceContainerLowest
    property color surfaceDim: Config.oledMode ? "#000000" : adapter.surfaceDim
    property color surfaceTint: adapter.surfaceTint
    property color surfaceVariant: adapter.surfaceVariant

    property color blue: adapter.blue
    property color blueContainer: adapter.blueContainer
    property color blueSource: adapter.blueSource
    property color blueValue: adapter.blueValue
    property color cyan: adapter.cyan
    property color cyanContainer: adapter.cyanContainer
    property color cyanSource: adapter.cyanSource
    property color cyanValue: adapter.cyanValue
    property color error: adapter.error
    property color errorContainer: adapter.errorContainer
    property color green: adapter.green
    property color greenContainer: adapter.greenContainer
    property color greenSource: adapter.greenSource
    property color greenValue: adapter.greenValue
    property color inverseOnSurface: adapter.inverseOnSurface
    property color inversePrimary: adapter.inversePrimary
    property color inverseSurface: adapter.inverseSurface
    property color lightBlue: adapter.lightBlue
    property color lightCyan: adapter.lightCyan
    property color lightGreen: adapter.lightGreen
    property color lightMagenta: adapter.lightMagenta
    property color lightRed: adapter.lightRed
    property color lightYellow: adapter.lightYellow
    property color magenta: adapter.magenta
    property color magentaContainer: adapter.magentaContainer
    property color magentaSource: adapter.magentaSource
    property color magentaValue: adapter.magentaValue
    property color overBackground: adapter.overBackground
    property color overBlue: adapter.overBlue
    property color overBlueContainer: adapter.overBlueContainer
    property color overCyan: adapter.overCyan
    property color overCyanContainer: adapter.overCyanContainer
    property color overError: adapter.overError
    property color overErrorContainer: adapter.overErrorContainer
    property color overGreen: adapter.overGreen
    property color overGreenContainer: adapter.overGreenContainer
    property color overMagenta: adapter.overMagenta
    property color overMagentaContainer: adapter.overMagentaContainer
    property color overPrimary: adapter.overPrimary
    property color overPrimaryContainer: adapter.overPrimaryContainer
    property color overPrimaryFixed: adapter.overPrimaryFixed
    property color overPrimaryFixedVariant: adapter.overPrimaryFixedVariant
    property color overRed: adapter.overRed
    property color overRedContainer: adapter.overRedContainer
    property color overSecondary: adapter.overSecondary
    property color overSecondaryContainer: adapter.overSecondaryContainer
    property color overSecondaryFixed: adapter.overSecondaryFixed
    property color overSecondaryFixedVariant: adapter.overSecondaryFixedVariant
    property color overSurface: adapter.overSurface
    property color overSurfaceVariant: adapter.overSurfaceVariant
    property color overTertiary: adapter.overTertiary
    property color overTertiaryContainer: adapter.overTertiaryContainer
    property color overTertiaryFixed: adapter.overTertiaryFixed
    property color overTertiaryFixedVariant: adapter.overTertiaryFixedVariant
    property color overWhite: adapter.overWhite
    property color overWhiteContainer: adapter.overWhiteContainer
    property color overYellow: adapter.overYellow
    property color overYellowContainer: adapter.overYellowContainer
    property color outline: adapter.outline
    property color outlineVariant: adapter.outlineVariant
    property color primary: adapter.primary
    property color primaryContainer: adapter.primaryContainer
    property color primaryFixed: adapter.primaryFixed
    property color primaryFixedDim: adapter.primaryFixedDim
    property color red: adapter.red
    property color redContainer: adapter.redContainer
    property color redSource: adapter.redSource
    property color redValue: adapter.redValue
    property color scrim: adapter.scrim
    property color secondary: adapter.secondary
    property color secondaryContainer: adapter.secondaryContainer
    property color secondaryFixed: adapter.secondaryFixed
    property color secondaryFixedDim: adapter.secondaryFixedDim
    property color shadow: adapter.shadow
    property color tertiary: adapter.tertiary
    property color tertiaryContainer: adapter.tertiaryContainer
    property color tertiaryFixed: adapter.tertiaryFixed
    property color tertiaryFixedDim: adapter.tertiaryFixedDim
    property color white: adapter.white
    property color whiteContainer: adapter.whiteContainer
    property color whiteSource: adapter.whiteSource
    property color whiteValue: adapter.whiteValue
    property color yellow: adapter.yellow
    property color yellowContainer: adapter.yellowContainer
    property color yellowSource: adapter.yellowSource
    property color yellowValue: adapter.yellowValue
    property color sourceColor: adapter.sourceColor

    property color criticalText: "#FF6B08"
    property color criticalRed: "#FF0028"

    property color warning: adapter.yellow
    property color success: adapter.green

    readonly property var availableColorNames: ["background", "surface", "surfaceBright", "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest", "surfaceContainerLow", "surfaceContainerLowest", "surfaceDim", "surfaceTint", "surfaceVariant", "primary", "primaryContainer", "primaryFixed", "primaryFixedDim", "secondary", "secondaryContainer", "secondaryFixed", "secondaryFixedDim", "tertiary", "tertiaryContainer", "tertiaryFixed", "tertiaryFixedDim", "error", "errorContainer", "overBackground", "overSurface", "overSurfaceVariant", "overPrimary", "overPrimaryContainer", "overPrimaryFixed", "overPrimaryFixedVariant", "overSecondary", "overSecondaryContainer", "overSecondaryFixed", "overSecondaryFixedVariant", "overTertiary", "overTertiaryContainer", "overTertiaryFixed", "overTertiaryFixedVariant", "overError", "overErrorContainer", "outline", "outlineVariant", "inversePrimary", "inverseSurface", "inverseOnSurface", "shadow", "scrim", "blue", "blueContainer", "overBlue", "overBlueContainer", "lightBlue", "cyan", "cyanContainer", "overCyan", "overCyanContainer", "lightCyan", "green", "greenContainer", "overGreen", "overGreenContainer", "lightGreen", "magenta", "magentaContainer", "overMagenta", "overMagentaContainer", "lightMagenta", "red", "redContainer", "overRed", "overRedContainer", "lightRed", "yellow", "yellowContainer", "overYellow", "overYellowContainer", "lightYellow", "white", "whiteContainer", "overWhite", "overWhiteContainer"]

    function isHexColor(value) {
        if (!value || typeof value !== "string")
            return false;
        const normalized = value.toLowerCase().trim();
        return normalized.startsWith("#") || normalized.startsWith("rgb");
    }

    function resolve(value) {
        if (!value)
            return "transparent";
        if (isHexColor(value))
            return value;
        return colors[value] || "transparent";
    }
}
