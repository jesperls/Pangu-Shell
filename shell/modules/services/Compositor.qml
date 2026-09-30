pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    readonly property QtObject clients: QtObject {
        property var values: []
    }

    readonly property QtObject monitors: QtObject {
        property var values: []
    }

    readonly property QtObject workspaces: QtObject {
        property var values: []
    }

    readonly property var focusedMonitor: root.monitorFor(Hyprland.focusedMonitor)
    readonly property var focusedWorkspace: workspaces.values.find(w => w.active) ?? null
    readonly property var focusedClient: clients.values.find(c => c.is_focused) ?? null

    readonly property var windowList: root.clients.values
    readonly property var workspaceOccupationMap: {
        const map = {};
        for (const win of (root.clients.values ?? []))
            map[win.workspace.id] = true;
        return map;
    }
    readonly property var workspaceWindowsMap: {
        const map = {};
        for (const win of (root.clients.values ?? [])) {
            const id = win.workspace.id;
            if (!map[id])
                map[id] = [];
            map[id].push(win);
        }
        return map;
    }

    property var gaps: ({})

    function gapFor(screenName) {
        return root.gaps[screenName] ?? null;
    }

    function handleRawEvent(event) {
        if (event.name !== "custom" || !event.data)
            return;
        const parts = event.data.split(",");
        if (parts[0] !== "centergap")
            return;
        if (parts.length < 4)
            return true;
        const name = parts[1];
        const x = Number(parts[2]);
        const width = Number(parts[3]);
        if (!name || !Number.isFinite(x) || !Number.isFinite(width))
            return true;
        const square = parts[4] === "1";
        const next = Object.assign({}, root.gaps);
        if (!width || width <= 0) {
            if (!(name in next))
                return true;
            delete next[name];
        } else {
            const prev = next[name];
            if (prev && prev.x === x && prev.width === width && prev.square === square)
                return true;
            next[name] = {
                x: x,
                width: width,
                square: square
            };
        }
        root.gaps = next;
        return true;
    }

    function logicalSize(monitor) {
        const rotated = (monitor.transform || 0) % 2 === 1;
        const scale = monitor.scale || 1;
        return {
            width: (rotated ? monitor.height : monitor.width) / scale,
            height: (rotated ? monitor.width : monitor.height) / scale
        };
    }

    function luaString(value) {
        return '"' + String(value).replace(/["\\\u0000-\u001f\u007f]/g, c => {
            if (c === '"' || c === "\\") return "\\" + c;
            return "\\" + String(c.charCodeAt(0)).padStart(3, "0");
        }) + '"';
    }

    function windowTarget(address) {
        const value = String(address).replace(/^address:/, "");
        return "address:" + (/^[0-9a-f]+$/i.test(value) ? "0x" + value : value);
    }

    function moveFloatingWindow(address, workspace, xRatio, yRatio) {
        if (!address || !Number.isInteger(workspace) || workspace <= 0
                || !Number.isFinite(xRatio) || !Number.isFinite(yRatio))
            return;
        root.request(`eval local w = hl.get_window(${root.luaString(root.windowTarget(address))})
if w then
    hl.dispatch(hl.dsp.window.move({ workspace = ${workspace}, follow = false, window = w }))
    local m = w.workspace and w.workspace.monitor
    if m and w.floating then
        local width, height = m.width, m.height
        if m.transform % 2 == 1 then width, height = height, width end
        hl.dispatch(hl.dsp.window.move({
            x = m.x + math.floor(width / m.scale * ${xRatio} + 0.5),
            y = m.y + math.floor(height / m.scale * ${yRatio} + 0.5),
            window = w,
        }))
    end
end`, reply => {
            if (reply.trim() !== "ok") console.warn("Floating-window move failed:", reply);
        });
    }

    function monitorFor(screen) {
        const name = screen && screen.name ? screen.name : screen;
        return root.monitors.values.find(m => m.name === name) ?? null;
    }

    function hasFullscreenWindow(screen) {
        const mon = root.monitorFor(screen);
        if (!mon || !mon.activeWorkspace || !root.clients.values)
            return false;

        const wsId = mon.activeWorkspace.id;
        const monId = mon.id;
        for (let i = 0; i < root.clients.values.length; i++) {
            const c = root.clients.values[i];
            if (c.monitor === monId && c.fullscreen && c.workspace.id === wsId)
                return true;
        }
        return false;
    }

    function dispatch(command) {
        if (!command)
            return;

        const split = command.indexOf(" ");
        const action = (split === -1 ? command : command.slice(0, split)).trim();
        const rest = split === -1 ? "" : command.slice(split + 1).trim();

        const target = str => root.luaString(root.windowTarget(str.trim()));

        switch (action) {
        case "workspace":
            return Hyprland.dispatch(`hl.dsp.focus({ workspace = ${root.luaString(rest)} })`);
        case "focuswindow":
            return Hyprland.dispatch(`hl.dsp.focus({ window = ${target(rest)} })`);
        case "focusmonitor":
            return Hyprland.dispatch(`hl.dsp.focus({ monitor = ${root.luaString(rest)} })`);
        case "closewindow":
            return Hyprland.dispatch(rest ? `hl.dsp.window.close({ window = ${target(rest)} })` : "hl.dsp.window.close()");
        case "togglespecialworkspace":
            return Hyprland.dispatch(rest ? `hl.dsp.workspace.toggle_special(${root.luaString(rest)})` : "hl.dsp.workspace.toggle_special()");
        case "movetoworkspacesilent": {
            const parts = rest.split(",");
            const window = parts.length > 1 ? `, window = ${target(parts[1])}` : "";
            return Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${root.luaString(parts[0].trim())}, follow = false${window} })`);
        }
        case "dpms":
            if (rest === "on" || rest === "off")
                return Hyprland.dispatch(`hl.dsp.dpms({ action = "${rest}" })`);
            return;
        case "exit":
            return Hyprland.dispatch("hl.dsp.exit()");
        }

        console.warn("Compositor: no dispatcher mapping for", command);
    }

    function splitCombo(combo) {
        const tokens = String(combo || "").split("+")
            .map(token => token.replace(/[\\"\u0000-\u001f\u007f]/g, "").trim())
            .filter(token => token.length > 0);
        if (tokens.length === 0)
            return null;
        const key = tokens.pop();
        if (!/^[A-Za-z0-9_:]+$/.test(key))
            return null;
        if (["SUPER", "CTRL", "ALT", "SHIFT"].indexOf(key.toUpperCase()) !== -1)
            return null;
        const mods = tokens.filter(token => ["SUPER", "CTRL", "ALT", "SHIFT"].indexOf(token.toUpperCase()) !== -1);
        return { mods: mods.join(" "), key: key };
    }

    function injectShortcut(combo) {
        const parsed = splitCombo(combo);
        if (!parsed)
            return;
        Hyprland.dispatch(`hl.dsp.send_shortcut({ mods = "${parsed.mods}", key = "${parsed.key}" })`);
    }

    function moveCursor(x, y) {
        if (!Number.isFinite(x) || !Number.isFinite(y))
            return;
        Hyprland.dispatch(`hl.dsp.cursor.move({ x = ${Math.round(x)}, y = ${Math.round(y)} })`);
    }

    function injectKeyState(combo, state) {
        const parsed = splitCombo(combo);
        if (!parsed || !["down", "up", "repeat"].includes(state))
            return;
        Hyprland.dispatch(`hl.dsp.send_key_state({ mods = "${parsed.mods}", key = "${parsed.key}", state = "${state}" })`);
    }

    // A Socket collector never finishes; a process collector finishes on exit.
    function request(payload, onReply) {
        const proc = requestComponent.createObject(root, {
            payload: payload,
            handler: onReply ?? (() => {})
        });
        proc.running = true;
    }

    function reloadConfig() {
        root.request("reload");
    }

    Component {
        id: requestComponent

        Process {
            id: proc

            required property string payload
            required property var handler

            command: ["sh", "-c", 'printf %s "$1" | socat -T 3 - "UNIX-CONNECT:$2"', "sh", payload, Hyprland.requestSocketPath]
            stdout: StdioCollector {
                onStreamFinished: proc.handler(text)
            }
            onExited: code => {
                if (code !== 0) console.warn("Compositor request failed:", payload, code);
                proc.destroy();
            }
        }
    }

    function rebuild() {
        root.clients.values = Hyprland.toplevels.values.map(toplevel => {
            const raw = toplevel.lastIpcObject ?? {};
            return {
                nativeToplevel: toplevel,
                address: raw.address ?? toplevel.address,
                class: raw.class ?? "",
                title: raw.title ?? toplevel.title,
                workspace: raw.workspace ?? {
                    id: 0,
                    name: ""
                },
                monitor: raw.monitor ?? 0,
                floating: raw.floating ?? false,
                fullscreen: (raw.fullscreen ?? 0) !== 0,
                hidden: raw.hidden ?? false,
                mapped: raw.mapped ?? true,
                at: raw.at ?? [0, 0],
                size: raw.size ?? [100, 100],
                xwayland: raw.xwayland ?? false,
                pinned: raw.pinned ?? false,
                focusHistoryID: raw.focusHistoryID ?? Infinity,
                is_focused: toplevel === Hyprland.activeToplevel
            };
        });

        root.monitors.values = Hyprland.monitors.values.map(monitor => {
            const raw = monitor.lastIpcObject ?? {};
            const size = root.logicalSize({width: monitor.width, height: monitor.height,
                scale: monitor.scale, transform: raw.transform});
            return {
                id: monitor.id,
                name: monitor.name,
                focused: monitor === Hyprland.focusedMonitor,
                width: monitor.width,
                height: monitor.height,
                logicalWidth: size.width,
                logicalHeight: size.height,
                scale: monitor.scale,
                x: monitor.x,
                y: monitor.y,
                refreshRate: raw.refreshRate ?? 0,
                transform: raw.transform ?? 0,
                activeWorkspace: monitor.activeWorkspace ? {
                    id: monitor.activeWorkspace.id,
                    name: monitor.activeWorkspace.name
                } : null
            };
        });

        root.workspaces.values = Hyprland.workspaces.values.map(workspace => ({
            id: workspace.id,
            name: workspace.name,
            monitor: workspace.monitor ? workspace.monitor.name : "",
            active: workspace === Hyprland.focusedWorkspace
        }));
    }

    function scheduleRefresh() {
        if (!refresh.running) refresh.start();
    }

    function scheduleSnapshot() {
        if (!snapshot.running) snapshot.start();
    }

    Timer {
        id: refresh
        interval: 30
        onTriggered: {
            Hyprland.refreshToplevels();
            Hyprland.refreshWorkspaces();
            Hyprland.refreshMonitors();
            root.scheduleSnapshot();
        }
    }

    Timer {
        id: snapshot
        interval: 40
        onTriggered: root.rebuild()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (!root.handleRawEvent(event)) root.scheduleRefresh();
        }
        function onFocusedMonitorChanged() {
            root.scheduleSnapshot();
        }
        function onFocusedWorkspaceChanged() {
            root.scheduleSnapshot();
        }
        function onActiveToplevelChanged() {
            root.scheduleSnapshot();
        }
    }

    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() {
            root.scheduleSnapshot();
        }
    }

    Connections {
        target: Hyprland.monitors
        function onValuesChanged() {
            root.scheduleSnapshot();
        }
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            root.scheduleSnapshot();
        }
    }

    Variants {
        model: Hyprland.toplevels.values.concat(Hyprland.monitors.values, Hyprland.workspaces.values)
        Connections {
            required property var modelData
            target: modelData
            function onLastIpcObjectChanged() { root.scheduleSnapshot(); }
        }
    }

    Component.onCompleted: refresh.restart()
}
