import QtQuick
import qs.modules.globals
import qs.modules.services
import qs.config
import qs.modules.components
import qs.modules.theme

ToggleButton {
    buttonIcon: Config.bar.launcherIcon || Icons.cube
    iconTint: Config.bar.launcherIconTint
    iconFullTint: Config.bar.launcherIconFullTint
    iconSize: Config.bar.launcherIconSize
    tooltipText: "Open Launcher"

    onToggle: function () {
        if (GlobalStates.launcherOpen) {
            GlobalStates.clearLauncherState();
            Visibilities.setActiveModule("");
        } else {
            GlobalStates.clearLauncherState();
            Visibilities.setActiveModule("launcher");
        }
    }
}
