import QtQuick
import qs.modules.components
import qs.modules.services
import qs.modules.theme
import Quickshell.Io

ActionGrid {
    id: root

    signal itemSelected

    layout: "row"
    buttonSize: 48
    iconSize: 20
    spacing: 8

    Process {
        id: actionProcess
        running: false
    }

    Component.onCompleted: {
        root.forceActiveFocus();
    }

    actions: [
        {
            icon: Icons.lock,
            tooltip: "Lock Session",
            run: () => LockscreenService.lock()
        },
        {
            icon: Icons.suspend,
            tooltip: "Suspend",
            command: "systemctl suspend"
        },
        {
            icon: Icons.hibernate,
            tooltip: "Hibernate",
            command: "systemctl hibernate"
        },
        {
            icon: Icons.logout,
            tooltip: "Exit Compositor",
            dispatch: "exit"
        },
        {
            icon: Icons.reboot,
            tooltip: "Reboot",
            command: "systemctl reboot"
        },
        {
            icon: Icons.shutdown,
            tooltip: "Power Off",
            command: "systemctl poweroff"
        }
    ]

    onActionTriggered: action => {
        if (action.run) {
            action.run();
        } else if (action.dispatch) {
            Compositor.dispatch(action.dispatch);
        } else if (action.command) {
            actionProcess.command = ["bash", "-c", action.command];
            actionProcess.running = true;
        }
        root.itemSelected();
    }
}
