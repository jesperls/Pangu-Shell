import QtQuick
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    implicitWidth: toolsMenu.implicitWidth
    implicitHeight: toolsMenu.implicitHeight

    Behavior on implicitWidth {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration
            easing.type: Easing.OutQuart
        }
    }

    Behavior on implicitHeight {
        enabled: Styling.animDuration > 0
        NumberAnimation {
            duration: Styling.animDuration
            easing.type: Easing.OutQuart
        }
    }

    ToolsMenu {
        id: toolsMenu
        anchors.fill: parent
        
        onItemSelected: {
            Visibilities.setActiveModule("")
        }
    }
    
    onVisibleChanged: {
        if (visible) {
            Qt.callLater(() => {
                toolsMenu.forceActiveFocus();
            });
        }
    }
    
    Component.onCompleted: {
        if (visible) {
            Qt.callLater(() => {
                toolsMenu.forceActiveFocus();
            });
        }
    }
}
