pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import QtQuick
import qs.modules.globals
import qs.config

Singleton {
    id: root

    property bool _firstStartOfSession: false
    property bool _hasPanguPam: false
    property bool _hasHyprlockPam: false
    property bool _hasLoginPam: false
    property bool authenticating: false
    property bool showError: false
    property string errorMessage: ""
    property string _pendingPassword: ""
    property string currentUser: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""

    signal unlocked()
    signal authFailed()

    function resolvePamTarget(hasPangu, hasHyprlock, hasLogin, shellDir) {
        if (hasPangu)
            return { directory: "/etc/pam.d", config: "pangu" };
        if (hasHyprlock)
            return { directory: "/etc/pam.d", config: "hyprlock" };
        if (hasLogin)
            return { directory: "/etc/pam.d", config: "login" };
        return { directory: (shellDir || ".") + "/config/pam", config: "password.conf" };
    }

    readonly property var _pamTarget: resolvePamTarget(
        root._hasPanguPam,
        root._hasHyprlockPam,
        root._hasLoginPam,
        typeof Paths !== "undefined" ? Paths.shellDir : "."
    )

    FileView {
        path: "/etc/pam.d/pangu"
        preload: true
        printErrors: false
        onLoaded: root._hasPanguPam = true
        onLoadFailed: root._hasPanguPam = false
    }

    FileView {
        path: "/etc/pam.d/hyprlock"
        preload: true
        printErrors: false
        onLoaded: root._hasHyprlockPam = true
        onLoadFailed: root._hasHyprlockPam = false
    }

    FileView {
        path: "/etc/pam.d/login"
        preload: true
        printErrors: false
        onLoaded: root._hasLoginPam = true
        onLoadFailed: root._hasLoginPam = false
    }

    Process {
        id: userFallbackProc
        running: root.currentUser === ""
        command: ["id", "-un"]
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                if (name !== "")
                    root.currentUser = name;
            }
        }
    }

    Process {
        id: bootProbe
        running: true
        command: ["mkdir", "--", (Quickshell.env("XDG_RUNTIME_DIR") || (typeof Paths !== "undefined" ? Paths.cacheDir : "/tmp")) + "/pangu-session-started"]
        onExited: code => {
            root._firstStartOfSession = code === 0;
            root.maybeBootLock();
        }
    }

    Connections {
        target: Config
        function onInitialLoadCompleteChanged() {
            root.maybeBootLock();
        }
    }

    PamContext {
        id: pamAuth
        configDirectory: root._pamTarget.directory
        config: root._pamTarget.config

        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root._pendingPassword);
            } else if (this.isError && this.message) {
                root.errorMessage = this.message;
            }
        }

        onCompleted: result => {
            root._pendingPassword = "";
            root.authenticating = false;
            if (result === PamResult.Success) {
                root.showError = false;
                root.errorMessage = "";
                root.unlocked();
            } else {
                root.showError = true;
                if (!root.errorMessage)
                    root.errorMessage = "Authentication failed";
                root.authFailed();
            }
        }
    }

    function authenticate(password: string) {
        if (root.authenticating || password.length === 0)
            return;
        root.showError = false;
        root.errorMessage = "";
        root._pendingPassword = password;
        root.authenticating = true;
        pamAuth.start();
    }

    function clearError() {
        root.showError = false;
        root.errorMessage = "";
    }

    function maybeBootLock() {
        if (root._firstStartOfSession && Config.initialLoadComplete && Config.lockscreen.lockOnBoot) {
            root._firstStartOfSession = false;
            root.lock();
        }
    }

    function toggle() {
        root.lock();
    }

    function lock() {
        root.clearError();
        GlobalStates.lockscreenVisible = true;
    }

    property IpcHandler ipc: IpcHandler {
        target: "lockscreen"

        function toggle() {
            root.toggle();
        }

        function lock() {
            root.lock();
        }
    }
}
