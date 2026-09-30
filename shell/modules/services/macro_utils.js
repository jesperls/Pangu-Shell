.pragma library

var STEP_TYPES = ["key", "text", "command", "launch", "sound", "delay", "click"];
var TRIGGER_TYPES = ["none", "hotkey", "timer", "app", "sequence", "startup"];
var LOOP_MODES = ["none", "count", "infinite"];
var CLICK_BUTTONS = ["left", "right", "middle"];

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

function pick(list, value, fallback) {
    return list.indexOf(value) !== -1 ? value : fallback;
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
    case "timer":
        return {
            type: "timer",
            seconds: clampInt(trigger.seconds, 1, 86400, 60),
            repeat: trigger.repeat !== false
        };
    case "app":
        return {
            type: "app",
            match: String(trigger.match || ""),
            onFocus: trigger.onFocus === true
        };
    case "sequence":
        return {
            type: "sequence",
            keys: asArray(trigger.keys).map(sanitizeCombo),
            timeoutMs: clampInt(trigger.timeoutMs, 200, 10000, 1500)
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
    default:
        return step.type;
    }
}

function describeTrigger(trigger) {
    switch (trigger.type) {
    case "hotkey":
        return trigger.keys || "Hotkey";
    case "timer":
        return "Every " + trigger.seconds + "s" + (trigger.repeat ? "" : " once");
    case "app":
        return (trigger.onFocus ? "Focus " : "Launch ") + (trigger.match || "app");
    case "sequence":
        return "Sequence of " + trigger.keys.length;
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
