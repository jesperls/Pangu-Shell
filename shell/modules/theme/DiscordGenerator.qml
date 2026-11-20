import QtQuick
import qs.modules.components
import Quickshell
import Quickshell.Io
import qs.config

QtObject {
    id: root

    function generate(Colors) {
        if (!Colors) return

        const toRGB = (c) => {
            return `${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)}`
        }
        
        const accentcolor = toRGB(Colors.primary)
        const accentcolor2 = toRGB(Colors.secondary)
        const linkcolor = toRGB(Colors.blue)
        const mentioncolor = toRGB(Colors.yellow)
        
        const font = String(Config.theme.font || "gg sans").replace(/[;"'\n\r{}]/g, "").trim() || "gg sans"

        const isLight = Config.theme.lightMode
        const backgroundaccent = toRGB(Colors.surfaceContainerHighest)
        const backgroundprimary = toRGB(Colors.surface)
        const backgroundsecondary = toRGB(Colors.surfaceContainerLow)
        const backgroundsecondaryalt = toRGB(Colors.surfaceContainer)
        const backgroundtertiary = toRGB(Colors.background)
        const backgroundfloating = toRGB(Colors.surfaceContainerHigh)

        const fg = Colors.overBackground
        const textbrightest = toRGB(fg)
        const textbrighter = isLight ? toRGB(Qt.lighter(fg, 1.15)) : toRGB(Qt.darker(fg, 1.15))
        const textbright = isLight ? toRGB(Qt.lighter(fg, 1.38)) : toRGB(Qt.darker(fg, 1.38))
        const textdark = isLight ? toRGB(Qt.lighter(fg, 1.82)) : toRGB(Qt.darker(fg, 1.82))
        const textdarker = isLight ? toRGB(Qt.lighter(fg, 2.22)) : toRGB(Qt.darker(fg, 2.22))
        const textdarkest = isLight ? toRGB(Qt.lighter(fg, 3.19)) : toRGB(Qt.darker(fg, 3.19))

        let css = `/**
 * @name Pangu
 * @description A Discord recolor theme, generated from the Pangu palette.
 * @version 1.0.0
*/ 

@import url('https://mwittrien.github.io/BetterDiscordAddons/Themes/DiscordRecolor/DiscordRecolor.css');

:root {
  --accentcolor: ${accentcolor};
  --accentcolor2: ${accentcolor2};
  --linkcolor: ${linkcolor};
  --mentioncolor: ${mentioncolor};
  --textbrightest: ${textbrightest};
  --textbrighter: ${textbrighter};
  --textbright: ${textbright};
  --textdark: ${textdark};
  --textdarker: ${textdarker};
  --textdarkest: ${textdarkest};
  --font: "${font}", "gg sans";
  --backgroundaccent: ${backgroundaccent};
  --backgroundprimary: ${backgroundprimary};
  --backgroundsecondary: ${backgroundsecondary};
  --backgroundsecondaryalt: ${backgroundsecondaryalt};
  --backgroundtertiary: ${backgroundtertiary};
  --backgroundfloating: ${backgroundfloating};
  --settingsicons: 1;
}

`

        discordFile.write(css);
    }

    property GeneratedFile discordFile: GeneratedFile {
        id: discordFile
        path: Paths.configHome + "/vesktop/themes/pangu.css"
    }
}
