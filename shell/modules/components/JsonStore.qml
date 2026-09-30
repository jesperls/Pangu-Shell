import QtQuick
import Quickshell.Io

FileView {
    id: root

    property string filePath: ""
    property bool directoryReady: false
    property bool ready: false
    property var data: ({})
    property var normalize: null
    signal dataLoaded

    path: root.directoryReady ? root.filePath : ""
    atomicWrites: true
    preload: true

    function finish(value) {
        if (root.ready)
            return;
        root.data = root.normalize ? root.normalize(value) : ((value && typeof value === "object" && !Array.isArray(value)) ? value : {});
        root.ready = true;
        root.dataLoaded();
    }

    onLoaded: {
        try {
            root.finish(JSON.parse(text()));
        } catch (error) {
            console.warn("Unreadable JSON store:", root.filePath, error);
            root.finish(null);
        }
    }
    onLoadFailed: root.finish(null)

    function save() {
        setText(JSON.stringify(root.data, null, 2));
    }

    property Process prepareDirectory: Process {
        id: prepareDirectory
        command: ["mkdir", "-p", "--", root.filePath.slice(0, root.filePath.lastIndexOf("/"))]
        onExited: code => {
            root.directoryReady = code === 0;
            if (code !== 0) {
                console.warn("Cannot create JSON store directory:", root.filePath);
                root.finish(null);
            }
        }
    }

    Component.onCompleted: prepareDirectory.running = true
}
