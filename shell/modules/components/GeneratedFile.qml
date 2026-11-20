import QtQuick
import Quickshell.Io

FileView {
    id: root
    preload: false
    atomicWrites: true

    property bool directoryReady: false
    property bool saving: false
    property var pendingText: null
    property var savedText: null
    property string writingText: ""
    property bool resyncing: false
    property int writeFailures: 0
    signal written()
    signal failed()

    onPathChanged: {
        directoryReady = false;
        savedText = null;
    }

    function write(text) {
        writeFailures = 0;
        pendingText = text;
        startWrite();
    }

    function startWrite() {
        if (saving || resyncing || pendingText === null)
            return;
        if (!directoryReady) {
            prepareDirectory.running = true;
            return;
        }
        if (pendingText === savedText) {
            pendingText = null;
            written();
            return;
        }
        const text = pendingText;
        pendingText = null;
        if (text === "") {
            if (savedText === null || savedText === "") {
                savedText = "";
                written();
                return;
            }
            saving = true;
            writingText = "";
            truncateProcess.running = true;
            return;
        }
        saving = true;
        writingText = text;
        setText(text);
    }

    function finishResync() {
        if (!resyncing)
            return;
        resyncing = false;
        Qt.callLater(root.startWrite);
    }

    function finishWrite(success) {
        if (success) {
            writeFailures = 0;
            savedText = writingText;
            saving = false;
            if (pendingText === null || pendingText === savedText)
                written();
            Qt.callLater(root.startWrite); // FileView must finish its saved signal before starting another write.
            return;
        }
        // FileView caches failed writes; reload before retrying the same text.
        if (pendingText === null && writingText !== "")
            pendingText = writingText;
        writingText = "";
        saving = false;
        if (++writeFailures >= 3) {
            console.warn("Giving up on generated file:", path);
            failed();
            return;
        }
        resyncing = true;
        if (typeof reload === "function")
            reload();
    }

    onSaved: finishWrite(true)
    onSaveFailed: error => {
        console.warn("Generated file write failed:", path, error);
        finishWrite(false);
    }
    onLoaded: finishResync()
    onLoadFailed: finishResync()

    property Process truncateProcess: Process {
        id: truncateProcess
        command: ["truncate", "-s", "0", "--", root.path]
        onExited: code => root.finishWrite(code === 0)
    }

    property Process prepareDirectory: Process {
        id: prepareDirectory
        command: {
            const idx = root.path.lastIndexOf("/");
            return ["mkdir", "-p", "--", idx > 0 ? root.path.slice(0, idx) : "."];
        }
        onExited: code => {
            root.directoryReady = code === 0;
            if (root.directoryReady)
                Qt.callLater(root.startWrite);
            else {
                console.warn("Cannot create generated file directory:", root.path);
                root.failed();
            }
        }
    }
}
