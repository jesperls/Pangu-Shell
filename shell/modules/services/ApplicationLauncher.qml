pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    function scopedCommand(command) {
        return ["systemd-run", "--user", "--scope", "--collect", "--quiet", "--slice=app.slice", "--property=PartOf=graphical-session.target", "--expand-environment=no", "--", "env", "-u", "HL_INITIAL_WORKSPACE_TOKEN"].concat(command);
    }

    function launchCommand(command) {
        if (!command || command.length === 0) return;
        Quickshell.execDetached({command: scopedCommand(command), workingDirectory: Paths.home});
    }

    function launchDesktop(appId, appName) {
        if (!appId) return;
        const launcher = desktopLauncher.createObject(root, {appId: appId, appName: appName || appId});
        launcher.running = true;
    }

    Component {
        id: desktopLauncher
        Process {
            property string appId
            property string appName
            command: root.scopedCommand(["bash", "-c", "exec gtk-launch -- \"$1\" </dev/null >/dev/null 2>&1", "bash", appId])
            workingDirectory: Paths.home
            onExited: code => {
                if (code === 0) UsageTracker.recordUsage(appId);
                else {
                    console.warn("Application launch failed:", appId, code);
                    Notifications.notifyInternal({
                        summary: "Could not open application",
                        body: appName + " failed to launch. Try again or check that it is still installed.",
                        replaceKey: "application-launch:" + appId
                    });
                }
                destroy();
            }
        }
    }
}
