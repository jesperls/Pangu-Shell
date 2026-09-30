import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property var files: []
    property var command: []
    property bool reloadPending: false

    function reload() {
        if (root.files.some(file => file.saving || file.savedText === null || (file.pendingText !== null && file.pendingText !== file.savedText)))
            return;
        root.reloadPending = process.running;
        if (!root.reloadPending)
            process.running = true;
    }

    property Process process: Process {
        id: process
        command: root.command
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn(text.trim())
        }
        onExited: if (root.reloadPending) Qt.callLater(root.reload)
    }
}
