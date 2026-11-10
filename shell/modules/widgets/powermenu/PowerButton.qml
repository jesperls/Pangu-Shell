import QtQuick
import qs.modules.components
import qs.modules.theme
import qs.modules.services

ToggleButton {
    id: powerButton
    property string screenName: ""

    buttonIcon: Icons.shutdown
    tooltipText: "Power Menu"
    active: screenName !== "" ? (Visibilities.getForScreen(screenName)?.powermenu ?? false) : Visibilities.isActiveOnFocusedScreen("powermenu")
    onToggle: function () {
        const isOpen = powerButton.active;
        Visibilities.setActiveModule(isOpen ? "" : "powermenu", powerButton.screenName);
    }
}
