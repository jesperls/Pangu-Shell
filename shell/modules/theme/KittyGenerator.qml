import QtQuick
import qs.modules.components
import Quickshell
import Quickshell.Io
import qs.config

QtObject {
    id: root

    function generate(Colors) {
        if (!Colors)
            return;
        const fmt = c => c.toString();

        const cursor = fmt(Colors.primary);
        const cursorText = fmt(Colors.overPrimary);

        const foreground = fmt(Colors.overSurface);
        const background = fmt(Colors.background);
        const selectionForeground = fmt(Colors.overPrimary);
        const selectionBackground = fmt(Colors.primary);
        const urlColor = fmt(Colors.secondary);
        const activeBorderColor = fmt(Colors.primary);
        const inactiveBorderColor = fmt(Colors.outlineVariant);
        const bellBorderColor = fmt(Colors.tertiary);
        const activeTabForeground = fmt(Colors.overPrimary);
        const activeTabBackground = fmt(Colors.primary);
        const inactiveTabForeground = fmt(Colors.overSurfaceVariant);
        const inactiveTabBackground = fmt(Colors.surfaceContainer);
        const tabBarBackground = fmt(Colors.surfaceContainerLowest);
        const backgroundOpacity = Config.theme.srBg.opacity;

        const color0 = fmt(Colors.surfaceContainerLow);
        const color8 = fmt(Colors.surfaceBright);

        const color1 = fmt(Colors.red);
        const color9 = fmt(Colors.lightRed);

        const color2 = fmt(Colors.green);
        const color10 = fmt(Colors.lightGreen);

        const color3 = fmt(Colors.yellow);
        const color11 = fmt(Colors.lightYellow);

        const color4 = fmt(Colors.primary);
        const color12 = fmt(Colors.lightBlue);

        const color5 = fmt(Colors.magenta);
        const color13 = fmt(Colors.lightMagenta);

        const color6 = fmt(Colors.cyan);
        const color14 = fmt(Colors.lightCyan);

        const color7 = fmt(Colors.outline);
        const color15 = fmt(Colors.overSurface);

        let conf = "";
        conf += `cursor ${cursor}\n`;
        conf += `cursor_text_color ${cursorText}\n\n`;

        conf += `foreground ${foreground}\n`;
        conf += `background ${background}\n`;
        conf += `background_opacity ${backgroundOpacity}\n`;
        conf += `selection_foreground ${selectionForeground}\n`;
        conf += `selection_background ${selectionBackground}\n`;
        conf += `url_color ${urlColor}\n`;
        conf += `active_border_color ${activeBorderColor}\n`;
        conf += `inactive_border_color ${inactiveBorderColor}\n`;
        conf += `bell_border_color ${bellBorderColor}\n`;
        conf += `active_tab_foreground ${activeTabForeground}\n`;
        conf += `active_tab_background ${activeTabBackground}\n`;
        conf += `inactive_tab_foreground ${inactiveTabForeground}\n`;
        conf += `inactive_tab_background ${inactiveTabBackground}\n`;
        conf += `tab_bar_background ${tabBarBackground}\n\n`;

        conf += `# black\n`;
        conf += `color0 ${color0}\n`;
        conf += `color8 ${color8}\n\n`;

        conf += `# red\n`;
        conf += `color1 ${color1}\n`;
        conf += `color9 ${color9}\n\n`;

        conf += `# green\n`;
        conf += `color2 ${color2}\n`;
        conf += `color10 ${color10}\n\n`;

        conf += `# yellow\n`;
        conf += `color3 ${color3}\n`;
        conf += `color11 ${color11}\n\n`;

        conf += `# blue\n`;
        conf += `color4 ${color4}\n`;
        conf += `color12 ${color12}\n\n`;

        conf += `# magenta\n`;
        conf += `color5 ${color5}\n`;
        conf += `color13 ${color13}\n\n`;

        conf += `# cyan\n`;
        conf += `color6 ${color6}\n`;
        conf += `color14 ${color14}\n\n`;

        conf += `# white\n`;
        conf += `color7 ${color7}\n`;
        conf += `color15 ${color15}\n`;

        kittyFile.write(conf);
    }

    property GeneratedFile kittyFile: GeneratedFile {
        id: kittyFile
        path: Paths.cachePath("kitty.conf")
        onWritten: reloadProcess.running = true
    }

    property Process reloadProcess: Process {
        command: ["pkill", "-USR1", "-x", "kitty"]
    }
}
