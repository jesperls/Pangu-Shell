import QtQuick
import qs.modules.components
import Quickshell
import Quickshell.Io
import qs.config

QtObject {
    id: root

    function generate(Colors) {
        if (!Colors) return

        const fmt = (c) => c.toString()

        const bg = Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, Config.theme.srBg.opacity).toString()
        const fg = fmt(Colors.overBackground)
        const surface = fmt(Colors.surface)
        const primary = fmt(Colors.primary)
        const secondary = fmt(Colors.secondary)
        const error = fmt(Colors.error)
        const inactive = fmt(Colors.outline)
        const link = fmt(Colors.tertiary)
        const selection = fmt(Colors.primary)
        const selectionFg = fmt(Colors.overPrimary)

        const colorSection = (name, backgroundAlternate, backgroundNormal, decoration, foreground, foregroundInactive) => `[Colors:${name}]\n`
            + `BackgroundAlternate=${backgroundAlternate}\n`
            + `BackgroundNormal=${backgroundNormal}\n`
            + `DecorationFocus=${decoration}\n`
            + `DecorationHover=${decoration}\n`
            + `ForegroundActive=${foreground}\n`
            + `ForegroundInactive=${foregroundInactive}\n`
            + `ForegroundLink=${link}\n`
            + `ForegroundNegative=${error}\n`
            + `ForegroundNeutral=${foreground}\n`
            + `ForegroundNormal=${foreground}\n`
            + `ForegroundPositive=${secondary}\n`
            + `ForegroundVisited=${link}\n\n`

        let ini = ""

        ini += "[ColorEffects:Disabled]\n"
        ini += `Color=${bg}\n`
        ini += "ColorAmount=0.5\n"
        ini += "ColorEffect=3\n"
        ini += "ContrastAmount=0\n"
        ini += "ContrastEffect=0\n"
        ini += "IntensityAmount=0\n"
        ini += "IntensityEffect=0\n\n"

        ini += "[ColorEffects:Inactive]\n"
        ini += "ChangeSelectionColor=true\n"
        ini += `Color=${bg}\n`
        ini += "ColorAmount=0.025\n"
        ini += "ColorEffect=0\n"
        ini += "ContrastAmount=0.1\n"
        ini += "ContrastEffect=0\n"
        ini += "Enable=true\n"
        ini += "IntensityAmount=0\n"
        ini += "IntensityEffect=0\n\n"

        ini += colorSection("Button", surface, surface, primary, fg, inactive)
        ini += colorSection("Complementary", bg, bg, primary, fg, inactive)
        ini += colorSection("Header", bg, bg, primary, fg, inactive)
        ini += colorSection("Header][Inactive", bg, bg, primary, fg, inactive)
        ini += colorSection("Selection", selection, selection, selection, selectionFg, selectionFg)
        ini += colorSection("Tooltip", surface, bg, primary, fg, inactive)
        ini += colorSection("View", surface, bg, primary, fg, inactive)
        ini += colorSection("Window", surface, bg, primary, fg, inactive)

        ini += "[General]\n"
        ini += "ColorScheme=Pangu\n"
        ini += "Name=Pangu\n"
        ini += "shadeSortColumn=true\n"
        ini += "\n"

        ini += "[KDE]\n"
        ini += "contrast=4\n"
        ini += "\n"

        ini += "[WM]\n"
        ini += `activeBackground=${bg}\n`
        ini += "activeBlend=252,252,252\n"
        ini += `activeForeground=${fg}\n`
        ini += `inactiveBackground=${fmt(Colors.surfaceDim)}\n`
        ini += "inactiveBlend=161,169,177\n"
        ini += `inactiveForeground=${inactive}\n`

        qt5File.write(ini);
        qt6File.write(ini);
    }

    property GeneratedFile qt5File: GeneratedFile {
        id: qt5File
        path: Paths.configHome + "/qt5ct/colors/pangu.colors"
    }

    property GeneratedFile qt6File: GeneratedFile {
        id: qt6File
        path: Paths.configHome + "/qt6ct/colors/pangu.colors"
    }
}
