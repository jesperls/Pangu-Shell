import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.components

QtObject {
    id: root

    readonly property string colorScheme: Config.theme.lightMode ? "prefer-light" : "prefer-dark"
    property string appliedColorScheme: ""

    function syncColorScheme() {
        if (schemeProcess.running || root.appliedColorScheme === root.colorScheme) return;
        schemeProcess.scheme = root.colorScheme;
        schemeProcess.running = true;
    }

    property Process schemeProcess: Process {
        property string scheme
        command: ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme]
        onExited: code => {
            if (code === 0) root.appliedColorScheme = scheme;
            else console.warn("Could not update desktop color scheme:", code);
            if (scheme !== root.colorScheme) Qt.callLater(root.syncColorScheme);
        }
    }

    function generate(Colors) {
        if (!Colors) return
        root.syncColorScheme();

        const fmt = (c) => c.toString()
        const toRgba = (c, a) => `rgba(${Math.round(c.r * 255)}, ${Math.round(c.g * 255)}, ${Math.round(c.b * 255)}, ${a})`

        const primary = fmt(Colors.primary)
        const onPrimary = fmt(Colors.overPrimary)
        const background = toRgba(Colors.background, Config.theme.srBg.opacity)
        const onBackground = fmt(Colors.overBackground)
        const surface = fmt(Colors.surface)
        const onSurface = fmt(Colors.overSurface)
        const surfaceContainer = fmt(Colors.surfaceContainer)

        let css = ""
        
        css += `@define-color accent_color ${primary};\n`
        css += `@define-color accent_fg_color ${onPrimary};\n`
        css += `@define-color accent_bg_color ${primary};\n`
        css += `@define-color window_bg_color ${background};\n`
        css += `@define-color window_fg_color ${onBackground};\n`
        css += `@define-color headerbar_bg_color ${background};\n`
        css += `@define-color headerbar_fg_color ${onBackground};\n`
        css += `@define-color popover_bg_color ${surface};\n`
        css += `@define-color popover_fg_color ${onSurface};\n`
        css += `@define-color view_bg_color ${background};\n`
        css += `@define-color view_fg_color ${onBackground};\n`
        css += `@define-color card_bg_color ${surfaceContainer};\n`
        css += `@define-color card_fg_color ${onSurface};\n`
        
        css += `@define-color sidebar_bg_color @window_bg_color;\n`
        css += `@define-color sidebar_fg_color @window_fg_color;\n`
        css += `@define-color sidebar_border_color @window_bg_color;\n`
        css += `@define-color sidebar_backdrop_color @window_bg_color;\n`

        paletteFile.write(css);
    }

    property GeneratedFile paletteFile: GeneratedFile {
        id: paletteFile
        path: Paths.cachePath("gtk.css")
        onWritten: Qt.callLater(root.reloader.reload)
    }

    property ThemeReloader reloader: ThemeReloader {
        files: [paletteFile]
        command: ["bash", "-c", "theme=$(gsettings get org.gnome.desktop.interface gtk-theme); gsettings set org.gnome.desktop.interface gtk-theme \"''\" && gsettings set org.gnome.desktop.interface gtk-theme \"$theme\""]
    }
}
