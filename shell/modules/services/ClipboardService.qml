pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

QtObject {
    id: root

    property bool active: true
    property var items: []
    property var imageDataById: ({})
    property var linkPreviewCache: ({})
    property int revision: 0
    property bool _operationInProgress: false
    
    readonly property string dbPath: Quickshell.dataPath("clipboard.db")
    readonly property string binaryDataDir: Quickshell.dataPath("clipboard-data")
    readonly property string schemaPath: Qt.resolvedUrl("clipboard_init.sql").toString().replace("file://", "")
    readonly property string backendPath: Paths.script("clipboard.py")
    readonly property string watchScriptPath: Paths.script("clipboard_watch.sh")
    readonly property string linkPreviewScriptPath: Paths.script("link_preview.py")

    property bool _initialized: false
    property bool watcherEnabled: true
    property bool listPending: false

    property var suspendConnections: Connections {
        target: SuspendManager
        function onWakingUp() {
            wakeRestartTimer.restart();
        }
    }

    property var wakeRestartTimer: Timer {
        id: wakeRestartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root._initialized) {
                root.list();
                root.watcherEnabled = true;
            }
        }
    }

    signal listCompleted()

    property int watcherRestarts: 0

    property Process clipboardWatcher: Process {
        running: root._initialized && !SuspendManager.isSuspending && root.watcherEnabled
        command: [watchScriptPath, backendPath, dbPath, binaryDataDir]

        onStarted: watcherStableTimer.restart()
        
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.trim() === "REFRESH_LIST") {
                    Qt.callLater(root.list);
                }
            }
        }
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0 && !text.includes("No selection")) {
                    console.warn("ClipboardService: watcher stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (root._initialized && !SuspendManager.isSuspending) {
                root.watcherEnabled = false;
                root.watcherRestarts++;
                console.warn("ClipboardService: watcher exited with code:", code, "- restarting...");
                watcherRestartTimer.interval = Math.min(30000, 1000 * root.watcherRestarts);
                watcherRestartTimer.start();
            }
        }
    }

    property Timer watcherStableTimer: Timer {
        interval: 30000
        onTriggered: root.watcherRestarts = 0
    }

    property Timer watcherRestartTimer: Timer {
        interval: 1000
        repeat: false
        onTriggered: {
            if (root._initialized && !SuspendManager.isSuspending) {
                root.watcherEnabled = true;
            }
        }
    }

    property Process initDbProcess: Process {
        running: false
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) console.warn("ClipboardService: DB Init Error: " + text)
            }
        }

        onExited: function(code) {
            if (code === 0) {
                root._initialized = true;
                Qt.callLater(root.list);
            } else {
                console.warn("ClipboardService: Failed to initialize database (Exit code: " + code + ")");
            }
        }
    }

    property Process checkAndInsertProcess: Process {
        running: false
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0 && !text.includes("No selection")) {
                    console.warn("ClipboardService: checkAndInsertProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            _operationInProgress = false;
            if (code === 0) {
                Qt.callLater(root.list);
            }
        }
    }

    property Process listProcess: Process {
        running: false
        
        stdout: StdioCollector {
            waitForEnd: true
            
            onStreamFinished: {
                var clipboardItems = [];
                
                var trimmedText = text.trim();
                if (trimmedText.length === 0) {
                    root.items = clipboardItems;
                    root.listCompleted();
                    root._operationInProgress = false;
                    return;
                }
                
                try {
                    var jsonArray = JSON.parse(trimmedText);
                    
                    for (var i = 0; i < jsonArray.length; i++) {
                        var item = jsonArray[i];
                        var isFile = item.mime_type === "text/uri-list";
                        
                        var preview = item.preview;
                        if (isFile && item.full_content) {
                            var uriContent = item.full_content.trim();
                            if (uriContent.startsWith("file://")) {
                                var filePath = uriContent.substring(7);  // Remove "file://"
                                var fileName = filePath.split('/').pop();
                                fileName = root.decodeUriString(fileName);
                                preview = "[File] " + fileName;
                            }
                        } else if (item.is_image === 1) {
                            preview = "[Image]";
                        }
                        
                        clipboardItems.push({
                            id: item.id.toString(),
                            preview: preview,
                            fullContent: item.preview,
                            mime: item.mime_type,
                            isImage: item.is_image === 1,
                            isFile: isFile,
                            binaryPath: item.binary_path || "",
                            hash: item.content_hash || "",
                            size: item.size || 0,
                            createdAt: item.created_at || 0,
                            pinned: item.pinned === 1,
                            alias: item.alias || "",
                            displayIndex: item.display_index !== null ? item.display_index : -1
                        });
                    }
                } catch (e) {
                    console.warn("ClipboardService: Failed to parse clipboard items:", e);
                }
                
                root.items = clipboardItems;
                root.listCompleted();
                root._operationInProgress = false;
            }
        }
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ClipboardService: listProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (root.listPending) {
                root.listPending = false;
                Qt.callLater(root.list);
            }
            if (code !== 0) {
                root.items = [];
                root.listCompleted();
                root._operationInProgress = false;
            }
        }
    }

    property Process getContentProcess: Process {
        property var pending: []
        property string itemId: ""
        stdout: StdioCollector {}
        onExited: code => {
            root.fullContentRetrieved(itemId, code === 0 ? stdout.text : "");
            Qt.callLater(root.startNext, getContentProcess);
        }
    }

    property Process deleteProcess: Process {
        property string itemId: ""
        running: false
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ClipboardService: deleteProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (code === 0) {
                Qt.callLater(root.list);
            } else {
                root._operationInProgress = false;
            }
        }
    }
    
    property Process clearProcess: Process {
        running: false
        
        onExited: function(code) {
            if (code === 0) {
                Qt.callLater(root.list);
            }
        }
    }
    
    property Process togglePinProcess: Process {
        property string itemId: ""
        running: false
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ClipboardService: togglePinProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (code === 0) {
                Qt.callLater(root.list);
            } else {
                root._operationInProgress = false;
            }
        }
    }
    
    property Process setAliasProcess: Process {
        property string itemId: ""
        running: false
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ClipboardService: setAliasProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (code === 0) {
                Qt.callLater(root.list);
            } else {
                root._operationInProgress = false;
            }
        }
    }
    
    property Process loadImageProcess: Process {
        property var pending: []
        property string itemId: ""
        property string mimeType: ""
        stdout: StdioCollector {}
        onExited: code => {
            if (code === 0 && stdout.text.length > 0) {
                root.imageDataById[itemId] = "data:" + mimeType + ";base64," + stdout.text.replace(/\s/g, "");
                root.revision++;
            }
            Qt.callLater(root.startNext, loadImageProcess);
        }
    }

    property Process linkPreviewProcess: Process {
        property var pending: []
        property string requestUrl: ""
        property string requestItemId: ""
        stdout: StdioCollector {}
        onExited: code => {
            let metadata;
            try {
                if (code !== 0) throw new Error("Preview process failed");
                metadata = JSON.parse(stdout.text);
                if (!metadata.error) root.linkPreviewCache[requestUrl] = metadata;
            } catch (error) {
                metadata = {error: String(error)};
            }
            root.linkPreviewFetched(requestUrl, metadata, requestItemId);
            Qt.callLater(root.startNext, linkPreviewProcess);
        }
    }

    function enqueue(process, request) {
        process.pending = process.pending.concat([request]);
        root.startNext(process);
    }

    function startNext(process) {
        if (process.running || process.pending.length === 0) return;
        const request = process.pending[0];
        process.pending = process.pending.slice(1);
        for (const key of Object.keys(request)) process[key] = request[key];
        process.running = true;
    }

    signal fullContentRetrieved(string itemId, string content)
    signal linkPreviewFetched(string url, var metadata, string itemId)
    
    function decodeUriString(str) {
        try {
            return decodeURIComponent(str);
        } catch (e) {
            return str;
        }
    }

    function backend(operation, args = []) {
        return ["python3", backendPath, dbPath, operation, "--"].concat(args);
    }

    function initialize() {
        initDbProcess.command = backend("init", [schemaPath]);
        initDbProcess.running = true;
    }

    function checkClipboard() {
        if (!_initialized || _operationInProgress) return;
        _operationInProgress = true;
        checkAndInsertProcess.command = backend("capture", [binaryDataDir]);
        checkAndInsertProcess.running = true;
    }

    function list() {
        if (!_initialized) return;
        if (listProcess.running) {
            root.listPending = true;
            return;
        }
        _operationInProgress = true;
        listProcess.command = backend("list");
        listProcess.running = true;
    }

    function getFullContent(id) {
        if (!_initialized) return;
        enqueue(getContentProcess, {itemId: id, command: backend("content", [id])});
    }

    function deleteItem(id) {
        if (!_initialized) return;
        _operationInProgress = true;
        deleteProcess.itemId = id;
        
        deleteProcess.command = backend("delete", [id, binaryDataDir]);
        deleteProcess.running = true;
    }

    function clear() {
        if (!_initialized) return;
        clearProcess.command = backend("clear", [binaryDataDir]);
        clearProcess.running = true;
    }

    function togglePin(id) {
        if (!_initialized) return;
        _operationInProgress = true;
        togglePinProcess.itemId = id;
        togglePinProcess.command = backend("pin", [id]);
        togglePinProcess.running = true;
    }

    function setAlias(id, alias) {
        if (!_initialized) return;
        _operationInProgress = true;
        setAliasProcess.itemId = id;
        setAliasProcess.command = backend("alias", [id, alias.trim()]);
        setAliasProcess.running = true;
    }

    function decodeToDataUrl(id, mime) {
        if (imageDataById[id]) {
            return;
        }
        
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === id) {
                var binaryPath = items[i].binaryPath;
                if (binaryPath && binaryPath.length > 0) {
                    enqueue(loadImageProcess, {itemId: id, mimeType: mime, command: ["base64", "-w", "0", binaryPath]});
                }
                break;
            }
        }
    }

    function getImageData(id) {
        return imageDataById[id] || "";
    }
    
    function fetchLinkPreview(url, itemId) {
        if (!_initialized) return;
        
        if (linkPreviewCache[url]) {
            Qt.callLater(function() {
                root.linkPreviewFetched(url, linkPreviewCache[url], itemId);
            });
            return;
        }
        
        enqueue(linkPreviewProcess, {requestUrl: url, requestItemId: itemId, command: ["python3", linkPreviewScriptPath, url, "5"]});
    }
    
    function moveItemUp(itemId) {
        var item = null;
        var currentIdx = -1;
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === itemId) {
                item = items[i];
                currentIdx = i;
                break;
            }
        }
        
        if (!item || currentIdx < 0) return;
        
        if (currentIdx === 0) return;
        
        var prevItem = items[currentIdx - 1];
        if (prevItem.pinned !== item.pinned) return;
        
        var temp = items[currentIdx];
        items[currentIdx] = items[currentIdx - 1];
        items[currentIdx - 1] = temp;
        
        listCompleted();
        
        swapItems(itemId, prevItem.id);
    }
    
    function moveItemDown(itemId) {
        var item = null;
        var currentIdx = -1;
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === itemId) {
                item = items[i];
                currentIdx = i;
                break;
            }
        }
        
        if (!item || currentIdx < 0) return;
        
        if (currentIdx >= items.length - 1) return;
        
        var nextItem = items[currentIdx + 1];
        if (nextItem.pinned !== item.pinned) return;
        
        var temp = items[currentIdx];
        items[currentIdx] = items[currentIdx + 1];
        items[currentIdx + 1] = temp;
        
        listCompleted();
        
        swapItems(itemId, nextItem.id);
    }
    
    function swapItems(itemId1, itemId2) {
        if (!_initialized) return;
        
        var proc = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
        proc.command = backend("swap", [itemId1, itemId2]);

        proc.onExited.connect(function(code) {
             if (code === 0) {
                 Qt.callLater(root.list);
             } else {
                 console.warn("ClipboardService: dynamic swapProcess failed with code:", code);
             }
             proc.destroy();
        });
        
        proc.running = true;
    }
    
    property Process emojiTypeProcess: Process {
        running: false
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ClipboardService: emojiTypeProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (code !== 0) {
                console.warn("ClipboardService: emojiTypeProcess failed with code:", code);
            }
        }
    }
    
    property Timer emojiTypeTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: {
            emojiTypeProcess.command = ["wtype", "-M", "ctrl", "-P", "v", "-p", "v", "-m", "ctrl"];
            emojiTypeProcess.running = true;
        }
    }
    
    property Process emojiCopyProcess: Process {
        running: false

        onExited: code => {
            if (code === 0) emojiTypeTimer.restart();
        }
    }

    function copyAndTypeEmoji(emojiText) {
        emojiCopyProcess.command = ["wl-copy", "--", emojiText];
        emojiCopyProcess.running = true;

    }

    Component.onCompleted: {
        Qt.callLater(() => initialize());
    }
}
