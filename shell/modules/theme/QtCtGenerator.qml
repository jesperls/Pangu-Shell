import QtQuick
import qs.modules.components
import Quickshell
import Quickshell.Io
import qs.config

QtObject {
    id: root

    function generate(Colors) {
        if (!Colors) return

        const argb = (c, alphaHex) => "#" + (alphaHex || "ff") + [c.r, c.g, c.b]
            .map(v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0"))
            .join("")

        const bg = argb(Colors.background)
        const fg = argb(Colors.overBackground)
        const disabledFg = argb(Colors.outline)
        const surface = argb(Colors.surface)
        const surfaceBright = argb(Colors.surfaceBright)
        const surfaceLow = argb(Colors.surfaceContainerLow)
        const surfaceLowest = argb(Colors.surfaceContainerLowest)
        const surfaceMid = argb(Colors.surfaceContainer)
        const surfaceHigh = argb(Colors.surfaceContainerHigh)
        const shadow = argb(Colors.shadow)
        const primary = argb(Colors.primary)
        const overPrimary = argb(Colors.overPrimary)
        const secondary = argb(Colors.secondary)
        const tertiary = argb(Colors.tertiary)
        const placeholder = argb(Colors.overBackground, "80")

        // QPalette::ColorRole enum order 0..20 required by qt5ct/qt6ct.
        const active = [
            fg, surfaceMid, surfaceBright, surfaceHigh, surfaceLowest, surfaceLow,
            fg, overPrimary, fg, surface, bg, shadow, primary, overPrimary,
            tertiary, secondary, surfaceLow, fg, surfaceHigh, fg, placeholder
        ]
        const disabled = [
            disabledFg, surfaceMid, surfaceBright, surfaceHigh, surfaceLowest, surfaceLow,
            disabledFg, overPrimary, disabledFg, surface, bg, shadow, surfaceHigh, disabledFg,
            tertiary, secondary, surfaceLow, disabledFg, surfaceHigh, disabledFg, placeholder
        ]
        const inactive = [
            fg, surfaceMid, surfaceBright, surfaceHigh, surfaceLowest, surfaceLow,
            fg, overPrimary, fg, surface, bg, shadow, primary, overPrimary,
            tertiary, secondary, surfaceLow, fg, surfaceHigh, fg, placeholder
        ]

        const conf = "[ColorScheme]\n"
            + `active_colors=${active.join(", ")}\n`
            + `disabled_colors=${disabled.join(", ")}\n`
            + `inactive_colors=${inactive.join(", ")}\n`

        qt5File.write(conf);
        qt6File.write(conf);
    }

    property GeneratedFile qt5File: GeneratedFile {
        id: qt5File
        path: Paths.configHome + "/qt5ct/colors/pangu.conf"
    }

    property GeneratedFile qt6File: GeneratedFile {
        id: qt6File
        path: Paths.configHome + "/qt6ct/colors/pangu.conf"
    }
}
