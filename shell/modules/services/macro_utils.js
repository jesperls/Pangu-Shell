.pragma library

var STEP_TYPES = ["key", "text", "command", "launch", "sound", "delay", "click", "focus", "notify"];
var TRIGGER_TYPES = ["none", "hotkey", "sequence", "sound", "app", "notification", "clipboard", "system", "timer", "startup"];
var LOOP_MODES = ["none", "count", "infinite"];
var CLICK_BUTTONS = ["left", "right", "middle"];
var SOUND_MODES = ["sample", "frequency"];
var SOUND_SOURCES = ["desktop", "mic", "both"];
var APP_EVENTS = ["launch", "focus", "close", "title", "fullscreen"];
var NOTIF_URGENCIES = ["any", "normal", "critical"];
var SYSTEM_EVENTS = [
    "unlock",
    "lock",
    "resume",
    "suspend",
    "gamemode_on",
    "gamemode_off",
    "wifi_connected",
    "wifi_disconnected",
    "bt_connected",
    "bt_disconnected",
    "audio_output"
];
var TIMER_MODES = ["interval", "daily"];
var CONDITION_MODES = ["any", "focused", "running", "not_focused"];

function newId() {
    return "m_" + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
}

function asArray(value) {
    if (Array.isArray(value))
        return value;
    if (value && typeof value.length === "number" && typeof value.slice === "function") {
        var out = [];
        for (var i = 0; i < value.length; i++)
            out.push(value[i]);
        return out;
    }
    return [];
}

function clampInt(value, min, max, fallback) {
    var n = parseInt(value, 10);
    if (isNaN(n)) return fallback;
    return Math.max(min, Math.min(max, n));
}

function clampFloat(value, min, max, fallback) {
    var n = parseFloat(value);
    if (isNaN(n) || !isFinite(n)) return fallback;
    return Math.max(min, Math.min(max, n));
}

function pick(list, value, fallback) {
    return list.indexOf(value) !== -1 ? value : fallback;
}

function normalizeTimeOfDay(value, fallback) {
    var m = /^(\d{1,2}):(\d{2})$/.exec(String(value || "").trim());
    if (!m)
        return fallback || "09:00";
    var hh = parseInt(m[1], 10);
    var mm = parseInt(m[2], 10);
    if (hh < 0 || hh > 23 || mm < 0 || mm > 59)
        return fallback || "09:00";
    return ("0" + hh).slice(-2) + ":" + ("0" + mm).slice(-2);
}

function matchesQuery(text, query) {
    var q = String(query === undefined || query === null ? "" : query).trim();
    if (!q)
        return false;
    var hay = String(text === undefined || text === null ? "" : text);
    if (q.length >= 2 && q.charAt(0) === "/") {
        var lastSlash = q.lastIndexOf("/");
        if (lastSlash > 0) {
            var flags = q.slice(lastSlash + 1);
            if (/^[gimsuy]*$/.test(flags)) {
                try {
                    return new RegExp(q.slice(1, lastSlash), flags).test(hay);
                } catch (e) {
                    return false;
                }
            }
        }
    }
    return hay.toLowerCase().indexOf(q.toLowerCase()) !== -1;
}

function matchesOptionalQuery(text, query) {
    var q = String(query === undefined || query === null ? "" : query).trim();
    if (!q)
        return true;
    return matchesQuery(text, q);
}

function clientMatches(client, appMatch, titleMatch) {
    if (!client)
        return false;
    var hasApp = String(appMatch || "").trim().length > 0;
    var hasTitle = String(titleMatch || "").trim().length > 0;
    if (!hasApp && !hasTitle)
        return false;
    if (hasApp && !matchesQuery(client.class, appMatch) && !matchesQuery(client.initialClass, appMatch))
        return false;
    if (hasTitle && !matchesQuery(client.title, titleMatch))
        return false;
    return true;
}

function sanitizeCombo(value) {
    var parts = String(value === undefined || value === null ? "" : value).split("+");
    var out = [];
    for (var i = 0; i < parts.length; i++) {
        var token = parts[i].replace(/[\u0000-\u001f\u007f]/g, "").trim();
        if (token.length > 0)
            out.push(token);
    }
    return out.join(" + ");
}

function isModifierToken(token) {
    return ["SUPER", "CTRL", "ALT", "SHIFT"].indexOf(String(token).toUpperCase()) !== -1;
}

