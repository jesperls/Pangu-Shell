pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services

Singleton {
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
    readonly property int maxItems: Math.max(10, Config.system.clipboard?.maxItems ?? 200)

    property bool _initialized: false
    property bool watcherEnabled: true
    property bool listPending: false

    Connections {
        target: SuspendManager
        function onWakingUp() {
            wakeRestartTimer.restart();
        }
    }

    Timer {
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

    Process {
        id: clipboardWatcher
        running: root._initialized && !SuspendManager.isSuspending && root.watcherEnabled
        command: [root.watchScriptPath, root.backendPath, root.dbPath, root.binaryDataDir, String(root.maxItems)]

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

        onExited: code => {
            if (root._initialized && !SuspendManager.isSuspending) {
                root.watcherEnabled = false;
                root.watcherRestarts++;
                console.warn("ClipboardService: watcher exited with code:", code, "- restarting...");
                watcherRestartTimer.interval = Math.min(30000, 1000 * root.watcherRestarts);
                watcherRestartTimer.start();
            }
        }
    }

    Timer {
        id: watcherStableTimer
        interval: 30000
        onTriggered: root.watcherRestarts = 0
    }

    Timer {
        id: watcherRestartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root._initialized && !SuspendManager.isSuspending) {
                root.watcherEnabled = true;
            }
        }
    }

    Process {
        id: initDbProcess
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) console.warn("ClipboardService: DB Init Error:", text);
            }
        }

        onExited: code => {
            if (code === 0) {
                root._initialized = true;
                Qt.callLater(root.list);
            } else {
                console.warn("ClipboardService: Failed to initialize database (exit " + code + ")");
            }
        }
    }

    Process {
        id: checkAndInsertProcess
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0 && !text.includes("No selection")) {
                    console.warn("ClipboardService: capture stderr:", text);
                }
            }
        }

        onExited: code => {
            root._operationInProgress = false;
            if (code === 0) {
                Qt.callLater(root.list);
            }
        }
    }

    function pruneCaches(items) {
        const activeIds = {};
        for (let i = 0; i < items.length; i++)
            activeIds[items[i].id] = true;

        const nextImages = {};
        let imagesPruned = false;
        for (const id in root.imageDataById) {
            if (activeIds[id])
                nextImages[id] = root.imageDataById[id];
            else
                imagesPruned = true;
        }
        if (imagesPruned)
            root.imageDataById = nextImages;

        const previewKeys = Object.keys(root.linkPreviewCache);
        if (previewKeys.length > 100) {
            const nextPreviews = {};
            const keep = previewKeys.slice(-100);
            for (const k of keep)
                nextPreviews[k] = root.linkPreviewCache[k];
            root.linkPreviewCache = nextPreviews;
        }
    }

    Process {
        id: listProcess
        running: false

        stdout: StdioCollector {
            waitForEnd: true

            onStreamFinished: {
                const clipboardItems = [];
                const trimmedText = text.trim();
                if (trimmedText.length === 0) {
                    root.items = clipboardItems;
                    root.pruneCaches(clipboardItems);
                    root.listCompleted();
                    root._operationInProgress = false;
                    return;
                }

                try {
                    const jsonArray = JSON.parse(trimmedText);
                    for (let i = 0; i < jsonArray.length; i++) {
                        const item = jsonArray[i];
                        const isFile = item.mime_type === "text/uri-list";
                        const fullText = item.full_content || item.preview || "";

                        let preview = item.preview || "";
                        if (isFile && fullText) {
                            const uriContent = fullText.trim();
                            if (uriContent.startsWith("file://")) {
                                const filePath = uriContent.substring(7);
                                const fileName = root.decodeUriString(filePath.split("/").pop());
                                preview = "[File] " + fileName;
                            }
                        } else if (item.is_image === 1) {
                            preview = "[Image]";
                        }

                        clipboardItems.push({
                            id: item.id.toString(),
                            preview: preview,
                            fullContent: fullText,
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
                root.pruneCaches(clipboardItems);
                root.listCompleted();
                root._operationInProgress = false;
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0)
                    console.warn("ClipboardService: list stderr:", text);
            }
        }

        onExited: code => {
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

    Process {
        id: getContentProcess
        property var pending: []
        property string itemId: ""
        stdout: StdioCollector {}
        onExited: code => {
            root.fullContentRetrieved(getContentProcess.itemId, code === 0 ? getContentProcess.stdout.text : "");
            Qt.callLater(root.startNext, getContentProcess);
        }
    }

    Process {
        id: mutationProcess
        property var pending: []
        property string itemId: ""
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0)
                    console.warn("ClipboardService: mutation stderr:", text);
            }
        }
        onExited: code => {
            if (code === 0 && mutationProcess.pending.length === 0) {
                Qt.callLater(root.list);
            } else if (code !== 0) {
                root._operationInProgress = false;
            }
            Qt.callLater(root.startNext, mutationProcess);
        }
    }

    Process {
        id: loadImageProcess
        property var pending: []
        property string itemId: ""
        property string mimeType: ""
        stdout: StdioCollector {}
        onExited: code => {
            if (code === 0 && loadImageProcess.stdout.text.length > 0) {
                const next = Object.assign({}, root.imageDataById);
                next[loadImageProcess.itemId] = "data:" + loadImageProcess.mimeType + ";base64," + loadImageProcess.stdout.text.replace(/\s/g, "");
                root.imageDataById = next;
                root.revision++;
            }
            Qt.callLater(root.startNext, loadImageProcess);
        }
    }

    Process {
        id: linkPreviewProcess
        property var pending: []
        property string requestUrl: ""
        property string requestItemId: ""
        stdout: StdioCollector {}
        onExited: code => {
            let metadata;
            try {
                if (code !== 0) throw new Error("Preview process failed");
                metadata = JSON.parse(linkPreviewProcess.stdout.text);
                if (!metadata.error) root.linkPreviewCache[linkPreviewProcess.requestUrl] = metadata;
            } catch (error) {
                metadata = {error: String(error)};
            }
            root.linkPreviewFetched(linkPreviewProcess.requestUrl, metadata, linkPreviewProcess.requestItemId);
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
        return ["python3", root.backendPath, root.dbPath, operation, "--"].concat(args);
    }

    function initialize() {
        initDbProcess.command = backend("init", [root.schemaPath]);
        initDbProcess.running = true;
    }

    function checkClipboard() {
        if (!_initialized || _operationInProgress) return;
        _operationInProgress = true;
        checkAndInsertProcess.command = backend("capture", [root.binaryDataDir, String(root.maxItems)]);
        checkAndInsertProcess.running = true;
    }

    function list() {
        if (!_initialized) return;
        if (listProcess.running) {
            root.listPending = true;
            return;
        }
        _operationInProgress = true;
        listProcess.command = backend("list", [String(root.maxItems)]);
        listProcess.running = true;
    }

    function getFullContent(id) {
        if (!_initialized) return;
        enqueue(getContentProcess, {itemId: id, command: backend("content", [id])});
    }

    function deleteItem(id) {
        if (!_initialized) return;
        _operationInProgress = true;
        enqueue(mutationProcess, {itemId: id, command: backend("delete", [id, root.binaryDataDir])});
    }

    function clear() {
        if (!_initialized) return;
        _operationInProgress = true;
        enqueue(mutationProcess, {itemId: "", command: backend("clear", [root.binaryDataDir])});
    }

    function togglePin(id) {
        if (!_initialized) return;
        _operationInProgress = true;
        enqueue(mutationProcess, {itemId: id, command: backend("pin", [id])});
    }

    function setAlias(id, alias) {
        if (!_initialized) return;
        _operationInProgress = true;
        enqueue(mutationProcess, {itemId: id, command: backend("alias", [id, alias.trim()])});
    }

    function decodeToDataUrl(id, mime) {
        if (imageDataById[id])
            return;
        for (let i = 0; i < items.length; i++) {
            if (items[i].id === id) {
                const binaryPath = items[i].binaryPath;
                if (binaryPath && binaryPath.length > 0)
                    enqueue(loadImageProcess, {itemId: id, mimeType: mime, command: ["base64", "-w", "0", binaryPath]});
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
            Qt.callLater(() => root.linkPreviewFetched(url, root.linkPreviewCache[url], itemId));
            return;
        }
        enqueue(linkPreviewProcess, {requestUrl: url, requestItemId: itemId, command: ["python3", root.linkPreviewScriptPath, url, "5"]});
    }

    function moveItemUp(itemId) {
        const currentIdx = items.findIndex(entry => entry.id === itemId);
        if (currentIdx <= 0) return;

        const item = items[currentIdx];
        const prevItem = items[currentIdx - 1];
        if (prevItem.pinned !== item.pinned) return;

        const next = items.slice();
        next[currentIdx] = prevItem;
        next[currentIdx - 1] = item;
        root.items = next;
        root.listCompleted();
        swapItems(itemId, prevItem.id);
    }

    function moveItemDown(itemId) {
        const currentIdx = items.findIndex(entry => entry.id === itemId);
        if (currentIdx < 0 || currentIdx >= items.length - 1) return;

        const item = items[currentIdx];
        const nextItem = items[currentIdx + 1];
        if (nextItem.pinned !== item.pinned) return;

        const next = items.slice();
        next[currentIdx] = nextItem;
        next[currentIdx + 1] = item;
        root.items = next;
        root.listCompleted();
        swapItems(itemId, nextItem.id);
    }

    function swapItems(itemId1, itemId2) {
        if (!_initialized) return;
        enqueue(mutationProcess, {itemId: itemId1, command: backend("swap", [itemId1, itemId2])});
    }

    property string _pendingEmoji: ""

    Process {
        id: emojiTypeProcess
        running: false
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0)
                    console.warn("ClipboardService: emojiTypeProcess stderr:", text);
            }
        }
    }

    Timer {
        id: emojiTypeTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (root._pendingEmoji !== "") {
                emojiTypeProcess.command = ["wtype", "--", root._pendingEmoji];
                emojiTypeProcess.running = true;
            }
        }
    }

    Process {
        id: emojiCopyProcess
        running: false
        onExited: code => {
            if (code === 0) emojiTypeTimer.restart();
        }
    }

    function copyAndTypeEmoji(emojiText) {
        root._pendingEmoji = emojiText;
        emojiCopyProcess.command = ["wl-copy", "--", emojiText];
        emojiCopyProcess.running = true;
    }

    Component.onCompleted: Qt.callLater(() => root.initialize())
}
