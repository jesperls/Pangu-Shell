import QtQuick
import qs.config
import qs.modules.components
import qs.modules.theme
import qs.modules.services

ToggleButton {
    id: petsButton

    visible: Boolean(Config.petsEnabled) && (Config.bar && Config.bar.showPetsButton !== undefined ? Config.bar.showPetsButton : true)
    buttonIcon: Icons.pawPrint
    tooltipText: "Pokémon Sanctuary · Right-click: toggle pets"
    onToggle: function () {
        ApplicationLauncher.launchCommand(["qs-vpets", "pen"]);
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: ApplicationLauncher.launchCommand(["qs-vpets", "toggle"])
    }
}
