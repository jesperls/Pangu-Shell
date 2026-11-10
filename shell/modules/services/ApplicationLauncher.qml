pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services

Singleton {
    id: root

    function scopedCommand(command) {
        const envArgs = ["env", "-u", "HL_INITIAL_WORKSPACE_TOKEN"];
        if (typeof Quickshell !== "undefined" && typeof Quickshell.env === "function") {
            const userPath = Quickshell.env("PANGU_USER_PATH");
            if (userPath !== null && userPath !== "")
                envArgs.push("PATH=" + userPath);
            for (const [saved, target] of [
                ["PANGU_USER_QT_PLUGIN_PATH", "QT_PLUGIN_PATH"],
                ["PANGU_USER_QML2_IMPORT_PATH", "QML2_IMPORT_PATH"],
                ["PANGU_USER_QML_IMPORT_PATH", "QML_IMPORT_PATH"]
            ]) {
                const val = Quickshell.env(saved);
                if (val === "__UNSET__")
                    envArgs.push("-u", target);
                else if (val !== null && val !== "")
                    envArgs.push(target + "=" + val);
            }
        }
        return [
            "systemd-run", "--user", "--scope", "--collect", "--quiet",
            "--slice=app.slice", "--property=PartOf=graphical-session.target",
            "--expand-environment=no", "--"
        ].concat(envArgs, command);
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
