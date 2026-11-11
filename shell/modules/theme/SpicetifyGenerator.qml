import QtQuick
import qs.config
import qs.modules.components

QtObject {
    id: root

    function stripHash(c) {
        return c.toString().replace(/^#/, "");
    }

    function generate(Colors) {
        if (!Colors)
            return;

        const text = stripHash(Colors.overBackground);
        const subtext = stripHash(Colors.overSurfaceVariant);
        const main = stripHash(Colors.background);
        const sidebar = stripHash(Colors.surfaceContainerLowest);
        const player = stripHash(Colors.surfaceContainerLow);
        const card = stripHash(Colors.surfaceContainer);
        const shadow = stripHash(Colors.shadow);
        const selectedRow = stripHash(Colors.surfaceContainerHigh);
        const button = stripHash(Colors.primary);
        const buttonActive = stripHash(Colors.primaryFixed);
        const buttonDisabled = stripHash(Colors.surfaceVariant);
        const tabActive = stripHash(Colors.surfaceContainerHigh);
        const notification = stripHash(Colors.primaryContainer);
        const notificationError = stripHash(Colors.error);
        const misc = stripHash(Colors.outlineVariant);

        const ini = `[pangu]
text               = ${text}
subtext            = ${subtext}
main               = ${main}
main-elevated      = ${card}
highlight          = ${selectedRow}
highlight-elevated = ${tabActive}
sidebar            = ${sidebar}
player             = ${player}
card               = ${card}
shadow             = ${shadow}
selected-row       = ${selectedRow}
button             = ${button}
button-active      = ${buttonActive}
button-disabled    = ${buttonDisabled}
tab-active         = ${tabActive}
notification       = ${notification}
notification-error = ${notificationError}
misc               = ${misc}
`;

        const css = `:root {
  --spice-text: #${text};
  --spice-subtext: #${subtext};
  --spice-main: #${main};
  --spice-sidebar: #${sidebar};
  --spice-player: #${player};
  --spice-card: #${card};
  --spice-button: #${button};
  --spice-button-active: #${buttonActive};
  --spice-selected-row: #${selectedRow};
  --spice-tab-active: #${tabActive};
}
`;

        colorIniFile.write(ini);
        userCssFile.write(css);
    }

    property GeneratedFile colorIniFile: GeneratedFile {
        path: Paths.configHome + "/spicetify/Themes/Pangu/color.ini"
    }

    property GeneratedFile userCssFile: GeneratedFile {
        path: Paths.configHome + "/spicetify/Themes/Pangu/user.css"
    }
}
