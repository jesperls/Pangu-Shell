import QtQuick
import qs.modules.globals
import qs.modules.services
import qs.config
import qs.modules.components
import qs.modules.theme

ToggleButton {
    id: launcherBtn
    property string screenName: ""

    buttonIcon: Config.bar.launcherIcon || Icons.cube
    iconTint: Config.bar.launcherIconTint
    iconFullTint: Config.bar.launcherIconFullTint
    iconSize: Config.bar.launcherIconSize
    tooltipText: "Open Launcher"
    active: screenName !== "" ? (Visibilities.getForScreen(screenName)?.launcher ?? false) : Visibilities.isActiveOnFocusedScreen("launcher")

    onToggle: function () {
        const isOpen = launcherBtn.screenName !== "" ? (Visibilities.getForScreen(launcherBtn.screenName)?.launcher ?? false) : GlobalStates.launcherOpen;
        GlobalStates.clearLauncherState();
        Visibilities.setActiveModule(isOpen ? "" : "launcher", launcherBtn.screenName);
    }
}