function isValidCombo(combo) {
    var tokens = sanitizeCombo(combo).split("+").map(function (token) {
        return token.trim();
    }).filter(function (token) {
        return token.length > 0;
    });
    if (tokens.length === 0)
        return false;
    var hasKey = false;
    for (var i = 0; i < tokens.length; i++) {
        if (!/^[A-Za-z0-9_:]+$/.test(tokens[i]))
            return false;
        if (!isModifierToken(tokens[i]))
            hasKey = true;
    }
    return hasKey;
}

function blankStep(type) {
    switch (type) {
    case "text":
        return { type: "text", text: "" };
    case "command":
        return { type: "command", command: "" };
    case "launch":
        return { type: "launch", command: "" };
    case "sound":
        return { type: "sound", path: "" };
    case "delay":
        return { type: "delay", ms: 500 };
    case "click":
        return { type: "click", button: "left" };
    case "focus":
        return { type: "focus", match: "" };
    case "notify":
        return { type: "notify", title: "", body: "" };
    case "key":
    default:
        return { type: "key", keys: "" };
    }
}

function normalizeStep(step) {
    var type = step && STEP_TYPES.indexOf(step.type) !== -1 ? step.type : "key";
    var out = blankStep(type);
    if (!step) return out;
    switch (type) {
    case "text":
        out.text = String(step.text !== undefined && step.text !== null ? step.text : "");
        break;
    case "command":
    case "launch":
        out.command = String(step.command !== undefined && step.command !== null ? step.command : "");
        break;
    case "sound":
        out.path = String(step.path !== undefined && step.path !== null ? step.path : "");
        break;
    case "delay":
        out.ms = clampInt(step.ms, 0, 3600000, 500);
        break;
    case "click":
        out.button = pick(CLICK_BUTTONS, step.button, "left");
        if (typeof step.x === "number" && typeof step.y === "number" && isFinite(step.x) && isFinite(step.y)) {
            out.x = Math.round(step.x);
            out.y = Math.round(step.y);
        }
        break;
    case "focus":
        out.match = String(step.match !== undefined && step.match !== null ? step.match : "");
        break;
    case "notify":
        out.title = String(step.title !== undefined && step.title !== null ? step.title : "");
        out.body = String(step.body !== undefined && step.body !== null ? step.body : "");
        break;
    case "key":
        out.keys = sanitizeCombo(step.keys);
        break;
    }
    return out;
}

function blankTrigger() {
    return { type: "none" };
}

function normalizeTrigger(trigger) {
    var type = trigger && TRIGGER_TYPES.indexOf(trigger.type) !== -1 ? trigger.type : "none";
    switch (type) {
    case "hotkey":
        return { type: "hotkey", keys: sanitizeCombo(trigger.keys) };
    case "sequence":
        return {
            type: "sequence",
            keys: asArray(trigger.keys).map(sanitizeCombo),
            timeoutMs: clampInt(trigger.timeoutMs, 200, 10000, 1500)
        };
    case "sound": {
        var t0 = Math.round(clampFloat(trigger.trimStart, 0, 60, 0) * 1000) / 1000;
        var t1 = Math.round(clampFloat(trigger.trimEnd, 0, 60, 0) * 1000) / 1000;
        if (t1 > 0 && t1 <= t0)
            t1 = 0;
        var minHz = clampInt(trigger.minHz, 60, 7600, 1200);
        var maxHz = clampInt(trigger.maxHz, minHz + 40, 7800, Math.max(minHz + 40, 3800));
        return {
            type: "sound",
            mode: pick(SOUND_MODES, trigger.mode, "sample"),
            source: pick(SOUND_SOURCES, trigger.source, "desktop"),
            samplePath: String(trigger.samplePath || ""),
            trimStart: t0,
            trimEnd: t1,
            bandFilter: trigger.bandFilter === true,
            minHz: minHz,
            maxHz: maxHz,
            minDurationMs: clampInt(trigger.minDurationMs, 20, 5000, 60),
            threshold: clampInt(trigger.threshold, 30, 98, 70),
            cooldownMs: clampInt(trigger.cooldownMs, 100, 300000, 1500)
        };
    }
    case "app": {
        var rawEvent = trigger.event ? trigger.event : (trigger.onFocus === true ? "focus" : "launch");
        var appEvent = pick(APP_EVENTS, rawEvent, "launch");
        return {
            type: "app",
            event: appEvent,
            match: String(trigger.match || ""),
            titleMatch: String(trigger.titleMatch || ""),
            onFocus: appEvent === "focus"
        };
    }
    case "notification":
        return {
            type: "notification",
            appMatch: String(trigger.appMatch || ""),
            textMatch: String(trigger.textMatch || ""),
            urgency: pick(NOTIF_URGENCIES, trigger.urgency, "any")
        };
    case "clipboard":
        return {
            type: "clipboard",
            match: String(trigger.match || "")
        };
    case "system":
        return {
            type: "system",
            event: pick(SYSTEM_EVENTS, trigger.event, "unlock"),
            match: String(trigger.match || "")
        };
    case "timer":
        return {
            type: "timer",
            mode: pick(TIMER_MODES, trigger.mode, "interval"),
            seconds: clampInt(trigger.seconds, 1, 86400, 60),
            repeat: trigger.repeat !== false,
            at: normalizeTimeOfDay(trigger.at, "09:00")
        };
    case "startup":
        return { type: "startup" };
    default:
        return { type: "none" };
    }
}

