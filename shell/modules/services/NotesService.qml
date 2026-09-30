pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    property var notes: []
    property var documents: Object.create(null)
    property var pending: []
    property var currentJob: null
    property int nextReadToken: 0
    property bool ready: false
    property string error: ""
    readonly property bool unsaved: Object.keys(documents).some(id => documents[id].dirty)

    signal noteChanged(string noteId, string origin)
    signal created(string noteId, string origin)

    function document(id) {
        return documents[id] || null;
    }

    function setDocument(id, document) {
        const next = Object.assign(Object.create(null), documents);
        next[id] = document;
        documents = next;
    }

    function enqueue(request) {
        pending = pending.concat([request]);
        startNext();
    }

    function startNext() {
        if (currentJob || pending.length === 0) return;
        const job = pending[0];
        pending = pending.slice(1);
        if (job.action === "save") {
            const doc = document(job.id);
            if (!doc || !doc.dirty || !doc.loaded) {
                Qt.callLater(root.startNext);
                return;
            }
            job.content = doc.content;
            job.revision = doc.revision;
            job.version = doc.version;
        }
        currentJob = job;
        worker.running = true;
    }

    function refresh() {
        enqueue({action: "list"});
    }

    function load(id) {
        const doc = document(id);
        if (doc && (doc.loaded || doc.loading)) return;
        const token = ++nextReadToken;
        setDocument(id, {content: "", loaded: false, loading: true, dirty: false, version: 0, readToken: token});
        enqueue({action: "read", id: id, readToken: token});
    }

    function edit(id, content, origin) {
        const doc = document(id);
        if (!doc || !doc.loaded || doc.content === content) return;
        setDocument(id, Object.assign({}, doc, {content: content, version: doc.version + 1, dirty: true}));
        noteChanged(id, origin);
        autosave.restart();
    }

    function queueSave(id) {
        if (!pending.some(job => job.action === "save" && job.id === id))
            enqueue({action: "save", id: id});
    }

    function flush() {
        for (const id of Object.keys(documents))
            if (documents[id].dirty) queueSave(id);
    }

    function create(title, markdown, origin) {
        enqueue({action: "create", title: title, isMarkdown: markdown, origin: origin});
    }

    function rename(id, title) {
        enqueue({action: "rename", id: id, title: title});
    }

    function move(id, direction) {
        enqueue({action: "move", id: id, direction: direction});
    }

    function remove(id) {
        queueSave(id);
        enqueue({action: "delete", id: id});
    }

    function retry() {
        error = "";
        flush();
        for (const id of Object.keys(documents))
            if (!documents[id].loaded && !documents[id].loading) load(id);
        refresh();
    }

    function reload(id) {
        error = "";
        const next = Object.assign(Object.create(null), documents);
        delete next[id];
        documents = next;
        pending = pending.filter(job => job.id !== id || job.action !== "save");
        load(id);
        noteChanged(id, "");
    }

    function finish(result) {
        const job = currentJob;
        if (!job) return;
        if (job.action === "read" && document(job.id)?.readToken !== job.readToken) {
            currentJob = null;
            Qt.callLater(root.startNext);
            return;
        }
        if (!result.ok) {
            error = result.error || "Could not update notes";
            if (job.action === "read") {
                setDocument(job.id, {content: "", loaded: false, loading: false, dirty: false, version: 0});
                noteChanged(job.id, "");
            }
        } else {
            if (result.notes) {
                ready = true;
                notes = result.notes;
            }
            if (job.action === "read") {
                setDocument(job.id, {content: result.content, revision: result.revision, loaded: true, loading: false, dirty: false, version: 0});
                noteChanged(job.id, "");
            } else if (job.action === "save") {
                const doc = document(job.id);
                if (doc && doc.loaded) {
                    setDocument(job.id, Object.assign({}, doc, {revision: result.revision, dirty: doc.version !== job.version}));
                    noteChanged(job.id, "");
                }
            } else if (job.action === "create") {
                created(result.id, job.origin || "");
            } else if (job.action === "delete") {
                const next = Object.assign(Object.create(null), documents);
                delete next[job.id];
                documents = next;
                noteChanged(job.id, "");
            }
        }
        currentJob = null;
        Qt.callLater(root.startNext);
    }

    Timer {
        id: autosave
        interval: 500
        onTriggered: root.flush()
    }

    Process {
        id: worker
        command: ["python3", Paths.script("notes.py"), Paths.notesDir]
        stdinEnabled: true
        onStarted: {
            write(JSON.stringify(root.currentJob));
            stdinEnabled = false;
        }
        stdout: StdioCollector { id: response; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: code => {
            let result;
            try { result = JSON.parse(response.text); }
            catch (_) { result = {ok: false, error: "Notes operation failed (exit " + code + ")"}; }
            stdinEnabled = true;
            root.finish(result);
        }
    }

    Component.onCompleted: refresh()
}
