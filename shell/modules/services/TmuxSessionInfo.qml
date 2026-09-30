import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property string sessionName: ""
    property var windows: []
    property var panes: []
    property bool loading: false
    property int generation: 0
    property int currentGeneration: -1
    property bool pending: false

    onSessionNameChanged: refresh()

    function refresh() {
        generation++;
        windows = [];
        panes = [];
        loading = sessionName !== "";
        pending = loading;
        Qt.callLater(root.startNext);
    }

    function startNext() {
        if (!pending || windowsProcess.running || panesProcess.running) return;
        pending = false;
        currentGeneration = generation;
        windowsProcess.command = ["tmux", "list-windows", "-t", sessionName, "-F", "#{window_index}:#{window_active}:#{window_name}"];
        panesProcess.command = ["tmux", "list-panes", "-t", sessionName, "-F", "#{pane_index}:#{pane_width}:#{pane_height}:#{pane_top}:#{pane_left}:#{pane_active}:#{pane_current_command}"];
        windowsProcess.running = true;
        panesProcess.running = true;
    }

    function parseWindows(text) {
        const result = [];
        for (const line of text.split("\n")) {
            const parts = line.split(":");
            if (parts.length >= 3 && /^\d+$/.test(parts[0]))
                result.push({index: parts[0], active: parts[1] === "1", name: parts.slice(2).join(":")});
        }
        return result;
    }

    function parsePanes(text) {
        const result = [];
        let totalWidth = 0, totalHeight = 0;
        for (const line of text.split("\n")) {
            const parts = line.split(":");
            if (parts.length < 7 || !parts.slice(0, 5).every(part => /^\d+$/.test(part))) continue;
            const width = Number(parts[1]), height = Number(parts[2]);
            if (width <= 0 || height <= 0) continue;
            const top = Number(parts[3]), left = Number(parts[4]);
            totalWidth = Math.max(totalWidth, left + width);
            totalHeight = Math.max(totalHeight, top + height);
            result.push({index: parts[0], width: width, height: height, top: top, left: left,
                active: parts[5] === "1", command: parts.slice(6).join(":")});
        }
        return result.map(pane => Object.assign(pane, {totalWidth: totalWidth, totalHeight: totalHeight}));
    }

    function finish() {
        if (windowsProcess.running || panesProcess.running) return;
        if (currentGeneration === generation) loading = false;
        Qt.callLater(root.startNext);
    }

    Process {
        id: windowsProcess
        stdout: StdioCollector { id: windowsOutput; waitForEnd: true }
        onExited: code => {
            if (root.currentGeneration === root.generation)
                root.windows = code === 0 ? root.parseWindows(windowsOutput.text) : [];
            root.finish();
        }
    }

    Process {
        id: panesProcess
        stdout: StdioCollector { id: panesOutput; waitForEnd: true }
        onExited: code => {
            if (root.currentGeneration === root.generation)
                root.panes = code === 0 ? root.parsePanes(panesOutput.text) : [];
            root.finish();
        }
    }
}
