import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals
import qs.config
import qs.modules.components

QtObject {
    id: root

    function generate(Colors) {
        if (!Colors)
            return;

        try {
            const fmt = (c) => c.toString();
            const image = (typeof GlobalStates !== "undefined" && GlobalStates.wallpaperManager)
                ? (GlobalStates.wallpaperManager.currentWallpaper || "")
                : "";

            const darken = (c, percent) => {
                try {
                    return Qt.tint(c, Qt.rgba(0, 0, 0, percent / 100)).toString();
                } catch (err) {
                    return "#000000";
                }
            };

            const palette = [
                fmt(Colors.background),
                fmt(Colors.red),
                fmt(Colors.green),
                fmt(Colors.yellow),
                fmt(Colors.primary),
                fmt(Colors.magenta),
                fmt(Colors.cyan),
                fmt(Colors.outline),
                fmt(Colors.surfaceBright),
                fmt(Colors.lightRed),
                fmt(Colors.lightGreen),
                fmt(Colors.lightYellow),
                fmt(Colors.lightBlue),
                fmt(Colors.lightMagenta),
                fmt(Colors.lightCyan),
                fmt(Colors.overSurface)
            ];

            const colorsContent = palette.join("\n");

            const colorMap = {};
            for (let i = 0; i < palette.length; i++)
                colorMap[`color${i}`] = palette[i];

            const jsonColors = {
                "wallpaper": image,
                "alpha": "100",
                "special": {
                    "background": darken(Colors.background, 5.0),
                    "foreground": fmt(Colors.overBackground),
                    "cursor": fmt(Colors.overSurface)
                },
                "colors": colorMap
            };
            const jsonContent = JSON.stringify(jsonColors, null, 2);

            let shContent = "";
            for (let i = 0; i < palette.length; i++)
                shContent += `color${i}="${palette[i]}"\n`;

            colorsFile.write(colorsContent);
            jsonFile.write(jsonContent);
            shellFile.write(shContent);
            imageFile.write(image);
        } catch (e) {
            console.warn("PywalGenerator:", e);
        }
    }

    property GeneratedFile colorsFile: GeneratedFile {
        id: colorsFile
        path: Paths.cacheHome + "/wal/colors"
        onWritten: Qt.callLater(root.reloader.reload)
    }

    property GeneratedFile jsonFile: GeneratedFile {
        id: jsonFile
        path: Paths.cacheHome + "/wal/colors.json"
        onWritten: Qt.callLater(root.reloader.reload)
    }

    property GeneratedFile shellFile: GeneratedFile {
        id: shellFile
        path: Paths.cacheHome + "/wal/colors.sh"
        onWritten: Qt.callLater(root.reloader.reload)
    }

    property GeneratedFile imageFile: GeneratedFile {
        id: imageFile
        path: Paths.cacheHome + "/wal/wal"
        onWritten: Qt.callLater(root.reloader.reload)
    }

    property ThemeReloader reloader: ThemeReloader {
        files: [colorsFile, jsonFile, shellFile, imageFile]
        command: ["bash", "-c", "if command -v pywalfox >/dev/null; then pywalfox update; fi; if command -v walogram >/dev/null; then walogram -B; fi"]
    }
}