function blankTriggerFor(type) {
    return normalizeTrigger({ type: type });
}

function blankCondition() {
    return { appMode: "any", appMatch: "" };
}

function normalizeCondition(condition) {
    return {
        appMode: pick(CONDITION_MODES, condition && condition.appMode, "any"),
        appMatch: String(condition && condition.appMatch ? condition.appMatch : "")
    };
}

function conditionMet(condition, clients, focusedClient) {
    var cond = normalizeCondition(condition);
    var q = cond.appMatch.trim();
    if (cond.appMode === "any" || !q)
        return true;
    var matchesClient = function (c) {
        return Boolean(c && (matchesQuery(c.class, q) || matchesQuery(c.initialClass, q) || matchesQuery(c.title, q)));
    };
    if (cond.appMode === "focused")
        return matchesClient(focusedClient);
    if (cond.appMode === "not_focused")
        return !matchesClient(focusedClient);
    if (cond.appMode === "running") {
        var list = asArray(clients);
        for (var i = 0; i < list.length; i++) {
            if (matchesClient(list[i]))
                return true;
        }
        return false;
    }
    return true;
}

function blankLoop() {
    return { mode: "none", count: 3, delayMs: 0 };
}

function normalizeLoop(loop) {
    return {
        mode: pick(LOOP_MODES, loop && loop.mode, "none"),
        count: clampInt(loop && loop.count, 1, 9999, 3),
        delayMs: clampInt(loop && loop.delayMs, 0, 600000, 0)
    };
}

function blankMacro(name) {
    return {
        id: newId(),
        name: name || "New macro",
        enabled: true,
        trigger: blankTrigger(),
        condition: blankCondition(),
        cooldownMs: 0,
        loop: blankLoop(),
        steps: []
    };
}

function normalizeMacro(macro) {
    var out = {
        id: typeof macro?.id === "string" && macro.id ? macro.id : newId(),
        name: String(macro?.name || "Untitled macro"),
        enabled: macro?.enabled !== false,
        trigger: normalizeTrigger(macro?.trigger),
        condition: normalizeCondition(macro?.condition),
        cooldownMs: clampInt(macro?.cooldownMs, 0, 300000, 0),
        loop: normalizeLoop(macro?.loop),
        steps: []
    };
    var steps = asArray(macro?.steps);
    for (var i = 0; i < steps.length; i++)
        out.steps.push(normalizeStep(steps[i]));
    return out;
}

function normalizeMacros(list) {
    return asArray(list).map(normalizeMacro);
}

function stepTitle(step) {
    switch (step.type) {
    case "key":
        return step.keys || "Key press";
    case "text":
        return step.text ? (step.text.length > 40 ? step.text.slice(0, 40) + "…" : step.text) : "Type text";
    case "command":
        return step.command || "Run command";
    case "launch":
        return step.command || "Launch app";
    case "sound":
        return step.path ? step.path.split("/").pop() : "Play sound";
    case "delay":
        return step.ms + " ms wait";
    case "click":
        return step.button + " click" + (typeof step.x === "number" ? " @ " + step.x + "," + step.y : "");
    case "focus":
        return step.match ? "Focus " + step.match : "Focus window";
    case "notify":
        return step.title || step.body || "Notification";
    default:
        return step.type;
    }
}

