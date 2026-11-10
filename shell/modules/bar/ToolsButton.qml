import QtQuick
import qs.modules.components
import qs.modules.theme
import qs.modules.services

ToggleButton {
    id: toolsButton
    property string screenName: ""

    buttonIcon: Icons.toolbox
    tooltipText: "Tools"
    active: screenName !== "" ? (Visibilities.getForScreen(screenName)?.tools ?? false) : Visibilities.isActiveOnFocusedScreen("tools")
    onToggle: function () {
        const isOpen = toolsButton.active;
        Visibilities.setActiveModule(isOpen ? "" : "tools", toolsButton.screenName);
    }
}
