pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.components
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
    property var knownClients: ({})
    property string lastFocusedAddress: ""
    property var sequenceState: ({})
    property bool startupDone: false

    function _timerFired(id) {
        root.run(id, false);
    }

    function _syncTimers() {
        const wanted = {};
        for (const macro of root.list()) {
            if (!macro || !macro.enabled || macro.trigger?.type !== "timer")
                continue;
            const id = macro.id;
            const interval = Math.max(1, macro.trigger.seconds || 60) * 1000;
            const repeat = macro.trigger.repeat !== false;
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

    function _syncAppClients() {
        const clients = Compositor.clients.values || [];
        const seen = {};
        for (const client of clients)
            seen[client.address] = true;
        root.knownClients = seen;
    }

    function _appMatches(trigger, className) {
        if (!trigger.match)
            return false;
        return String(className || "").toLowerCase().indexOf(trigger.match.toLowerCase()) !== -1;
    }

    function _fireAppTriggers(className, focused) {
        for (const macro of root.list()) {
            if (!macro || !macro.enabled || macro.trigger?.type !== "app")
                continue;
            const trigger = macro.trigger;
            const isFocusedRule = trigger.onFocus === true;
            if (isFocusedRule !== focused)
                continue;
            if (root._appMatches(trigger, className))
                root.run(macro.id, false);
        }
    }

    function _checkLaunches() {
        const clients = Compositor.clients.values || [];
        for (const client of clients) {
            if (root.knownClients[client.address])
                continue;
            root._fireAppTriggers(client.class, false);
        }
        root._syncAppClients();
    }

    function _checkFocus() {
        const client = Compositor.focusedClient;
        if (!client || client.address === root.lastFocusedAddress)
            return;
        root.lastFocusedAddress = client.address;
        root._fireAppTriggers(client.class, true);
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
                root.run(id, true);
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
                root.run(macro.id, false);
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

    Connections {
        target: Config.macros
        function onMacrosChanged() {
            root._syncTimers();
            root._syncAppClients();
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
            root._checkLaunches();
        }
    }

    Connections {
        target: Config
        function onInitialLoadCompleteChanged() {
            if (Config.initialLoadComplete) {
                root._syncTimers();
                root._syncAppClients();
                root._runStartup();
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
            root._runStartup();
        }
        bindDebounce.restart();
    }
}