function describeSystemEvent(event, match) {
    var labels = {
        unlock: "On unlock",
        lock: "On lock",
        resume: "On wake",
        suspend: "On sleep",
        gamemode_on: "Game mode on",
        gamemode_off: "Game mode off",
        wifi_connected: "Wi-Fi connect",
        wifi_disconnected: "Wi-Fi disconnect",
        bt_connected: "BT connect",
        bt_disconnected: "BT disconnect",
        audio_output: "Audio output"
    };
    var base = labels[event] || "System event";
    return match ? base + " (" + match + ")" : base;
}

function describeTrigger(trigger) {
    switch (trigger.type) {
    case "hotkey":
        return trigger.keys || "Hotkey";
    case "sequence":
        return "Sequence of " + trigger.keys.length;
    case "sound":
        if (trigger.mode === "frequency")
            return trigger.minHz + "–" + trigger.maxHz + " Hz";
        return trigger.samplePath ? "Sound: " + trigger.samplePath.split("/").pop() : "Sound match";
    case "app": {
        var ev = trigger.event || (trigger.onFocus ? "focus" : "launch");
        var target = trigger.match || trigger.titleMatch || "window";
        if (ev === "focus")
            return "Focus " + (trigger.match || "app");
        if (ev === "close")
            return "Close " + target;
        if (ev === "title")
            return "Title " + (trigger.titleMatch || target);
        if (ev === "fullscreen")
            return "Fullscreen " + target;
        return "Launch " + (trigger.match || "app");
    }
    case "notification":
        return "Notify: " + (trigger.textMatch || trigger.appMatch || "any");
    case "clipboard":
        return "Copy: " + (trigger.match || "pattern");
    case "system":
        return describeSystemEvent(trigger.event, trigger.match);
    case "timer":
        if (trigger.mode === "daily")
            return "Daily at " + (trigger.at || "09:00");
        return "Every " + trigger.seconds + "s" + (trigger.repeat ? "" : " once");
    case "startup":
        return "On shell start";
    default:
        return "Manual";
    }
}

function luaQuote(value) {
    var s = String(value);
    var out = "\"";
    for (var i = 0; i < s.length; i++) {
        var c = s.charAt(i);
        if (c === "\\") out += "\\\\";
        else if (c === "\"") out += "\\\"";
        else if (c === "\n") out += "\\n";
        else if (c === "\r") out += "\\r";
        else if (c === "\t") out += "\\t";
        else if (c < " " || c === "\u007f")
            out += "\\" + ("000" + c.charCodeAt(0)).slice(-3);
        else out += c;
    }
    return out + "\"";
}

function runCommand(macroId) {
    return "pangu run " + shellQuote("macros-run " + macroId);
}

function sequenceCommand(macroId, index) {
    return "pangu run " + shellQuote("macros-seq " + macroId + " " + index);
}

function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function bindLine(combo, command, description, nonConsuming) {
    return "macro_bind(" + luaQuote(combo) + ", " + luaQuote(command)
        + ", " + luaQuote(description) + ", " + (nonConsuming ? "true" : "false") + ")";
}

function bindsLua(macros) {
    var binds = [];
    var list = asArray(macros);
    for (var i = 0; i < list.length; i++) {
        var macro = list[i];
        if (!macro || macro.enabled === false) continue;
        var trigger = macro.trigger || { type: "none" };
        var label = macro.name || macro.id;
        var hotkey = sanitizeCombo(trigger.keys);
        if (trigger.type === "hotkey" && isValidCombo(hotkey)) {
            binds.push(bindLine(hotkey, runCommand(macro.id), "Macro: " + label, false));
        } else if (trigger.type === "sequence") {
            var keys = asArray(trigger.keys);
            for (var j = 0; j < keys.length; j++) {
                var key = sanitizeCombo(keys[j]);
                if (!isValidCombo(key)) continue;
                var desc = "Macro: " + label + " (sequence " + (j + 1) + "/" + keys.length + ")";
                binds.push(bindLine(key, sequenceCommand(macro.id, j), desc, true));
            }
        }
    }
    if (binds.length === 0)
        return "\n";
    return [
        "local function macro_bind(combo, command, description, non_consuming)",
        "  local ok, err = pcall(function()",
        "    hl.bind(combo, hl.dsp.exec_cmd(command), { description = description, non_consuming = non_consuming })",
        "  end)",
        "  if not ok then",
        "    io.stderr:write(\"pangu: macro bind failed: \" .. tostring(err) .. \"\\n\")",
        "  end",
        "end",
        ""
    ].concat(binds).join("\n") + "\n";
}
