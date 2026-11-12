pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.components
import qs.modules.globals
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services
import qs.modules.theme
import "macro_utils.js" as MacroUtils

Singleton {
    id: root

    readonly property var macros: Config.macros.macros
    readonly property bool enabled: Config.macros.enabled

    property bool playing: false
    property string activeId: ""
    property string activeName: ""
    property int activeStep: -1
    property int repeatLeft: 0
    property var currentMacro: null
    property int currentStepIndex: 0
    property bool loopPending: false
    property var queue: []
    readonly property int queuedCount: root.queue.length

    property int runToken: 0
    property int stepToken: -1
    property var processes: []

    property var lastFiredAt: ({})
    property var lastTriggerInfo: ({})

    property var soundScores: ({})
    property var soundLevels: ({})
    property var soundPeakHz: ({})
    property var previewDraft: null
    property string recordingMacroId: ""
    property string recordingTargetPath: ""
    property real recordingLevel: 0
    property real recordingSeconds: 0
    property bool previewPlaying: false
    property bool soundDaemonRetried: false

    signal soundSampleReady(string macroId, string samplePath, var meta)
    signal soundSampleInspected(string samplePath, var meta)

    function list() {
        return MacroUtils.asArray(root.macros);
    }

    function findMacro(id) {
        for (const macro of root.list()) {
            if (macro.id === id)
                return macro;
        }
        return null;
    }

    function saveList(list) {
        Config.macros.macros = list;
    }

    function addMacro() {
        const macro = MacroUtils.blankMacro("Macro " + (root.list().length + 1));
        const list = root.list();
        list.push(macro);
        root.saveList(list);
        return macro.id;
    }

    function replaceMacro(macro) {
        const clean = MacroUtils.normalizeMacro(macro);
        const list = root.list();
        const index = list.findIndex(item => item.id === clean.id);
        if (index === -1) list.push(clean);
        else list[index] = clean;
        root.saveList(list);
    }

    function removeMacro(id) {
        root.queue = root.queue.filter(queued => queued !== id);
        if (root.activeId === id) {
            root._resetPlayback();
            root._dequeue();
        }
        root.saveList(root.list().filter(macro => macro.id !== id));
    }

    function _guardsPass(macro, nowMs) {
        if (!macro || macro.enabled === false || !root.enabled)
            return false;
        const cd = Math.max(0, macro.cooldownMs || 0);
        if (cd > 0 && root.lastFiredAt[macro.id] && (nowMs - root.lastFiredAt[macro.id]) < cd)
            return false;
        const clients = Compositor.clients.values || [];
        return MacroUtils.conditionMet(macro.condition, clients, Compositor.focusedClient);
    }

    function _recordFire(id, nowMs, detail) {
        const dt = new Date(nowMs);
        const hh = ("0" + dt.getHours()).slice(-2);
        const mm = ("0" + dt.getMinutes()).slice(-2);
        const ss = ("0" + dt.getSeconds()).slice(-2);
        root.lastFiredAt = Object.assign({}, root.lastFiredAt, { [id]: nowMs });
        root.lastTriggerInfo = Object.assign({}, root.lastTriggerInfo, {
            [id]: { time: hh + ":" + mm + ":" + ss, detail: detail || "Triggered" }
        });
    }

    function _fireTrigger(id, urgent, detail) {
        const macro = root.findMacro(id);
        const nowMs = Date.now();
        if (!root._guardsPass(macro, nowMs))
            return false;
        root._recordFire(id, nowMs, detail);
        root.run(id, urgent);
        return true;
    }

    function triggerHotkey(id) {
        if (root.playing && root.activeId === id) {
            root.stop();
            return;
        }
        root._fireTrigger(id, true, "Hotkey");
    }

    function run(id, urgent) {
        if (urgent === undefined)
            urgent = true;
        const macro = root.findMacro(id);
        if (!macro || !root.enabled)
            return;
        if (root.playing && root.activeId === id) {
            if (urgent)
                root.stop();
            return;
        }
        if (root.playing) {
            if (urgent) {
                root._resetPlayback();
                root._startMacro(macro);
            } else {
                root._enqueue(id);
            }
            return;
        }
        root._startMacro(macro);
    }

    function stop() {
        root._resetPlayback();
        root.queue = [];
    }

    function _enqueue(id) {
        if (root.queue.indexOf(id) !== -1)
            return;
        root.queue = root.queue.concat([id]);
    }

    function _dequeue() {
        while (!root.playing && root.queue.length > 0) {
            const id = root.queue[0];
            root.queue = root.queue.slice(1);
            const macro = root.findMacro(id);
            if (macro)
                root._startMacro(macro);
        }
    }

    function _startMacro(macro) {
        const clean = MacroUtils.normalizeMacro(macro);
        if (!clean.enabled || clean.steps.length === 0)
            return;
        root._start(clean);
    }

    function _start(clean) {
        root.runToken++;
        root.currentMacro = clean;
        root.activeId = clean.id;
        root.activeName = clean.name;
        root.repeatLeft = clean.loop.mode === "count" ? clean.loop.count : -1;
        root.playing = true;
        root.currentStepIndex = 0;
        root.loopPending = false;
        root._runStep();
    }

    function _resetPlayback() {
        root.runToken++;
        stepTimer.stop();
        root._killProcesses();
        root.playing = false;
        root.currentMacro = null;
        root.activeId = "";
        root.activeName = "";
        root.activeStep = -1;
        root.repeatLeft = 0;
        root.loopPending = false;
    }

    function _reconcileActive() {
        if (!root.playing || !root.activeId || !root.currentMacro)
            return;
        const macro = root.findMacro(root.activeId);
        if (!macro || !macro.enabled) {
            root._resetPlayback();
            root._dequeue();
            return;
        }
        const clean = MacroUtils.normalizeMacro(macro);
        if (clean.steps.length === 0) {
            root._resetPlayback();
            root._dequeue();
            return;
        }
        const previous = root.currentMacro.loop;
        root.currentMacro.loop = clean.loop;
        if (previous.mode !== clean.loop.mode || previous.count !== clean.loop.count || previous.delayMs !== clean.loop.delayMs)
            root.repeatLeft = clean.loop.mode === "count" ? clean.loop.count : -1;
    }

    function _next() {
        if (!root.playing || !root.currentMacro)
            return;
        root.currentStepIndex++;
        root._runStep();
    }

    function _timerTick() {
        if (root.stepToken !== root.runToken)
            return;
        if (root.loopPending) {
            root.loopPending = false;
            root.currentStepIndex = 0;
            root._runStep();
            return;
        }
        root._next();
    }

    function _finishPass() {
        const macro = root.currentMacro;
        if (!macro) {
            root._dequeue();
            return;
        }
        const loop = macro.loop;
        let again = loop.mode === "infinite";
        if (loop.mode === "count") {
            root.repeatLeft--;
            again = root.repeatLeft > 0;
        }
        if (!again) {
            root._resetPlayback();
            root._dequeue();
            return;
        }
        root.activeStep = -1;
        if (loop.delayMs > 0) {
            root.loopPending = true;
            root.stepToken = root.runToken;
            stepTimer.interval = loop.delayMs;
            stepTimer.restart();
        } else {
            const token = root.runToken;
            Qt.callLater(() => {
                if (token === root.runToken)
                    root._runStep();
            });
        }
    }

    function _findMatchingClient(query) {
        if (!query || !String(query).trim())
            return null;
        const clients = Compositor.clients.values || [];
        for (const client of clients) {
            if (MacroUtils.matchesQuery(client.class, query) || MacroUtils.matchesQuery(client.title, query))
                return client;
        }
        return null;
    }

    function _runStep() {
        if (!root.playing || !root.currentMacro)
            return;
        const steps = root.currentMacro.steps;
        if (root.currentStepIndex >= steps.length) {
            root._finishPass();
            return;
        }
        root.activeStep = root.currentStepIndex;
        const step = steps[root.currentStepIndex];
        const token = root.runToken;
        switch (step.type) {
        case "delay":
            root.stepToken = token;
            stepTimer.interval = step.ms;
            stepTimer.restart();
            break;
        case "command":
            root._spawnProcess(token, ["bash", "-c", step.command], () => root._next());
            break;
        case "text":
            root._spawnProcess(token, ["wtype", "--", step.text], () => root._next());
            break;
        case "click": {
            const button = root._clickCode(step.button);
            if (typeof step.x === "number" && typeof step.y === "number") {
                // Hyprland positions the cursor; only the button press needs uinput.
                Compositor.moveCursor(step.x, step.y);
                root._spawnProcess(token, ["bash", "-c", "sleep 0.05; exec ydotool click " + button], code => {
                    if (code !== 0)
                        console.warn("MacroService: click step failed — is ydotoold running?");
                    root._next();
                });
            } else {
                root._spawnProcess(token, ["ydotool", "click", button], code => {
                    if (code !== 0)
                        console.warn("MacroService: click step failed — is ydotoold running?");
                    root._next();
                });
            }
            break;
        }
        case "key":
            Compositor.injectShortcut(step.keys);
            Qt.callLater(() => {
                if (token === root.runToken)
                    root._next();
            });
            break;
        case "launch":
            ApplicationLauncher.launchCommand(["bash", "-c", step.command]);
            Qt.callLater(() => {
                if (token === root.runToken)
                    root._next();
            });
            break;
        case "focus": {
            const client = root._findMatchingClient(step.match);
            if (client)
                Compositor.dispatch("focuswindow address:" + client.address);
            Qt.callLater(() => {
                if (token === root.runToken)
                    root._next();
            });
            break;
        }
        case "notify":
            Notifications.notifyInternal({
                appName: "Pangu Macros",
                summary: step.title || root.currentMacro.name || "Macro",
                body: step.body || ""
            });
            Qt.callLater(() => {
                if (token === root.runToken)
                    root._next();
            });
            break;
        case "sound":
            if (!step.path) {
                Qt.callLater(() => {
                    if (token === root.runToken)
                        root._next();
                });
                break;
            }
            root._spawnProcess(token, ["mpv", "--no-video", "--no-terminal", "--", step.path], code => {
                if (code !== 0)
                    console.warn("MacroService: sound step failed:", step.path);
                root._next();
            });
            break;
        default:
            Qt.callLater(() => {
                if (token === root.runToken)
                    root._next();
            });
        }
    }

    function _clickCode(button) {
        if (button === "right") return "0xC1";
        if (button === "middle") return "0xC2";
        return "0xC0";
    }

    function _spawnProcess(token, command, onDone) {
        const proc = processComponent.createObject(root, { token: token });
        proc.command = command;
        proc.done.connect(exitCode => {
            if (proc.released)
                return;
            proc.released = true;
            root._forgetProcess(proc);
            const stale = token !== root.runToken;
            proc.destroy();
            if (!stale)
                onDone(exitCode);
        });
        root.processes = root.processes.concat([proc]);
        proc.running = true;
    }

    function _forgetProcess(proc) {
        const index = root.processes.indexOf(proc);
        if (index !== -1)
            root.processes = root.processes.slice(0, index).concat(root.processes.slice(index + 1));
    }

    function _killProcesses() {
        const live = root.processes.slice();
        root.processes = [];
        for (const proc of live) {
            if (proc.released)
                continue;
            proc.running = false;
            if (!proc.released) {
                proc.released = true;
                proc.destroy();
            }
        }
    }

    property var timerObjects: ({})
    property var dailyFiredStamp: ({})
    property var clientSnapshots: ({})
    property bool clientsInitialized: false
    property string lastFocusedAddress: ""
    property var sequenceState: ({})
    property bool startupDone: false
    property int maxClipboardId: -1
    property bool clipboardInitialized: false
    property string lastWifiStatus: ""
    property string lastWifiSsid: ""
    property var connectedBtMap: ({})
    property bool btInitialized: false
    property string lastSinkName: ""
    property bool gameModeSettled: false
    property bool lastGameMode: false

    function _timerFired(id) {
        root._fireTrigger(id, false, "Timer");
    }

    function _syncTimers() {
        const wanted = {};
        for (const macro of root.list()) {
            if (!macro || !macro.enabled || macro.trigger?.type !== "timer")
                continue;
            const trig = MacroUtils.normalizeTrigger(macro.trigger);
            if (trig.mode !== "interval")
                continue;
            const id = macro.id;
            const interval = Math.max(1, trig.seconds || 60) * 1000;
            const repeat = trig.repeat !== false;
            wanted[id] = true;
            let timer = root.timerObjects[id];
            if (!timer) {
                timer = timerComponent.createObject(root, { macroId: id, repeatMode: repeat });
                root.timerObjects[id] = timer;
            }
            if (timer.interval !== interval) {
                timer.interval = interval;
                timer.firedOnce = false;
            }
            timer.repeat = repeat;
            if (repeat || !timer.firedOnce)
                timer.running = true;
        }
        for (const id in root.timerObjects) {
            if (!wanted[id]) {
                root.timerObjects[id].destroy();
                delete root.timerObjects[id];
            }
        }
    }

    function _checkDailyTimers(nowDate) {
        const dt = nowDate || new Date();
        const hhmm = ("0" + dt.getHours()).slice(-2) + ":" + ("0" + dt.getMinutes()).slice(-2);
        const dayKey = dt.getFullYear() + "-" + (dt.getMonth() + 1) + "-" + dt.getDate() + " " + hhmm;
        for (const macro of root.list()) {
            if (!macro || !macro.enabled || macro.trigger?.type !== "timer")
                continue;
            const trig = MacroUtils.normalizeTrigger(macro.trigger);
            if (trig.mode !== "daily" || trig.at !== hhmm)
                continue;
            if (root.dailyFiredStamp[macro.id] === dayKey)
                continue;
            root.dailyFiredStamp = Object.assign({}, root.dailyFiredStamp, { [macro.id]: dayKey });
            root._fireTrigger(macro.id, false, "Daily " + hhmm);
        }
    }

    function _snapshotClient(client) {
        return {
            address: client.address,
            class: client.class || "",
            initialClass: client.initialClass || "",
            title: client.title || "",
            fullscreen: Boolean(client.fullscreen)
        };
    }

    function _syncAppClients() {
        const clients = Compositor.clients.values || [];
        const seen = {};
        for (const client of clients)
            seen[client.address] = root._snapshotClient(client);
        root.clientSnapshots = seen;
        root.clientsInitialized = true;
    }

    function _fireAppEvent(eventName, client, prevClient) {
        for (const macro of root.list()) {
            if (!macro || !macro.enabled || macro.trigger?.type !== "app")
                continue;
            const trig = MacroUtils.normalizeTrigger(macro.trigger);
            if (trig.event !== eventName)
                continue;
            if (!MacroUtils.clientMatches(client, trig.match, trig.titleMatch))
                continue;
            if (eventName === "title" && prevClient && MacroUtils.clientMatches(prevClient, trig.match, trig.titleMatch))
                continue;
            root._fireTrigger(macro.id, false, "Window " + eventName);
        }
    }

    function _checkClientEvents() {
        if (!Config.initialLoadComplete)
            return;
        if (!root.clientsInitialized) {
            root._syncAppClients();
            return;
        }
        const clients = Compositor.clients.values || [];
        const next = {};
        for (const client of clients) {
            const prev = root.clientSnapshots[client.address];
            const snap = root._snapshotClient(client);
            next[client.address] = snap;
            if (!prev) {
                root._fireAppEvent("launch", snap, null);
            } else {
                if (snap.title !== prev.title)
                    root._fireAppEvent("title", snap, prev);
                if (snap.fullscreen && !prev.fullscreen)
                    root._fireAppEvent("fullscreen", snap, prev);
            }
        }
        for (const addr in root.clientSnapshots) {
            if (!next[addr])
                root._fireAppEvent("close", root.clientSnapshots[addr], null);
        }
        root.clientSnapshots = next;
    }

    function _checkFocus() {
        const client = Compositor.focusedClient;
        if (!client) {
            root.lastFocusedAddress = "";
            return;
        }
        if (client.address === root.lastFocusedAddress)
            return;
        root.lastFocusedAddress = client.address;
        if (!Config.initialLoadComplete)
            return;
        root._fireAppEvent("focus", root._snapshotClient(client), null);
    }

    function _handleNotification(notif) {
        if (!Config.initialLoadComplete || !notif)
            return;
        // Ignore notifications emitted by macro steps to prevent self-triggering loops.
        if (String(notif.appName || "") === "Pangu Macros")
            return;
        const urgencyNum = typeof notif.urgency === "number" ? notif.urgency : 1;
        const text = String(notif.summary || "") + "\n" + String(notif.body || "");
        for (const macro of root.list()) {
            if (!macro || !macro.enabled || macro.trigger?.type !== "notification")
                continue;
            const trig = MacroUtils.normalizeTrigger(macro.trigger);
            if (!trig.appMatch.trim() && !trig.textMatch.trim() && trig.urgency === "any")
                continue;
            if (trig.urgency === "critical" && urgencyNum < 2)
                continue;
            if (trig.urgency === "normal" && urgencyNum < 1)
                continue;
            if (!MacroUtils.matchesOptionalQuery(notif.appName || "", trig.appMatch))
                continue;
            if (!MacroUtils.matchesOptionalQuery(text, trig.textMatch))
                continue;
            root._fireTrigger(macro.id, false, "Notification: " + (notif.appName || "alert"));
        }
    }

    function _handleClipboardUpdate() {
        const items = ClipboardService.items || [];
        let highest = root.maxClipboardId;
        for (const item of items) {
            const num = parseInt(item.id, 10);
            if (!isNaN(num) && num > highest)
                highest = num;
        }
        if (!root.clipboardInitialized) {
            root.maxClipboardId = highest;
            root.clipboardInitialized = true;
            return;
        }
        if (highest <= root.maxClipboardId)
            return;
        const prevMax = root.maxClipboardId;
        root.maxClipboardId = highest;
        if (!Config.initialLoadComplete)
            return;
        for (const item of items) {
            const num = parseInt(item.id, 10);
            if (isNaN(num) || num <= prevMax || item.isImage)
                continue;
            const content = String(item.fullContent || item.preview || "");
            for (const macro of root.list()) {
                if (!macro || !macro.enabled || macro.trigger?.type !== "clipboard")
                    continue;
                const trig = MacroUtils.normalizeTrigger(macro.trigger);
                if (MacroUtils.matchesQuery(content, trig.match))
                    root._fireTrigger(macro.id, false, "Clipboard copy");
            }
        }
    }

    function _fireSystemEvent(eventName, contextValue) {
        if (!Config.initialLoadComplete)
            return;
        for (const macro of root.list()) {
            if (!macro || !macro.enabled || macro.trigger?.type !== "system")
                continue;
            const trig = MacroUtils.normalizeTrigger(macro.trigger);
            if (trig.event !== eventName)
                continue;
            if (!MacroUtils.matchesOptionalQuery(contextValue || "", trig.match))
                continue;
            root._fireTrigger(macro.id, false, MacroUtils.describeSystemEvent(eventName, contextValue || ""));
        }
    }

    function _resetSequences() {
        if (Object.keys(root.sequenceState).length === 0)
            return;
        root.sequenceState = ({});
    }

    function sequenceStep(id, index) {
        const macro = root.findMacro(id);
        if (!macro || !macro.enabled || macro.trigger?.type !== "sequence")
            return;
        const total = macro.trigger.keys.length;
        if (total === 0)
            return;
        const expected = root.sequenceState[id] || 0;
        if (index === expected) {
            if (expected + 1 >= total) {
                root._resetSequences();
                root._fireTrigger(id, true, "Key sequence");
                return;
            }
            root.sequenceState = Object.assign({}, root.sequenceState, { [id]: expected + 1 });
            sequenceTimer.interval = Math.max(200, macro.trigger.timeoutMs || 1500);
            sequenceTimer.restart();
        } else if (index === 0) {
            root.sequenceState = Object.assign({}, root.sequenceState, { [id]: 1 });
            sequenceTimer.interval = Math.max(200, macro.trigger.timeoutMs || 1500);
            sequenceTimer.restart();
        } else {
            root._resetSequences();
        }
    }

    function _runStartup() {
        if (root.startupDone)
            return;
        root.startupDone = true;
        for (const macro of root.list()) {
            if (macro && macro.enabled && macro.trigger?.type === "startup")
                root._fireTrigger(macro.id, false, "Shell startup");
        }
    }

    function samplePathFor(macroId) {
        const safeId = String(macroId || "sample").replace(/[^A-Za-z0-9_-]/g, "_");
        return Paths.dataPath("macro-sounds/" + safeId + ".wav");
    }

    function _soundRuleFromMacro(macro, telemetryOnly) {
        const trig = MacroUtils.normalizeTrigger(macro.trigger);
        if (trig.type !== "sound")
            return null;
        if (trig.mode === "sample" && !trig.samplePath)
            return null;
        return {
            id: macro.id,
            mode: trig.mode,
            source: trig.source,
            samplePath: trig.samplePath,
            trimStart: trig.trimStart,
            trimEnd: trig.trimEnd,
            bandFilter: trig.bandFilter,
            minHz: trig.minHz,
            maxHz: trig.maxHz,
            minDurationMs: trig.minDurationMs,
            threshold: trig.threshold,
            cooldownMs: trig.cooldownMs,
            telemetryOnly: Boolean(telemetryOnly)
        };
    }

    function _buildSoundConfig(macrosList, masterEnabled, draftMacro, telemetryActive) {
        const rules = [];
        const draftId = telemetryActive && draftMacro && draftMacro.id ? draftMacro.id : "";
        let draftIncluded = false;
        for (const raw of MacroUtils.asArray(macrosList)) {
            if (!raw)
                continue;
            if (draftId && raw.id === draftId) {
                draftIncluded = true;
                const cleanDraft = MacroUtils.normalizeMacro(draftMacro);
                const draftRule = root._soundRuleFromMacro(cleanDraft, !(masterEnabled && cleanDraft.enabled));
                if (draftRule)
                    rules.push(draftRule);
                continue;
            }
            if (!masterEnabled || raw.enabled === false)
                continue;
            const rule = root._soundRuleFromMacro(raw, false);
            if (rule)
                rules.push(rule);
        }
        if (draftId && !draftIncluded) {
            const extraDraft = MacroUtils.normalizeMacro(draftMacro);
            const extraRule = root._soundRuleFromMacro(extraDraft, !(masterEnabled && extraDraft.enabled));
            if (extraRule)
                rules.push(extraRule);
        }
        return {
            rules: rules,
            json: JSON.stringify({ telemetry: Boolean(telemetryActive), rules: rules })
        };
    }

    readonly property var _soundState: root._buildSoundConfig(
        root.macros,
        root.enabled,
        root.previewDraft,
        GlobalStates.macrosWindowVisible
    )
    readonly property string _soundConfigJson: root._soundState.json
    readonly property bool soundShouldRun: Config.initialLoadComplete
        && root._soundState.rules.length > 0
        && !SuspendManager.isSuspending
        && root.recordingMacroId === ""

    function _ensureSoundMonitor() {
        if (!root.soundShouldRun) {
            soundRetryTimer.stop();
            if (soundMonitorProc.running)
                soundMonitorProc.running = false;
            return;
        }
        if (!soundMonitorProc.running)
            soundMonitorProc.running = true;
    }

    on_SoundConfigJsonChanged: soundConfigDebounce.restart()

    onSoundShouldRunChanged: {
        if (root.soundShouldRun) {
            root.soundDaemonRetried = false;
            soundConfigDebounce.restart();
        } else {
            soundRetryTimer.stop();
            soundMonitorProc.running = false;
            root.soundScores = ({});
            root.soundLevels = ({});
            root.soundPeakHz = ({});
        }
    }

    function startSoundRecord(macroId, source) {
        if (!macroId || soundRecordProc.running)
            return;
        root.stopSoundPreview();
        const outPath = root.samplePathFor(macroId);
        const recSource = source === "mic" ? "mic" : "desktop";
        root.recordingMacroId = macroId;
        root.recordingTargetPath = outPath;
        root.recordingLevel = 0;
        root.recordingSeconds = 0;
        soundRecordProc.command = [
            "python3",
            Paths.script("sound_trigger.py"),
            "record",
            outPath,
            "--source",
            recSource,
            "--max-seconds",
            "10"
        ];
        soundRecordProc.running = true;
    }

    function stopSoundRecord() {
        if (soundRecordProc.running && soundRecordProc.processId > 0) {
            soundStopSignalProc.command = ["kill", "-INT", String(soundRecordProc.processId)];
            soundStopSignalProc.running = true;
        } else {
            soundRecordProc.running = false;
            root.recordingMacroId = "";
            root.recordingLevel = 0;
        }
    }

    function importSoundSample(macroId, inputPath) {
        if (!macroId || !inputPath)
            return;
        const outPath = root.samplePathFor(macroId);
        const proc = inspectProcessComponent.createObject(root, {
            macroId: macroId,
            samplePath: outPath,
            isImport: true,
            command: ["python3", Paths.script("sound_trigger.py"), "import", inputPath, outPath]
        });
        proc.running = true;
    }

    function inspectSoundSample(samplePath, trimStart, trimEnd, autotrim) {
        if (!samplePath)
            return;
        const cmd = ["python3", Paths.script("sound_trigger.py"), "inspect", samplePath];
        if (autotrim) {
            cmd.push("--autotrim");
        } else if (typeof trimStart === "number" && typeof trimEnd === "number" && trimEnd > trimStart) {
            cmd.push("--trim-start", String(trimStart), "--trim-end", String(trimEnd));
        }
        const proc = inspectProcessComponent.createObject(root, {
            macroId: "",
            samplePath: samplePath,
            isImport: false,
            command: cmd
        });
        proc.running = true;
    }

    function previewSoundSnippet(samplePath, trimStart, trimEnd) {
        if (!samplePath)
            return;
        if (soundPreviewProc.running)
            soundPreviewProc.running = false;
        const args = ["mpv", "--no-video", "--no-terminal"];
        if (typeof trimStart === "number" && trimStart > 0)
            args.push("--start=" + trimStart.toFixed(3));
        if (typeof trimEnd === "number" && trimEnd > (trimStart || 0))
            args.push("--end=" + trimEnd.toFixed(3));
        args.push("--", samplePath);
        soundPreviewProc.command = args;
        root.previewPlaying = true;
        soundPreviewProc.running = true;
    }

    function stopSoundPreview() {
        if (soundPreviewProc.running)
            soundPreviewProc.running = false;
        root.previewPlaying = false;
    }

    GeneratedFile {
        id: soundConfigFile
        path: Paths.runtimePath("macro-sound-triggers.json")
        onWritten: root._ensureSoundMonitor()
    }

    Timer {
        id: soundConfigDebounce
        interval: 120
        onTriggered: soundConfigFile.write(root._soundConfigJson)
    }

    Process {
        id: soundMonitorProc
        command: ["python3", Paths.script("sound_trigger.py"), "monitor", "--config", soundConfigFile.path]

        stdout: SplitParser {
            onRead: line => {
                const text = line.trim();
                if (text.startsWith("MATCH ")) {
                    const parts = text.split(/\s+/);
                    if (parts.length >= 3)
                        root._fireTrigger(parts[1], false, "Sound match (" + parts[2] + "%)");
                } else if (text.startsWith("TELEMETRY ")) {
                    try {
                        const data = JSON.parse(text.slice(10));
                        root.soundScores = data.scores || ({});
                        root.soundLevels = data.levels || ({});
                        root.soundPeakHz = data.peakHz || ({});
                    } catch (e) {}
                }
            }
        }

        onExited: {
            if (!root.soundShouldRun)
                return;
            if (!root.soundDaemonRetried) {
                root.soundDaemonRetried = true;
                soundRetryTimer.restart();
            }
        }
    }

    Timer {
        id: soundRetryTimer
        interval: 1500
        onTriggered: root._ensureSoundMonitor()
    }

    Timer {
        id: soundHealthyTimer
        interval: 10000
        running: soundMonitorProc.running
        onTriggered: root.soundDaemonRetried = false
    }

    Process {
        id: soundRecordProc
        stdout: SplitParser {
            onRead: line => {
                const text = line.trim();
                if (text.startsWith("RMS ")) {
                    const parts = text.split(/\s+/);
                    root.recordingLevel = parseFloat(parts[1]) || 0;
                    root.recordingSeconds = parseFloat(parts[2]) || 0;
                } else if (text.startsWith("SAVED ")) {
                    try {
                        const meta = JSON.parse(text.slice(6));
                        root.soundSampleReady(root.recordingMacroId, root.recordingTargetPath, meta);
                    } catch (e) {}
                }
            }
        }
        onExited: {
            root.recordingMacroId = "";
            root.recordingLevel = 0;
            root.recordingSeconds = 0;
        }
    }

    Process {
        id: soundStopSignalProc
    }

    Process {
        id: soundPreviewProc
        onExited: root.previewPlaying = false
    }

    Component {
        id: inspectProcessComponent
        Process {
            id: inspectProc
            property string macroId: ""
            property string samplePath: ""
            property bool isImport: false
            property string outputBuffer: ""
            stdout: StdioCollector {
                onStreamFinished: inspectProc.outputBuffer = text.trim()
            }
            onExited: code => {
                if (code === 0 && inspectProc.outputBuffer.length > 0) {
                    try {
                        const meta = JSON.parse(inspectProc.outputBuffer);
                        if (inspectProc.isImport)
                            root.soundSampleReady(inspectProc.macroId, inspectProc.samplePath, meta);
                        else
                            root.soundSampleInspected(inspectProc.samplePath, meta);
                    } catch (e) {}
                }
                inspectProc.destroy();
            }
        }
    }

    Component {
        id: timerComponent
        Timer {
            property string macroId
            property bool repeatMode
            property bool firedOnce: false
            onTriggered: {
                if (!repeatMode)
                    firedOnce = true;
                root._timerFired(macroId);
            }
        }
    }

    Component {
        id: processComponent
        Process {
            property int token: -1
            property bool released: false
            signal done(int exitCode)
            onExited: code => done(code)
        }
    }

    Timer {
        id: stepTimer
        onTriggered: root._timerTick()
    }

    Timer {
        id: sequenceTimer
        onTriggered: root._resetSequences()
    }

    Timer {
        id: dailyScheduleTimer
        interval: 15000
        repeat: true
        running: Config.initialLoadComplete && root.enabled && !SuspendManager.isSuspending
        onTriggered: root._checkDailyTimers(new Date())
    }

    Connections {
        target: Config.macros
        function onMacrosChanged() {
            root._syncTimers();
            root._resetSequences();
            root._reconcileActive();
        }
        function onEnabledChanged() {
            if (!Config.macros.enabled)
                root.stop();
        }
    }

    Connections {
        target: Compositor
        function onFocusedClientChanged() {
            root._checkFocus();
        }
    }

    Connections {
        target: Compositor.clients
        function onValuesChanged() {
            root._checkClientEvents();
        }
    }

    Connections {
        target: Notifications
        function onNotify(notif) {
            root._handleNotification(notif);
        }
    }

    Connections {
        target: ClipboardService
        function onListCompleted() {
            root._handleClipboardUpdate();
        }
    }

    Connections {
        target: GlobalStates
        function onLockscreenVisibleChanged() {
            if (GlobalStates.lockscreenVisible)
                root._fireSystemEvent("lock", "");
        }
    }

    Connections {
        target: LockscreenService
        function onUnlocked() {
            root._fireSystemEvent("unlock", "");
        }
    }

    Connections {
        target: SuspendManager
        function onPreparingForSleep() {
            root._fireSystemEvent("suspend", "");
        }
        function onWakingUp() {
            root._fireSystemEvent("resume", "");
        }
    }

    Connections {
        target: GameModeService
        function onToggledChanged() {
            if (!root.gameModeSettled)
                return;
            const next = Boolean(GameModeService.toggled);
            if (next === root.lastGameMode)
                return;
            root.lastGameMode = next;
            root._fireSystemEvent(next ? "gamemode_on" : "gamemode_off", "");
        }
    }

    Connections {
        target: NetworkService
        function onWifiStatusChanged() {
            const st = NetworkService.wifiStatus || "";
            const ssid = NetworkService.active?.ssid || "";
            if (!root.lastWifiStatus) {
                root.lastWifiStatus = st;
                root.lastWifiSsid = ssid;
                return;
            }
            if (st === "connected" && root.lastWifiStatus !== "connected") {
                root.lastWifiSsid = ssid;
                root._fireSystemEvent("wifi_connected", ssid);
            } else if ((st === "disconnected" || st === "disabled") && root.lastWifiStatus === "connected") {
                root._fireSystemEvent("wifi_disconnected", root.lastWifiSsid);
                root.lastWifiSsid = "";
            }
            root.lastWifiStatus = st;
        }
    }

    Connections {
        target: BluetoothService
        function onFriendlyDeviceListChanged() {
            const devices = BluetoothService.friendlyDeviceList || [];
            const next = {};
            for (const dev of devices) {
                if (dev && dev.connected)
                    next[dev.address || dev.name] = dev.name || dev.address || "";
            }
            if (!root.btInitialized) {
                root.connectedBtMap = next;
                root.btInitialized = true;
                return;
            }
            for (const key in next) {
                if (!(key in root.connectedBtMap))
                    root._fireSystemEvent("bt_connected", next[key]);
            }
            for (const key in root.connectedBtMap) {
                if (!(key in next))
                    root._fireSystemEvent("bt_disconnected", root.connectedBtMap[key]);
            }
            root.connectedBtMap = next;
        }
    }

    Connections {
        target: Audio
        function onSinkChanged() {
            if (soundMonitorProc.running) {
                root.soundDaemonRetried = false;
                soundMonitorProc.running = false;
            }
            if (!Audio._sinkSettled || !Audio.sink)
                return;
            const label = Audio.friendlyDeviceName(Audio.sink);
            if (root.lastSinkName && label !== root.lastSinkName)
                root._fireSystemEvent("audio_output", label);
            root.lastSinkName = label;
        }
    }

    Connections {
        target: Config
        function onInitialLoadCompleteChanged() {
            if (Config.initialLoadComplete) {
                root._syncTimers();
                root._syncAppClients();
                root.lastWifiStatus = NetworkService.wifiStatus || "";
                root.lastWifiSsid = NetworkService.active?.ssid || "";
                root.lastGameMode = Boolean(GameModeService.toggled);
                root.gameModeSettled = true;
                if (Audio.sink)
                    root.lastSinkName = Audio.friendlyDeviceName(Audio.sink);
                root._runStartup();
                soundConfigDebounce.restart();
            }
        }
    }

    readonly property string bindsText: MacroUtils.bindsLua(Config.macros.enabled ? root.macros : [])

    GeneratedFile {
        id: bindsFile
        path: Paths.dataPath("macros.lua")
        onWritten: Compositor.reloadConfig()
    }

    Timer {
        id: bindDebounce
        interval: 300
        onTriggered: bindsFile.write(root.bindsText)
    }

    onBindsTextChanged: bindDebounce.restart()

    Component.onCompleted: {
        if (Config.initialLoadComplete) {
            root._syncTimers();
            root._syncAppClients();
            root.lastWifiStatus = NetworkService.wifiStatus || "";
            root.lastWifiSsid = NetworkService.active?.ssid || "";
            root.lastGameMode = Boolean(GameModeService.toggled);
            root.gameModeSettled = true;
            if (Audio.sink)
                root.lastSinkName = Audio.friendlyDeviceName(Audio.sink);
            root._runStartup();
            soundConfigDebounce.restart();
        }
        bindDebounce.restart();
    }
}
