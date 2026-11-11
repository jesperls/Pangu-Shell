pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services
import qs.modules.theme

Singleton {
    id: root

    property string clipboardMediaUrl: ""
    property bool activeDownload: false
    property int progressPercent: 0
    property string downloadMode: ""
    property string lastSavedFile: ""

    readonly property string scriptPath: Paths.script("media_grab.sh")

    function isMediaUrl(rawText) {
        const text = String(rawText || "").trim();
        if (text.length < 12 || text.length > 2048 || /\s/.test(text))
            return false;
        if (!/^https?:\/\//i.test(text))
            return false;
        if (/\.(mp4|webm|mkv|mov|m3u8|mp3|flac|ogg)(\?.*)?$/i.test(text))
            return true;
        return /^https?:\/\/(www\.|m\.|music\.)?(youtube\.com\/(watch|shorts|live|playlist)|youtu\.be\/|twitch\.tv\/|clips\.twitch\.tv\/|(x|twitter)\.com\/[^\/]+\/status\/|v\.redd\.it\/|reddit\.com\/r\/[^\/]+\/comments\/|tiktok\.com\/|vm\.tiktok\.com\/|vimeo\.com\/|soundcloud\.com\/|instagram\.com\/(reel|p)\/|streamable\.com\/)/i.test(text);
    }

    function shortHost(url) {
        const m = String(url || "").match(/^https?:\/\/(?:www\.|m\.)?([^\/]+)/i);
        return m ? m[1] : "media link";
    }

    function openInPip(url) {
        const target = String(url || root.clipboardMediaUrl || "").trim();
        if (!target)
            return;
        Quickshell.execDetached([
            "mpv",
            "--title=Picture-in-Picture",
            "--keepaspect-window",
            "--ontop",
            "--autofit=640x360",
            "--",
            target
        ]);
    }

    function downloadVideo(url) {
        _startDownload("video", "MP4", url);
    }

    function downloadAudio(url) {
        _startDownload("audio", "MP3", url);
    }

    function _startDownload(mode, label, url) {
        const target = String(url || root.clipboardMediaUrl || "").trim();
        if (!target || grabProcess.running)
            return;
        root.activeDownload = true;
        root.progressPercent = 0;
        root.downloadMode = label;
        root.lastSavedFile = "";
        grabProcess.command = [root.scriptPath, mode, target];
        grabProcess.running = true;
    }

    function entriesForLauncher(searchText) {
        const typed = String(searchText || "").trim();
        let target = "";
        let fromClipboard = false;
        if (typed !== "" && isMediaUrl(typed)) {
            target = typed;
        } else if (typed === "" && root.clipboardMediaUrl !== "") {
            target = root.clipboardMediaUrl;
            fromClipboard = true;
        }
        if (!target)
            return [];

        const host = shortHost(target);
        const prefix = fromClipboard ? ("Clipboard · " + host) : host;
        return [
            {
                id: "media-pip:" + target,
                name: "Open in Pinned PiP",
                icon: "font:" + Icons.pictureInPicture,
                comment: prefix + " — float & pin in mpv",
                execString: "",
                categories: [],
                runInTerminal: false,
                isAction: true,
                execute: () => root.openInPip(target)
            },
            {
                id: "media-mp4:" + target,
                name: "Save Video (MP4)",
                icon: "font:" + Icons.downloadSimple,
                comment: prefix + " — download to ~/Downloads",
                execString: "",
                categories: [],
                runInTerminal: false,
                isAction: true,
                execute: () => root.downloadVideo(target)
            },
            {
                id: "media-mp3:" + target,
                name: "Extract Audio (MP3)",
                icon: "font:" + Icons.musicNotes,
                comment: prefix + " — save MP3 to ~/Downloads",
                execString: "",
                categories: [],
                runInTerminal: false,
                isAction: true,
                execute: () => root.downloadAudio(target)
            }
        ];
    }

    function refreshClipboard() {
        if (!pasteProcess.running)
            pasteProcess.running = true;
    }

    Connections {
        target: ClipboardService
        function onRevisionChanged() {
            pasteDebounce.restart();
        }
    }

    Timer {
        id: pasteDebounce
        interval: 150
        onTriggered: root.refreshClipboard()
    }

    Component.onCompleted: Qt.callLater(() => root.refreshClipboard())

    Process {
        id: pasteProcess
        command: ["sh", "-c", "wl-paste --no-newline --type text/plain 2>/dev/null | head -c 2048 || true"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const candidate = text.trim();
                root.clipboardMediaUrl = root.isMediaUrl(candidate) ? candidate : "";
            }
        }
    }

    Process {
        id: grabProcess
        running: false
        stdout: SplitParser {
            onRead: line => {
                const s = String(line || "").trim();
                if (s.startsWith("PANGU_PROG:")) {
                    const num = parseFloat(s.slice(11).replace("%", "").trim());
                    if (Number.isFinite(num))
                        root.progressPercent = Math.max(0, Math.min(100, Math.round(num)));
                } else if (s.startsWith("PANGU_FILE:")) {
                    root.lastSavedFile = s.slice(11).trim();
                }
            }
        }
        onExited: code => {
            const saved = root.lastSavedFile;
            const modeLabel = root.downloadMode;
            root.activeDownload = false;
            root.progressPercent = 0;
            root.downloadMode = "";

            if (code === 0 && saved !== "") {
                const baseName = saved.split("/").pop() || saved;
                Notifications.notifyInternal({
                    summary: modeLabel + " Saved",
                    body: baseName,
                    actions: [
                        { identifier: "open", text: "Play" },
                        { identifier: "copy", text: "Copy File" }
                    ],
                    actionHandlers: {
                        open: function () {
                            ApplicationLauncher.launchCommand(["mpv", "--", saved]);
                        },
                        copy: function () {
                            Quickshell.execDetached(["bash", "-c", "printf 'file://%s\\r\\n' \"$1\" | wl-copy --type text/uri-list", "pangu-media-copy", saved]);
                        }
                    }
                });
            } else if (code !== 0) {
                Notifications.notifyInternal({
                    summary: "Media Download Failed",
                    body: "Could not grab media from URL"
                });
            }
        }
    }
}
