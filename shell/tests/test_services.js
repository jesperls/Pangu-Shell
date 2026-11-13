const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function serviceFunctions(filename, names, context) {
    const source = fs.readFileSync(path.join(__dirname, '../modules/services', filename), 'utf8');
    vm.createContext(context);
    for (const name of names) {
        const start = source.indexOf(`    function ${name}(`);
        assert.notEqual(start, -1, `Missing ${name}`);
        let end = source.indexOf('{', start) + 1;
        let depth = 1;
        while (depth && end < source.length) {
            if (source[end] === '{') depth++;
            if (source[end] === '}') depth--;
            end++;
        }
        vm.runInContext(source.slice(start, end), context);
        context.root[name] = context[name];
    }
}

let emojiSaves = 0;
const emojiContext = {
    root: {}, pending: [], Date: {now: () => 100},
    history: {ready: false, data: [], save() { emojiSaves++; }}
};
serviceFunctions('EmojiService.qml', ['normalizeCatalog', 'normalizeRecent', 'addRecent', 'remember', 'clearRecent', 'finishLoad'], emojiContext);
const smile = {emoji: '😀', name: 'grinning face', slug: 'grinning_face'};
assert.equal(emojiContext.normalizeCatalog({'😀': smile, broken: null}).length, 1);
assert.equal(emojiContext.normalizeRecent({invalid: true}).length, 0);
assert.equal(emojiContext.normalizeRecent([null, {}, smile, smile]).length, 1);
emojiContext.remember(smile);
emojiContext.remember(smile);
assert.equal(emojiContext.pending.length, 2);
assert.equal(emojiSaves, 0);
emojiContext.history.data = emojiContext.normalizeRecent([{...smile, usage: 5}]);
emojiContext.history.ready = true;
emojiContext.finishLoad();
assert.equal(emojiContext.history.data[0].usage, 7);
assert.equal(smile.usage, undefined);
assert.equal(emojiSaves, 1);
emojiContext.remember({emoji: '👍🏽', name: 'thumbs up (medium)', usage: 90});
assert.equal(emojiContext.history.data[1].usage, 1);
emojiContext.history.ready = false;
emojiContext.remember(smile);
emojiContext.clearRecent();
emojiContext.remember({emoji: '👍🏽', name: 'thumbs up (medium)'});
emojiContext.history.ready = true;
emojiContext.finishLoad();
assert.equal(emojiContext.history.data.length, 1);
assert.equal(emojiContext.history.data[0].emoji, '👍🏽');
assert.equal(emojiContext.history.data[0].usage, 1);
const manyEmojis = Array.from({length: 60}, (_, i) => ({emoji: String(i), usage: i + 1}));
const limited = emojiContext.normalizeRecent(manyEmojis);
assert.equal(limited.length, 50);
assert.equal(limited[0].usage, 60);
console.log('Shared emoji history counts repeated copies and replays startup changes in order');

const emojiSearchContext = {
    root: {}, searchText: 'no match', expandedItemIndex: 0, selectedOptionIndex: 3,
    keyboardNavigation: true, selectedIndex: 0, filteredEmojis: [],
    emojiData: emojiContext.normalizeCatalog({'😀': smile}),
    emojisModel: {clear() {}, append() {}}, emojiList: {contentY: 0}
};
serviceFunctions('../widgets/dashboard/emoji/EmojiTab.qml', ['performSearch', 'updateFilteredEmojis'], emojiSearchContext);
emojiSearchContext.performSearch();
assert.equal(emojiSearchContext.selectedIndex, -1);
assert.equal(emojiSearchContext.expandedItemIndex, -1);
assert.equal(emojiSearchContext.selectedOptionIndex, 0);
assert.equal(emojiSearchContext.keyboardNavigation, false);
emojiSearchContext.searchText = 'grinning';
emojiSearchContext.performSearch();
assert.equal(emojiSearchContext.selectedIndex, 0);
assert.equal(emojiSearchContext.filteredEmojis.length, 1);

const tmuxContext = {root: {}};
serviceFunctions('TmuxSessionInfo.qml', ['parseWindows', 'parsePanes'], tmuxContext);
const tmuxWindows = tmuxContext.parseWindows('0:1:editor:project\n1:0:server\ninvalid\n');
assert.equal(tmuxWindows[0].name, 'editor:project');
assert.equal(tmuxWindows[0].active, true);
assert.equal(tmuxWindows.length, 2);
const tmuxPanes = tmuxContext.parsePanes('0:80:20:0:0:1:editor:project\n1:80:10:20:0:0:shell\n2:bad:10:0:0:0:bad\n');
assert.equal(tmuxPanes.length, 2);
assert.equal(tmuxPanes[0].command, 'editor:project');
assert.equal(tmuxPanes[0].totalWidth, 80);
assert.equal(tmuxPanes[0].totalHeight, 30);
const paneFocusContext = {root: {}, focusPaneProcess: {running: false}};
serviceFunctions('../widgets/dashboard/tmux/TmuxTab.qml', ['focusPane'], paneFocusContext);
paneFocusContext.focusPane('selected-session', 2);
assert.deepEqual(Array.from(paneFocusContext.focusPaneProcess.command), ['tmux', 'select-pane', '-t', 'selected-session:.2']);
console.log('Tmux details preserve colon names and pane selection targets the selected session');

const notices = [1, 2].map(id => ({id, popup: true, timer: {destroy() {}}, closeTimer: {
    running: false, start() { this.running = true; }
}}));
const expired = [];
const notificationContext = {
    root: {list: notices, timeoutWithAnimation() {}, timeout(id) { expired.push(id); }},
    NotificationUrgency: {Critical: 2}
};
serviceFunctions('Notifications.qml', ['popupTimeout', 'finishTimeout', 'timeoutNotification'], notificationContext);
assert.equal(notificationContext.popupTimeout(-1, 1), 5000);
assert.equal(notificationContext.popupTimeout(0, 1), 0);
assert.equal(notificationContext.popupTimeout(1200, 1), 1200);
assert.equal(notificationContext.popupTimeout(1200, 2), 1200);
assert.equal(notificationContext.popupTimeout(-1, 2), 0);
notificationContext.timeoutNotification(1);
notificationContext.timeoutNotification(2);
assert.ok(notices.every(notice => notice.closeTimer.running));
notificationContext.finishTimeout(1);
notificationContext.finishTimeout(2);
assert.ok(notices.every(notice => !notice.popup && notice.timer === null));
assert.deepEqual(expired, [1, 2]);

const historyContext = {root: {}, notifComponent: {createObject(parent, properties) { return properties; }}};
serviceFunctions('Notifications.qml', ['historyImage', 'notifToJSON', 'jsonToNotif'], historyContext);
const transient = 'image://qsimage/230/1';
const history = historyContext.notifToJSON({id: 42, appIcon: 'firefox', image: transient, cachedImage: transient});
assert.equal(history.image, '');
assert.equal(history.cachedImage, '');
assert.equal(history.appIcon, 'firefox');
const restoredHistory = historyContext.jsonToNotif({id: 42, appIcon: 'firefox', image: transient, cachedImage: transient});
assert.equal(restoredHistory.image, '');
assert.equal(restoredHistory.appIcon, 'firefox');
const dataImage = 'data:image/png;base64,abcd';
assert.equal(historyContext.historyImage(dataImage), dataImage);
const iconContext = {root: {appIcon: dataImage}, Quickshell: {iconPath(name) { return 'image://icon/' + name; }}};
serviceFunctions('../notifications/NotificationAppIcon.qml', ['iconSource'], iconContext);
assert.equal(iconContext.iconSource(), dataImage);
iconContext.root.appIcon = '/path/to/icon.png';
assert.equal(iconContext.iconSource(), '/path/to/icon.png');
iconContext.root.appIcon = 'firefox';
assert.equal(iconContext.iconSource(), 'image://icon/firefox');
console.log('Notification history drops expired provider handles and preserves usable icon sources');

const clipboardContext = {root: {}};
serviceFunctions('ClipboardService.qml', ['enqueue', 'startNext'], clipboardContext);
const process = {pending: [], running: false};
clipboardContext.enqueue(process, {itemId: 'first', command: ['first']});
clipboardContext.enqueue(process, {itemId: 'second', command: ['second']});
assert.equal(process.itemId, 'first');
assert.equal(process.pending.length, 1);
process.running = false;
clipboardContext.startNext(process);
assert.equal(process.itemId, 'second');
assert.equal(process.pending.length, 0);

const recorderContext = {
    root: {videosDir: '/tmp/space and "quote"', starting: false},
    isRecording: false, starting: false,
    startProcess: {}, prepareProcess: {}, Date
};
serviceFunctions('ScreenRecorder.qml', ['startRecording'], recorderContext);
recorderContext.startRecording(true, true, 'region', '100x100+0+0; literal');
const command = recorderContext.startProcess.command;
assert.equal(command[0], 'gpu-screen-recorder');
assert.ok(command.includes('100x100+0+0; literal'));
assert.ok(command.includes('default_output|default_input'));
assert.ok(command.at(-1).startsWith('/tmp/space and "quote"/'));
assert.ok(recorderContext.prepareProcess.running);
console.log('Notification timing, clipboard request queue and recording argument tests passed');

const captureEvents = [];
const captureContext = {
    root: {monitors: [{name: 'DP-2', x: -1000, y: 100, logicalWidth: 1000, logicalHeight: 800, scale: 1.5}],
        errorOccurred(message) { captureEvents.push(message); },
        imageSaved(path) { captureEvents.push(path); }, runLensScript() { captureEvents.push('lens'); }},
    Paths: {picturesDir: '/pictures', runtimePath: name => '/runtime/' + name, script: name => '/scripts/' + name},
    GlobalStates: {screenshotToolVisible: false}, Visibilities: {setActiveModule(name) { captureEvents.push('close:' + name); }},
    Styling: {animDuration: 300}, initialize() {}, captureMode: 'normal', processingMode: 'normal',
    _freezing: false, toolImagePath: '', finalPath: '', screenshotsDir: '', savedScreenName: '',
    tempPathBase: '/runtime/freeze', getTimestamp: () => 'timestamp',
    captureTimer: {stop() {}, restart() { captureEvents.push('scheduled'); }},
    cropProcess: {running: false}, toolProcess: {running: false}, copyProcess: {running: false},
    cleanupProcess: {running: false}, lensProcess: {running: false}, verifyImageProcess: {running: false},
    LauncherActions: {ocrLangString: () => 'eng+jpn'}, console
};
Object.assign(captureContext, captureContext.root);
captureContext.root = captureContext;
serviceFunctions('Screenshot.qml', ['startCapture', 'cancelCapture', 'prepareOutput', 'saveCapture', 'processRegion', 'processMonitorScreen', 'finishCrop'], captureContext);
captureContext.startCapture('ocr');
assert.deepEqual(captureEvents, ['close:', 'scheduled']);
assert.equal(captureContext.captureTimer.interval, 350);
captureContext.processRegion(-990, 120, 20, 10);
assert.equal(captureContext.processingMode, 'ocr');
assert.equal(captureContext.savedScreenName, 'DP-2');
assert.ok(captureContext.cropProcess.command.includes('30x15+15+30'));
assert.equal(captureContext.finalPath, '/runtime/ocr_timestamp.png');
captureContext.cancelCapture();
assert.equal(captureContext.captureMode, 'normal');
captureContext.finishCrop(0);
assert.deepEqual(Array.from(captureContext.toolProcess.command), ['bash', '/scripts/ocr.sh', 'eng+jpn', '/runtime/ocr_timestamp.png']);
assert.equal(captureContext.copyProcess.running, false);
captureContext.cropProcess.running = false;
captureContext.toolProcess.running = false;
captureContext.captureMode = 'qr';
captureContext.processMonitorScreen('DP-2');
captureContext.cancelCapture();
captureContext.finishCrop(0);
assert.deepEqual(Array.from(captureContext.toolProcess.command), ['bash', '/scripts/qr_scan.sh', '/runtime/qr_timestamp.png']);
captureContext.cropProcess.running = false;
captureContext.toolProcess.running = false;
captureContext.captureMode = 'lens';
captureContext.cancelCapture();
captureContext.processMonitorScreen('DP-2');
assert.equal(captureContext.finalPath, '/pictures/Screenshots/Screenshot_timestamp.png');
captureContext.finishCrop(0);
assert.equal(captureContext.copyProcess.running, true);
assert.equal(captureEvents.at(-1), captureContext.finalPath);
captureContext.processingMode = 'ocr';
captureContext.toolProcess.running = false;
captureContext.finishCrop(1);
assert.equal(captureContext.toolProcess.running, false);
assert.equal(captureEvents.at(-1), 'Failed to save image');
console.log('OCR and QR use frozen crops, preserve job routing after closing, and reset cancelled Lens captures');

const popupEvents = [];
const deferredPopup = [];
const popupContext = {
    root: {}, isOpen: false, visible: true, focusActive: false, popupOpacity: 0, popupScale: 0.9,
    closeTimer: {stop() { popupEvents.push('stop'); }, restart() { popupEvents.push('closing'); }},
    Visibilities: {registerBarPopup() { popupEvents.push('register'); }, unregisterBarPopup() { popupEvents.push('unregister'); }},
    Qt: {callLater(callback) { deferredPopup.push(callback); }}
};
serviceFunctions('../components/BarPopup.qml', ['open', 'close', 'toggle'], popupContext);
popupContext.toggle();
assert.equal(popupContext.isOpen, true);
assert.deepEqual(popupEvents, ['stop', 'register']);
popupContext.close();
deferredPopup.shift()();
assert.equal(popupContext.focusActive, false);
popupContext.open();
deferredPopup.shift()();
assert.equal(popupContext.focusActive, true);
assert.equal(popupContext.popupOpacity, 1);
console.log('Popups reopen during their closing animation and ignore stale focus callbacks');
const parentPopup = {isOpen: true, focusActive: true};
popupContext.root = popupContext;
popupContext.parentPopup = parentPopup;
popupContext.close();
parentPopup.isOpen = false;
while (deferredPopup.length) deferredPopup.shift()();
assert.equal(parentPopup.focusActive, true);
parentPopup.isOpen = true;
popupContext.open();
while (deferredPopup.length) deferredPopup.shift()();
assert.equal(parentPopup.focusActive, false);
popupContext.close();
while (deferredPopup.length) deferredPopup.shift()();
assert.equal(parentPopup.focusActive, true);
console.log('Nested tray menus hand focus back to their open overflow owner');


let replayNotices = 0;
const replayContext = {
    root: {_pendingStart: true, _scanned: true, videosDir: '/tmp/Replays', active: false},
    ScreenRecorder: {capabilitiesReady: false, canRecordDirectly: false},
    Notifications: {notifyInternal() { replayNotices++; }}, prepareProcess: {running: false}
};
serviceFunctions('ReplayService.qml', ['maybeStart'], replayContext);
replayContext.maybeStart();
assert.equal(replayContext.root._pendingStart, true);
assert.equal(replayContext.prepareProcess.running, false);
replayContext.ScreenRecorder.capabilitiesReady = true;
replayContext.maybeStart();
assert.equal(replayNotices, 1);
assert.equal(replayContext.root._pendingStart, false);
assert.equal(replayContext.prepareProcess.running, false);
replayContext.ScreenRecorder.canRecordDirectly = true;
replayContext.root._pendingStart = true;
replayContext.maybeStart();
assert.equal(replayContext.prepareProcess.running, true);
console.log('Replay waits for capture capabilities before starting its daemon');

const captureDirectory = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'pangu-capture-'));
try {
    const {spawnSync} = require('node:child_process');
    const captureContext = {
        root: {monitors: [], tempPathBase: path.join(captureDirectory, 'runtime/freeze')},
        Paths: {runtimeDir: path.join(captureDirectory, 'runtime')},
        freezeProcess: {}, _freezing: true, console: {warn() {}}
    };
    serviceFunctions('Screenshot.qml', ['executeFreezeBatch'], captureContext);
    captureContext.executeFreezeBatch();
    assert.equal(captureContext._freezing, false);
    const literal = 'DP-"$HOME"$(false)';
    captureContext.root.monitors = [{name: literal}, {name: 'failed'}];
    captureContext.executeFreezeBatch();
    const bash = spawnSync('bash', ['-c', 'command -v bash'], {encoding: 'utf8'}).stdout.trim();
    fs.writeFileSync(path.join(captureDirectory, 'grim'), `#!${bash}\n`
        + 'printf "%s\\0" "$2" >> "$PANGU_TEST_CAPTURE_LOG"\n'
        + 'if [ "$2" = failed ]; then exit 4; fi\n'
        + 'printf png > "$3"\n', {mode: 0o755});
    const result = spawnSync(captureContext.freezeProcess.command[0], captureContext.freezeProcess.command.slice(1), {
        encoding: 'utf8', env: {...require('node:process').env,
            PATH: captureDirectory + ':' + require('node:process').env.PATH,
            PANGU_TEST_CAPTURE_LOG: path.join(captureDirectory, 'calls')}
    });
    assert.equal(result.status, 1, result.stderr);
    assert.deepEqual(fs.readFileSync(path.join(captureDirectory, 'calls'), 'utf8').split('\0').filter(Boolean).sort(),
        [literal, 'failed'].sort());
    assert.equal(fs.readFileSync(captureContext.root.tempPathBase + '_' + literal + '.png', 'utf8'), 'png');
} finally {
    fs.rmSync(captureDirectory, {recursive: true});
}
console.log('Screenshot batches preserve literal arguments and report a failed monitor capture');

const firstScreen = {}, removedScreen = {}, newScreen = {};
let destroyed = 0, created = 0;
const firstMonitor = {screen: firstScreen, destroy() { destroyed++; }};
const removedMonitor = {screen: removedScreen, destroy() { destroyed++; }};
const brightnessContext = {
    root: {monitors: [firstMonitor, removedMonitor]},
    Quickshell: {screens: [firstScreen, newScreen]},
    monitorComp: {createObject(parent, properties) { created++; return properties; }}
};
serviceFunctions('Brightness.qml', ['syncMonitors'], brightnessContext);
brightnessContext.syncMonitors();
assert.equal(brightnessContext.root.monitors[0], firstMonitor);
assert.equal(created, 1);
assert.equal(destroyed, 1);
brightnessContext.syncMonitors();
assert.equal(created, 1);
assert.equal(destroyed, 1);

const ddcContext = {
    root: {}, ready: true, isDdc: true, busNum: '7', writePending: false,
    monitor: {brightness: 0.2, rawMaxBrightness: 100}, setProc: {running: false}
};
serviceFunctions('Brightness.qml', ['syncBrightness'], ddcContext);
ddcContext.syncBrightness();
assert.equal(ddcContext.setProc.command.at(-1), 20);
ddcContext.monitor.brightness = 0.8;
ddcContext.syncBrightness();
assert.equal(ddcContext.setProc.command.at(-1), 20);
assert.equal(ddcContext.writePending, true);
ddcContext.setProc.running = false;
ddcContext.syncBrightness();
assert.equal(ddcContext.setProc.command.at(-1), 80);
console.log('Brightness hotplug ownership and DDC write serialization tests passed');

let weatherErrors = 0, weatherResponses = 0, weatherRefreshes = 0;
const weatherContext = {
    root: {
        wasCancelled: false, pendingRefresh: false, isLoading: true,
        handleError() { weatherErrors++; },
        handleResponse() { weatherResponses++; },
        updateWeather() { weatherRefreshes++; }
    },
    SuspendManager: {isSuspending: false},
    Qt: {callLater(callback) { callback(); }}
};
serviceFunctions('WeatherService.qml', ['finishRequest'], weatherContext);
weatherContext.finishRequest(124, '');
assert.equal(weatherErrors, 1);
assert.equal(weatherResponses, 0);
weatherContext.root.pendingRefresh = true;
weatherContext.finishRequest(0, 'stale location');
assert.equal(weatherResponses, 0);
assert.equal(weatherRefreshes, 1);
weatherContext.finishRequest(0, 'current location');
assert.equal(weatherResponses, 1);
weatherContext.root.wasCancelled = true;
weatherContext.finishRequest(143, '');
assert.equal(weatherErrors, 1);
assert.equal(weatherContext.root.isLoading, false);
console.log('Weather timeout, superseded request and cancellation tests passed');

const idleCommands = [];
const idleContext = {
    root: {
        generation: 4, triggered: {},
        activeListeners: [{timeout: 300, onTimeout: 'lock', onResume: 'restore'}],
        executeCommand(command) { idleCommands.push(command); }
    },
    CaffeineService: {inhibit: false}, SuspendManager: {isSuspending: false}
};
serviceFunctions('IdleService.qml', ['renderConfig', 'handleTimeout', 'handleResume', 'resumeAll'], idleContext);
const idleConfig = idleContext.renderConfig([{timeout: 300, onTimeout: 'echo # {\nunsafe config'}], 4);
assert.ok(idleConfig.includes('timeout = 300'));
assert.ok(idleConfig.includes('pangu idle timeout 4 0'));
assert.ok(!idleConfig.includes('unsafe config'));
idleContext.handleTimeout(3, 0);
assert.equal(idleCommands.length, 0);
idleContext.handleTimeout(4, 0);
idleContext.handleTimeout(4, 0);
assert.deepEqual(idleCommands, ['lock']);
idleContext.handleResume(3, 0);
assert.deepEqual(idleCommands, ['lock']);
idleContext.resumeAll();
idleContext.handleResume(4, 0);
assert.deepEqual(idleCommands, ['lock', 'restore']);
idleContext.CaffeineService.inhibit = true;
idleContext.handleTimeout(4, 0);
assert.equal(idleCommands.length, 2);
console.log('Idle daemon generation, command isolation and resume tests passed');

const wallpaperContext = {
    root: {},
    wallpaperConfig: {adapter: {perScreenWallpapers: {'DP-2': 'old'}, currentWall: 'first'}},
    wallpaperPaths: ['first', 'second'], currentIndex: 0, initialLoadCompleted: true,
    Quickshell: {screens: [{name: 'DP-1'}, {name: 'DP-2'}]},
    runMatugenForCurrentWallpaper() {}, generateLockscreenFrame() {}, console
};
serviceFunctions('../widgets/dashboard/wallpapers/WallpaperService.qml', ['setWallpaper', 'clearPerScreenWallpaper'], wallpaperContext);
wallpaperContext.setWallpaper('second', 'DP-2');
assert.equal(wallpaperContext.wallpaperConfig.adapter.currentWall, 'first');
assert.equal(wallpaperContext.wallpaperConfig.adapter.perScreenWallpapers['DP-2'], 'second');
wallpaperContext.setWallpaper('second', 'DP-1');
assert.equal(wallpaperContext.wallpaperConfig.adapter.currentWall, 'second');
wallpaperContext.clearPerScreenWallpaper('DP-1');
assert.equal(wallpaperContext.wallpaperConfig.adapter.perScreenWallpapers['DP-1'], undefined);
assert.equal(wallpaperContext.wallpaperConfig.adapter.perScreenWallpapers['DP-2'], 'second');
console.log('Shared wallpaper per-monitor selection tests passed');

const settingsContext = {root: {editGroups: {}, pauseAutoSave: false}};
serviceFunctions('../../config/Config.qml', ['beginEdit', 'endEdit', 'isPaused'], settingsContext);
settingsContext.beginEdit('theme', ['theme']);
settingsContext.beginEdit('shell', ['bar', 'system']);
assert.equal(settingsContext.isPaused('theme'), true);
assert.equal(settingsContext.isPaused('weather'), false);
settingsContext.endEdit('theme');
assert.equal(settingsContext.isPaused('theme'), false);
assert.equal(settingsContext.isPaused('system'), true);
settingsContext.beginEdit('second', ['system']);
settingsContext.endEdit('shell');
assert.equal(settingsContext.isPaused('system'), true);
settingsContext.root.pauseAutoSave = true;
settingsContext.endEdit('second');
assert.equal(settingsContext.isPaused('weather'), true);
settingsContext.root.pauseAutoSave = false;
assert.equal(settingsContext.isPaused('system'), false);
console.log('Independent settings drafts and batch-save inhibition tests passed');

const globalsSource = fs.readFileSync(path.join(__dirname, '../modules/globals/GlobalStates.qml'), 'utf8');
assert.match(globalsSource, /Config\.snapshot\(/, 'GlobalStates must snapshot the adapters');
const sectionNames = JSON.parse(globalsSource.match(/_shellSections: (\[[^\]]*\])/)[1]);
const shellPanelSource = fs.readFileSync(path.join(__dirname, '../modules/widgets/dashboard/controls/ShellPanel.qml'), 'utf8');
for (const match of shellPanelSource.matchAll(/Config\.(\w+)\.(\w+)\s*=(?!=)/g)) {
    assert.ok(sectionNames.includes(match[1]), `Shell section is not drafted: ${match[1]}.${match[2]}`);
}
console.log('Shell Apply/Discard coverage matches editable controls');

let fileReloads = 0;
const reloadContext = {
    root: {}, ready: true, reloading: false, reloadPending: false, name: 'theme',
    Config: {isPaused() { return true; }}, reload() { fileReloads++; }
};
serviceFunctions('../../config/ConfigFile.qml', ['reloadConfig'], reloadContext);
reloadContext.reloadConfig();
assert.equal(fileReloads, 0);
assert.equal(reloadContext.reloadPending, true);
reloadContext.Config.isPaused = () => false;
reloadContext.reloadConfig();
assert.equal(fileReloads, 1);
assert.equal(reloadContext.reloadPending, false);
assert.equal(reloadContext.reloading, true);
console.log('Settings file reload waits for pending edits');

const monitorA = {name: 'DP-1'}, monitorB = {name: 'DP-2'};
const clearedGrabs = [];
const grabContext = {
    root: {}, _grabs: {}, _grabOrder: [], Qt: {callLater(callback) { callback(); }}
};
serviceFunctions('FocusGrabManager.qml', ['requestGrab', 'releaseGrab', 'hasGrabFor', 'clearTopGrab'], grabContext);
grabContext.requestGrab('first', () => clearedGrabs.push('first'), [{screen: monitorA}]);
assert.equal(grabContext.hasGrabFor(monitorA), true);
assert.equal(grabContext.hasGrabFor(monitorB), false);
grabContext.requestGrab('second', () => clearedGrabs.push('second'), [{screen: monitorB}]);
grabContext.clearTopGrab(monitorA);
assert.deepEqual(clearedGrabs, ['first']);
assert.equal(grabContext.hasGrabFor(monitorB), true);
grabContext.releaseGrab('second');
assert.equal(grabContext.hasGrabFor(monitorB), false);
console.log('Focus grabs and dismissal stay on their owning monitor');

const visibilityContext = {
    root: {}, screens: {}, currentActiveModule: 'dashboard', lastFocusedScreen: 'DP-1',
    Compositor: {focusedMonitor: {name: 'DP-2'}},
    Quickshell: {screens: [monitorA, monitorB]}, clearAll() {},
    screenPropertiesComponent: {createObject(parent, properties) { return properties; }}
};
serviceFunctions('Visibilities.qml', ['_updateMap', 'getForScreen', 'syncScreens', 'isActiveOnFocusedScreen'], visibilityContext);
const oldScreens = visibilityContext.screens;
assert.equal(visibilityContext.getForScreen('DP-2'), null);
assert.equal(visibilityContext.screens, oldScreens);
visibilityContext.syncScreens();
const screenState = visibilityContext.getForScreen('DP-2');
assert.notEqual(visibilityContext.screens, oldScreens);
assert.equal(visibilityContext.getForScreen('DP-2'), screenState);
assert.equal(visibilityContext.isActiveOnFocusedScreen('dashboard'), false);
visibilityContext.Compositor.focusedMonitor = {name: 'DP-1'};
assert.equal(visibilityContext.isActiveOnFocusedScreen('dashboard'), true);
console.log('Monitor state registration is reactive and shortcuts target focused screens');

const paletteContext = {root: {}, pendingPalette: [], paletteProcess: {running: false}};
serviceFunctions('../widgets/dashboard/wallpapers/WallpaperService.qml', ['requestPalette', 'startPalette'], paletteContext);
paletteContext.requestPalette(['matugen', 'first']);
paletteContext.requestPalette(['matugen', 'obsolete']);
paletteContext.requestPalette(['preset', 'latest']);
assert.equal(paletteContext.paletteProcess.command[1], 'first');
paletteContext.paletteProcess.running = false;
paletteContext.startPalette();
assert.equal(paletteContext.paletteProcess.command[1], 'latest');
assert.equal(paletteContext.pendingPalette.length, 0);
console.log('Palette writes are serialized and superseded requests are coalesced');

const presetDirectory = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'pangu-palette-'));
try {
    const presetName = "Quote's preset";
    const userDir = path.join(presetDirectory, 'user', presetName);
    fs.mkdirSync(userDir, {recursive: true});
    fs.writeFileSync(path.join(userDir, 'dark.json'), '{"background":"#123456"}');
    let presetCommand;
    const presetContext = {
        root: {}, activeColorPreset: presetName, Config: {theme: {lightMode: false}},
        officialColorPresetsDir: path.join(presetDirectory, 'official'),
        colorPresetsDir: path.join(presetDirectory, 'user'),
        Paths: {cachePath(name) { return path.join(presetDirectory, name); }},
        requestPalette(command) { presetCommand = command; }
    };
    serviceFunctions('../widgets/dashboard/wallpapers/WallpaperService.qml', ['applyColorPreset'], presetContext);
    presetContext.applyColorPreset();
    const result = require('node:child_process').spawnSync(presetCommand[0], presetCommand.slice(1));
    assert.equal(result.status, 0, result.stderr.toString());
    assert.equal(fs.readFileSync(path.join(presetDirectory, 'colors.json'), 'utf8'), '{"background":"#123456"}');
} finally {
    fs.rmSync(presetDirectory, {recursive: true});
}
console.log('Preset copying preserves quoted paths and falls back to user presets');

const pamContext = {root: {}};
serviceFunctions('LockscreenService.qml', ['resolvePamTarget'], pamContext);
assert.deepEqual({...pamContext.resolvePamTarget(true, true, true, '/shell')}, {directory: '/etc/pam.d', config: 'pangu'});
assert.deepEqual({...pamContext.resolvePamTarget(false, true, true, '/shell')}, {directory: '/etc/pam.d', config: 'hyprlock'});
assert.deepEqual({...pamContext.resolvePamTarget(false, false, true, '/shell')}, {directory: '/etc/pam.d', config: 'login'});
assert.deepEqual({...pamContext.resolvePamTarget(false, false, false, '/shell')}, {directory: '/shell/config/pam', config: 'password.conf'});
console.log('Lockscreen PAM probe falls back through pangu, hyprlock, login and bundled config');

let scannedCommand = null, matugenCommand = null;
const wallSvcContext = {
    root: {},
    defaultWallpaperDir: '/home/alice/Pictures/Wallpapers',
    fallbackDir: '/nix/store/pangu/assets/wallpapers',
    wallpaperDir: '/home/alice/Pictures/Wallpapers',
    scanPending: false,
    scanDirectory: '',
    activeColorPreset: '',
    currentWallpaper: '/nix/store/pangu/assets/wallpapers/01-deep-horizon.jpg',
    initialLoadCompleted: true,
    Paths: {
        home: '/home/alice',
        script(name) { return '/nix/store/pangu/scripts/' + name; },
        asset(name) { return '/nix/store/pangu/assets/' + name; },
        cachePath(name) { return '/custom/cache/pangu/' + name; }
    },
    Config: {theme: {dynamicColors: true, lightMode: false}},
    wallpaperAdapter: {wallPath: ''},
    wallpaperConfig: {adapter: {matugenScheme: 'scheme-tonal-spot'}},
    scanWallpapers: {running: false, command: []},
    getColorSource(filePath) { return filePath; },
    requestPalette(command) { matugenCommand = command; }
};
wallSvcContext.wallpaper = wallSvcContext;
serviceFunctions('../widgets/dashboard/wallpapers/WallpaperService.qml',
    ['expandDirectory', 'setWallpaperDirectory', 'startScan', 'runMatugenForCurrentWallpaper'], wallSvcContext);
wallSvcContext.setWallpaperDirectory('');
assert.equal(wallSvcContext.wallpaperAdapter.wallPath, '/home/alice/Pictures/Wallpapers',
    'Resetting wallpaper directory must preserve user default folder rather than packaged store fallback');
wallSvcContext.startScan();
scannedCommand = [...wallSvcContext.scanWallpapers.command];
assert.deepEqual(scannedCommand, [
    'python3', '/nix/store/pangu/scripts/wallpaper_files.py',
    '/home/alice/Pictures/Wallpapers', '--fallback', '/nix/store/pangu/assets/wallpapers'
]);
wallSvcContext.runMatugenForCurrentWallpaper(false);
assert.deepEqual([...matugenCommand], [
    'python3', '/nix/store/pangu/scripts/matugen_palette.py',
    '/nix/store/pangu/assets/wallpapers/01-deep-horizon.jpg',
    '/nix/store/pangu/assets/matugen/colors.json',
    '/nix/store/pangu/assets/matugen/config.toml',
    'scheme-tonal-spot', 'dark', '/custom/cache/pangu/colors.json'
]);
console.log('Wallpaper fallback keeps user wallPath while matugen targets XDG cache');

const shaderWrites = [], shaderUpdates = [];
const shaderContext = {
    root: {}, Qt: {callLater(callback) { callback(); }}, shaderWriting: false, pendingShader: 'first', shaderSlot: 0,
    currentScreenName: 'DP-1', mpvShaderPath: '', usesMpv: true, tintEnabled: true,
    Paths: {runtimePath(name) { return '/runtime/' + name; }},
    mpvShaderWriter: {path: '', setText(text) { shaderWrites.push(text); }},
    updateMpvRuntime(enabled) { shaderUpdates.push(enabled); }
};
shaderContext.wallpaper = shaderContext;
serviceFunctions('../widgets/dashboard/wallpapers/Wallpaper.qml', ['startShaderWrite', 'finishShaderWrite'], shaderContext);
shaderContext.startShaderWrite();
const firstShaderPath = shaderContext.mpvShaderWriter.path;
assert.equal(shaderContext.mpvShaderPath, '');
shaderContext.pendingShader = 'latest';
shaderContext.startShaderWrite();
assert.deepEqual(shaderWrites, ['first']);
shaderContext.finishShaderWrite(true);
assert.deepEqual(shaderWrites, ['first', 'latest']);
assert.deepEqual(shaderUpdates, []);
assert.notEqual(shaderContext.mpvShaderWriter.path, firstShaderPath);
shaderContext.tintEnabled = false;
shaderContext.finishShaderWrite(true);
assert.deepEqual(shaderUpdates, [false]);
shaderContext.pendingShader = 'failed';
shaderContext.startShaderWrite();
const committedShaderPath = shaderContext.mpvShaderPath;
shaderContext.finishShaderWrite(false);
assert.equal(shaderContext.mpvShaderPath, committedShaderPath);
assert.equal(shaderContext.shaderWriting, false);
console.log('Shader writes publish only completed files and respect the latest tint setting');

const ipcContext = {
    root: {}, queue: [], job: null,
    ipcRetryTimer: {job: null, stop() {}}, pump() {}
};
serviceFunctions('../widgets/dashboard/wallpapers/Wallpaper.qml', ['send'], ipcContext);
ipcContext.send('/mpv.sock', ['set_property', 'glsl-shaders', 'old'], 10);
ipcContext.job = ipcContext.queue.shift();
ipcContext.ipcRetryTimer.job = {...ipcContext.job};
ipcContext.send('/mpv.sock', ['set_property', 'glsl-shaders', 'new'], 10);
ipcContext.send('/mpv.sock', ['set_property', 'glsl-shaders', ''], 10);
assert.equal(ipcContext.job.retries, 0);
assert.equal(ipcContext.ipcRetryTimer.job, null);
assert.equal(ipcContext.queue.length, 1);
assert.equal(JSON.parse(ipcContext.queue[0].data).command[2], '');
console.log('New MPV settings supersede queued commands and stale retries');

const engineDirectory = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'pangu-engine-'));
try {
    const {spawnSync} = require('node:child_process');
    const configDir = path.join(engineDirectory, 'Linux Wallpaper Engine');
    fs.mkdirSync(configDir);
    const background = "/wallpapers/Quote's scene";
    fs.writeFileSync(path.join(configDir, 'settings.json'), JSON.stringify({
        audioProcessing: true, pauseOnFullscreen: false, volume: 80, disableMouse: true
    }));
    fs.writeFileSync(path.join(configDir, 'wallpaper-overrides.json'), JSON.stringify({overrides: {
        [background]: {audioProcessing: false, disableMouse: false, volume: 0,
            customProperties: {caption: 'legacy caption', bloom: true, inherited: 'keep'}}
    }}));
    fs.mkdirSync(path.join(engineDirectory, 'pangu'));
    fs.writeFileSync(path.join(engineDirectory, 'pangu/wallpaper-engine.json'), JSON.stringify({
        [background]: {caption: 'literal $value; with spaces', bloom: false, speed: 0}
    }));
    const bash = spawnSync('bash', ['-c', 'command -v bash'], {encoding: 'utf8'}).stdout.trim();
    fs.writeFileSync(path.join(engineDirectory, 'linux-wallpaperengine'),
        `#!${bash}\nprintf '%s\\n' "$$" "$@"\n`, {mode: 0o755});
    const result = spawnSync('bash', [path.join(__dirname, '../scripts/wallpaperengine.sh'),
        'apply', background, 'DP-1'], {encoding: 'utf8', env: {
            ...require('node:process').env, XDG_CONFIG_HOME: engineDirectory,
            PATH: engineDirectory + ':' + require('node:process').env.PATH
        }});
    assert.equal(result.status, 0, result.stderr);
    const args = result.stdout.trim().split('\n');
    assert.equal(Number(args.shift()), result.pid, 'Renderer must replace the owned process');
    assert.equal(args[args.indexOf('--bg') + 1], background);
    assert.equal(args[args.indexOf('--volume') + 1], '0');
    assert.ok(args.includes('--no-audio-processing'));
    assert.ok(args.includes('--no-fullscreen-pause'));
    assert.ok(!args.includes('--disable-mouse'));
    assert.equal(args[args.indexOf('--set-property') + 1], 'caption=literal $value; with spaces');
    assert.ok(args.includes('bloom=0'));
    assert.ok(args.includes('speed=0'));
    assert.ok(args.includes('inherited=keep'));
} finally {
    fs.rmSync(engineDirectory, {recursive: true});
}
console.log('Wallpaper Engine keeps process ownership, false overrides, and literal arguments');

const exportWrites = [], exportNotifications = [];
const exportContext = {
    root: {}, pendingText: null, savedText: null, writingText: '', saving: false,
    resyncing: false, writeFailures: 0, reloadCount: 0, path: '/test/generated.conf',
    directoryReady: true, Qt: {callLater(callback) { callback(); }},
    reload() { exportContext.reloadCount++; },
    failed() { exportContext.failureCount = (exportContext.failureCount || 0) + 1; },
    console: {warn() {}},
    setText(text) { exportWrites.push(text); }, written() { exportNotifications.push(exportContext.savedText); }
};
serviceFunctions('../components/GeneratedFile.qml', ['write', 'startWrite', 'finishWrite', 'finishResync'], exportContext);
exportContext.write('first');
exportContext.write('discarded');
exportContext.write('latest');
exportContext.finishWrite(true);
assert.deepEqual(exportNotifications, []);
assert.deepEqual(exportWrites, ['first', 'latest']);
exportContext.finishWrite(true);
assert.deepEqual(exportNotifications, ['latest']);
exportContext.write('latest');
assert.equal(exportWrites.length, 2);
assert.deepEqual(exportNotifications, ['latest', 'latest']);
exportContext.write('retry');
exportContext.finishWrite(false);
assert.equal(exportContext.reloadCount, 1);
assert.equal(exportWrites.length, 3);
exportContext.finishResync();
assert.equal(exportWrites.length, 4);
exportContext.finishWrite(true);
exportContext.write('outdated');
exportContext.write('newer');
exportContext.finishWrite(false);
assert.equal(exportContext.pendingText, 'newer');
exportContext.write('newest');
assert.equal(exportWrites.at(-1), 'outdated');
exportContext.finishResync();
assert.equal(exportWrites.at(-1), 'newest');
exportContext.finishWrite(true);
assert.equal(exportNotifications.at(-1), 'newest');
exportContext.write('unwritable');
for (let failure = 1; failure <= 3; failure++) {
    exportContext.finishWrite(false);
    assert.equal(exportContext.writeFailures, failure);
    exportContext.finishResync();
}
assert.equal(exportContext.saving, false);
assert.equal(exportContext.resyncing, false);
assert.equal(exportContext.failureCount, 1);
console.log('Generated files coalesce edits, retain newer output across failures, and stop after three retries');

const nightTimer = {interval: 0, running: false, stop() { this.running = false; }, restart() { this.running = true; }};
const nightContext = {
    root: {}, active: true, restored: true, stopping: false, restartFailures: 0,
    restartTimer: nightTimer, wlsunsetProcess: {running: true},
    Config: {initialLoadComplete: true}, console: {warn() {}}
};
serviceFunctions('NightLightService.qml', ['reconcile', 'processExited'], nightContext);
nightContext.reconcile();
assert.equal(nightContext.active, true);
assert.equal(nightContext.stopping, true);
assert.equal(nightContext.wlsunsetProcess.running, false);
nightContext.active = false;
nightContext.reconcile();
nightContext.processExited(0);
assert.equal(nightTimer.running, false);
nightContext.active = true;
for (let i = 0; i < 12; i++) nightContext.processExited(1);
assert.equal(nightTimer.interval, 30000);
assert.equal(nightContext.active, true);
console.log('Night-light restarts preserve intent, respect disabling, and back off after failures');

const autoContext = {
    root: {enabled: true}, SuspendManager: {isSuspending: false},
    schedule: {day: 480, night: 1200}, boundaryTimer: {restart() {}},
    Config: {initialLoadComplete: true, theme: {lightMode: null}, isPaused() { return true; }, save() { throw new Error('Draft was saved'); }}
};
serviceFunctions('AutoThemeService.qml', ['minutesOf', 'isLightAt', 'nextBoundary', 'apply'], autoContext);
assert.equal(autoContext.minutesOf('23:59', 480), 1439);
for (const time of ['24:00', '08:99', '8:30garbage', '', undefined])
    assert.equal(autoContext.minutesOf(time, 480), 480);
assert.equal(autoContext.isLightAt(600, 480, 1200), true);
assert.equal(autoContext.isLightAt(60, 1200, 480), true);
assert.equal(autoContext.isLightAt(600, 1200, 480), false);
assert.equal(autoContext.isLightAt(480, 480, 480), false);
const late = new Date(2026, 8, 6, 23, 0);
assert.equal(autoContext.nextBoundary(late, 1200, 480), new Date(2026, 8, 7, 8, 0).getTime());
autoContext.apply();
assert.equal(autoContext.Config.theme.lightMode, null);
assert.ok(autoContext.boundaryTimer.interval > 0);
console.log('Automatic theme validates times, handles midnight, and leaves settings drafts alone');

let usageSignals = 0;
const usageContext = {
    root: {}, usageData: {}, pendingUsage: [], dataLoaded: false,
    store: {ready: true, data: {}, save() {}},
    saveTimer: {restart() {}}, Date, maxBoostScore: 200, dayInMs: 86400000,
    usageDataReady() {}, usageChanged() { usageSignals++; }
};
serviceFunctions('UsageTracker.qml', ['validate', 'finishLoad', 'recordUsage', 'getUsageScore'], usageContext);
usageContext.recordUsage('early.desktop');
const loadedUsage = usageContext.validate({
    'early.desktop': {count: 4, lastUsed: Date.now()},
    invalid: {count: 'oops', lastUsed: null},
    future: {count: 1, lastUsed: Date.now() + 1e12}
});
usageContext.usageData = loadedUsage;
usageContext.store.data = loadedUsage;
usageContext.finishLoad();
assert.equal(usageContext.usageData['early.desktop'].count, 5);
assert.equal(usageContext.getUsageScore('invalid'), 0);
assert.ok(usageContext.getUsageScore('future') <= 200 + Math.log(2) * 20);
usageContext.recordUsage('__proto__');
assert.equal(usageContext.usageData.__proto__.count, 1);
assert.ok(Number.isFinite(usageContext.getUsageScore('__proto__')));
assert.equal(usageSignals, 2);
const settled = usageContext.usageData;
usageContext.finishLoad();
assert.equal(usageContext.usageData, settled);
console.log('Usage history validates persisted data and preserves launches during initial loading');

const launchRequests = [];
const launchContext = {
    root: {}, ApplicationLauncher: {launchDesktop(id) { launchRequests.push(id); }}
};
serviceFunctions('AppSearch.qml', ['launchApp'], launchContext);
launchContext.launchApp({id: 'terminal-app.desktop', runInTerminal: true, command: ['wrong fallback']});
assert.deepEqual(launchRequests, ['terminal-app.desktop']);
launchContext.launchApp(null);
assert.equal(launchRequests.length, 1);
const scopeContext = {
    root: {},
    Quickshell: {
        env(key) {
            return ({
                PATH: '/nix/store/pangu-runtime/bin',
                PANGU_USER_PATH: '/etc/profiles/per-user/test/bin:/run/current-system/sw/bin',
                PANGU_USER_QT_PLUGIN_PATH: '/etc/profiles/per-user/test/lib/qt-6/plugins',
                PANGU_USER_QML2_IMPORT_PATH: '/etc/profiles/per-user/test/lib/qt-6/qml',
                PANGU_USER_QML_IMPORT_PATH: '__UNSET__'
            })[key] ?? null;
        }
    }
};
serviceFunctions('ApplicationLauncher.qml', ['scopedCommand'], scopeContext);
const scoped = scopeContext.scopedCommand(['xdg-open', '/path/with $literal and spaces']);
assert.ok(scoped.includes('--expand-environment=no'));
assert.ok(scoped.includes('--slice=app.slice'));
assert.equal(scoped[scoped.length - 1], '/path/with $literal and spaces');
const envIdx = scoped.indexOf('env');
const cmdIdx = scoped.indexOf('xdg-open');
const envTokens = scoped.slice(envIdx + 1, cmdIdx);
let seenAssignment = false;
for (let i = 0; i < envTokens.length; i++) {
    if (envTokens[i] === '-u') {
        assert.equal(seenAssignment, false, 'env -u flags must precede NAME=VALUE assignments');
        i++;
    } else {
        assert.ok(envTokens[i].includes('='), `unexpected env token: ${envTokens[i]}`);
        seenAssignment = true;
    }
}
assert.ok(envTokens.includes('PATH=/etc/profiles/per-user/test/bin:/run/current-system/sw/bin:/nix/store/pangu-runtime/bin'));
console.log('Application launches use desktop IDs and isolated scopes with literal arguments');

const placementCalls = [];
const oldToplevel = {};
const staleClients = [{title: "Pangu Settings", nativeToplevel: oldToplevel, address: "old", workspace: {id: 1}}];
const placementContext = {
    root: {},
    clientsBeforeMapping: [oldToplevel],
    settingsWindow: {title: "Pangu Settings"},
    settingsTab: {focusSearchInput() {}},
    GlobalStates: {settingsTargetWorkspaceId: 2},
    Compositor: {clients: {values: staleClients}, dispatch(command) { placementCalls.push(command); }}
};
serviceFunctions('../widgets/config/SettingsWindow.qml', ['placeOnTargetWorkspace'], placementContext);
assert.equal(placementContext.placeOnTargetWorkspace(), false);
assert.equal(placementCalls.length, 0);
placementContext.Compositor.clients.values = staleClients.map(client => ({...client}));
assert.equal(placementContext.placeOnTargetWorkspace(), false);
placementContext.Compositor.clients.values = [{title: "Pangu Settings", nativeToplevel: {}, address: "new", workspace: {id: 1}}];
assert.equal(placementContext.placeOnTargetWorkspace(), true);
assert.deepEqual(placementCalls, ['movetoworkspacesilent 2, address:new', 'focuswindow address:new']);

const themeWrites = [];
const themeContext = {
    root: {},
    Qt: {callLater(callback) {}},
    directoryReady: true,
    saving: false,
    resyncing: false,
    pendingText: "",
    savedText: null,
    writingText: "",
    prepareDirectory: {running: false},
    setText(text) { themeWrites.push(text); },
    written() { themeContext.writeCount = (themeContext.writeCount || 0) + 1; }
};
serviceFunctions('../components/GeneratedFile.qml', ['startWrite'], themeContext);
themeContext.startWrite();
assert.deepEqual(themeWrites, []);
assert.equal(themeContext.savedText, "");
assert.equal(themeContext.writeCount, 1);
themeContext.pendingText = "content";
themeContext.startWrite();
assert.deepEqual(themeWrites, ["content"]);
assert.equal(themeContext.saving, true);
console.log('Theme exports treat an empty write as a completed no-op');

const composerContext = {root: {gaps: {}}};
serviceFunctions('Compositor.qml', ['handleRawEvent', 'gapFor'], composerContext);
composerContext.handleRawEvent({name: 'custom', data: 'centergap,DP-1,100,500,1'});
let gap = composerContext.gapFor('DP-1');
assert.equal(gap.x, 100);
assert.equal(gap.width, 500);
assert.equal(gap.square, true);
composerContext.handleRawEvent({name: 'custom', data: 'centergap,DP-1,100,500,1'});
assert.equal(composerContext.gapFor('DP-1').width, 500);
composerContext.handleRawEvent({name: 'custom', data: 'centergap,DP-1,0,0,0'});
assert.equal(composerContext.gapFor('DP-1'), null);
composerContext.handleRawEvent({name: 'custom', data: 'centergap,DP-2,0,0,0'});
composerContext.handleRawEvent({name: 'workspace', data: 'ignored'});
assert.equal(Object.keys(composerContext.root.gaps).length, 0);
console.log('Centered-layout gap events are parsed and cleared per screen');

const compositorCalls = [];
const compositorContext = {
    root: {request(payload) { compositorCalls.push(payload); }},
    Hyprland: {dispatch(command) { compositorCalls.push(command); }}, console,
    refresh: {running: false, start() { this.running = true; }},
    snapshot: {running: false, start() { this.running = true; }}
};
serviceFunctions('Compositor.qml', ['logicalSize', 'luaString', 'windowTarget', 'moveFloatingWindow',
    'dispatch', 'moveCursor', 'injectKeyState', 'splitCombo', 'scheduleRefresh', 'scheduleSnapshot'], compositorContext);
for (const transform of [0, 1, 3, 5, 7]) {
    const size = compositorContext.logicalSize({width: 3840, height: 1440, scale: 2, transform});
    assert.equal(size.width, transform % 2 ? 720 : 1920);
    assert.equal(size.height, transform % 2 ? 1920 : 720);
}
const {spawnSync} = require('node:child_process');
const literalLua = 'a"\\b\n\u0001' + '2 Ö';
const quoted = spawnSync('lua', ['-e', 'io.write(' + compositorContext.luaString(literalLua) + ')'], {encoding: 'utf8', timeout: 3000});
assert.equal(quoted.status, 0, quoted.stderr);
assert.equal(quoted.stdout, literalLua);
compositorContext.dispatch('focusmonitor DP-"quoted"');
assert.ok(compositorCalls.pop().includes('DP-\\"quoted\\"'));
compositorContext.moveFloatingWindow('abc', 2, 0.25, 0.5);
const transaction = compositorCalls.pop();
const moved = spawnSync('lua', ['-e', `
local source = {x = 0, y = 0, width = 1920, height = 1080, transform = 0, scale = 1}
local destination = {x = -100, y = 50, width = 3840, height = 1440, transform = 1, scale = 2}
local w = {floating = true, workspace = {id = 1, monitor = source}}
local calls = 0
hl = {get_window = function(selector) assert(selector == 'address:0xabc'); return w end,
    dsp = {window = {move = function(args) return args end}},
    dispatch = function(args)
        calls = calls + 1
        assert(args.window == w)
        if calls == 1 then
            assert(args.workspace == 2 and args.follow == false)
            w.workspace = {id = 2, monitor = destination}
        else assert(args.x == 80 and args.y == 1010) end
    end}
${transaction.slice('eval '.length)}
assert(calls == 2)
`], {encoding: 'utf8', timeout: 3000});
assert.equal(moved.status, 0, moved.stderr);
compositorContext.moveFloatingWindow('abc', 2, Infinity, 0.5);
compositorContext.moveCursor(NaN, 5);
compositorContext.injectKeyState('CTRL+A', 'invalid');
assert.equal(compositorCalls.length, 0);
compositorContext.injectKeyState('CTRL+A', 'down');
assert.ok(compositorCalls.pop().includes('state = "down"'));
compositorContext.scheduleRefresh();
compositorContext.scheduleSnapshot();
assert.equal(compositorContext.refresh.running, true);
assert.equal(compositorContext.snapshot.running, true);
composerContext.handleRawEvent({name: 'custom', data: 'centergap,DP-1,NaN,500,1'});
assert.equal(composerContext.gapFor('DP-1'), null);
assert.equal(composerContext.handleRawEvent({name: 'custom', data: 'centergap,DP-1,100,500,1'}), true);
console.log('Compositor moves use ordered Lua, destination geometry and literal selectors');

const previewMoves = [];
for (const file of ['OverviewWindow.qml', 'ScrollingWorkspace.qml']) {
    const previewContext = {
        root: {windowData: {address: 'abc'}, monitorData: {logicalWidth: 1920, logicalHeight: 1080},
            scale: 0.25, scale_: 0.25, barPosition: 'left', barReserved: 44},
        Compositor: {moveFloatingWindow(...args) { previewMoves.push(args); }}
    };
    serviceFunctions('../widgets/overview/' + file, ['moveFloatingWindow'], previewContext);
    if (file === 'OverviewWindow.qml') previewContext.moveFloatingWindow(2, 20, 14);
    else previewContext.moveFloatingWindow('abc', 2, 20, 14);
}
assert.deepEqual(previewMoves[0], ['abc', 2, 124 / 1920, 56 / 1080]);
assert.deepEqual(previewMoves[1], previewMoves[0]);
console.log('Both overview modes restore reserved bar space before placing floating windows');

const detailState = {
    selectedIndex: 2, renameHighlightsCancel: false,
    deleteMode: false, pendingDeleteId: '', originalSelectedIndex: -1, deleteButtonIndex: 0,
    renameMode: false, pendingRenameId: '', pendingRenameName: '', renameSelectedIndex: -1, renameButtonIndex: 1, pendingRenamedId: '',
    refreshes: 0, focuses: 0, resultsIndex: -1,
    refresh() { this.refreshes++; }, focusSearch() { this.focuses++; },
    setResultsCurrentIndex(value) { this.resultsIndex = value; },
    prepareRename(id) { return 'name:' + id; }
};
const detailContext = {root: detailState, ctrl: detailState};
serviceFunctions('../components/ListDetailController.qml', ['enterDeleteMode', 'cancelDeleteMode', 'enterRenameMode', 'cancelRenameMode', 'cancelModes'], detailContext);
detailContext.enterDeleteMode('a');
assert.equal(detailState.deleteMode, true);
assert.equal(detailState.pendingDeleteId, 'a');
assert.equal(detailState.originalSelectedIndex, 2);
detailState.selectedIndex = 4;
detailContext.cancelDeleteMode();
assert.equal(detailState.deleteMode, false);
assert.equal(detailState.selectedIndex, 2);
assert.equal(detailState.resultsIndex, 2);
assert.equal(detailState.refreshes, 1);
assert.equal(detailState.focuses, 1);
detailContext.enterRenameMode('b');
assert.equal(detailState.renameMode, true);
assert.equal(detailState.pendingRenameName, 'name:b');
assert.equal(detailState.renameSelectedIndex, 2);
detailState.pendingRenamedId = 'b';
detailState.selectedIndex = 9;
detailContext.cancelRenameMode();
assert.equal(detailState.renameMode, false);
assert.equal(detailState.pendingRenameName, '');
assert.equal(detailState.selectedIndex, 9, 'A pending rename must not restore the selection');
console.log('List-detail delete/rename state machine is shared');

const controlsDir = path.join(__dirname, '../modules/widgets/dashboard/controls');
const indexSource = fs.readFileSync(path.join(controlsDir, 'SettingsIndex.qml'), 'utf8');
const indexEntries = [...indexSource.matchAll(/\{ label: "([^"]*)", keywords: "[^"]*", section: "(\w*)", subSection: "(\w*)", subLabel: "([^"]*)"/g)]
    .map(match => ({label: match[1], section: match[2], subSection: match[3], subLabel: match[4]}));
assert.ok(indexEntries.length > 200, 'Expected the settings search index to be populated');
const settingsTab = fs.readFileSync(path.join(controlsDir, 'SettingsTab.qml'), 'utf8');
const panelBlock = settingsTab.match(/panelComponents: \[([\s\S]*?)\n\s*\]/)[1];
const panels = {};
for (const match of panelBlock.matchAll(/component: "(\w+\.qml)",\s*\n\s*section: "(\w+)"/g))
    panels[match[2]] = match[1];
const subsections = {};
for (const [section, file] of Object.entries(panels)) {
    const source = fs.readFileSync(path.join(controlsDir, file), 'utf8');
    subsections[section] = new Set([...source.matchAll(/currentSection === "(\w+)"/g)].map(match => match[1]));
}
for (const entry of indexEntries) {
    assert.ok(entry.label.length > 0, `Settings index entry has no label (${entry.section}/${entry.subSection})`);
    assert.ok(panels[entry.section], `Settings index targets an unknown section: ${entry.section}`);
    if (entry.subSection) {
        assert.ok(subsections[entry.section].has(entry.subSection),
            `Settings index targets an unknown subsection: ${entry.section} > ${entry.subSection}`);
        assert.ok(entry.subLabel.length > 0, `Settings index entry ${entry.section} > ${entry.subSection} has no subLabel`);
    }
}
for (const [section, subs] of Object.entries(subsections)) {
    for (const sub of subs) {
        assert.ok(indexEntries.some(entry => entry.section === section && entry.subSection === sub),
            `Panel subsection is not searchable: ${section} > ${sub}`);
    }
}
console.log('Settings search index targets match the panels');

const configSource = fs.readFileSync(path.join(__dirname, '../config/Config.qml'), 'utf8');
assert.match(configSource, /name: "pinnedapps"\n\s*path: Paths\.dataPath\("pinnedapps\.json"\)/,
    'pinnedapps must live in the shell data dir that nix overrides target');
assert.match(configSource, /name: "macros"/, 'Macros must persist through a ConfigFile adapter');
console.log('Pinned apps path matches the nix override target');

const macroSource = fs.readFileSync(path.join(__dirname, '../modules/services/macro_utils.js'), 'utf8')
    .replace(/^\.pragma library\n/, '');
const macroContext = vm.createContext({module: {exports: {}}, console});
vm.runInContext(macroSource
    + '\nmodule.exports = {normalizeMacro, normalizeStep, normalizeTrigger, blankMacro, blankStep, blankTriggerFor, bindsLua, luaQuote, runCommand, sequenceCommand, sanitizeCombo, isValidCombo, describeTrigger, stepTitle, matchesQuery, matchesOptionalQuery, clientMatches, conditionMet, describeSystemEvent, normalizeTimeOfDay, normalizeHexColor, normalizeHexColors, asArray, delayBounds, sampleDelayMs};',
    macroContext, {filename: 'macro_utils.js'});
const macroUtils = macroContext.module.exports;
const macro = macroUtils.normalizeMacro({
    name: 'Greet "friend"',
    trigger: {type: 'hotkey', keys: 'SUPER + SHIFT + M'},
    steps: [{type: 'delay', ms: 'nope'}, {type: 'key', keys: 'Return'}, {type: 'click', button: 'sideways'}]
});
assert.equal(macro.steps[0].ms, 500, 'Invalid delay falls back to a default');
assert.equal(macro.steps[2].button, 'left', 'Unknown click button falls back to left');
assert.equal(macroUtils.normalizeStep({type: 'sound', path: '/a/b/boom.mp3'}).path, '/a/b/boom.mp3');
assert.equal(macroUtils.normalizeStep({type: 'sound'}).path, '', 'A sound step defaults to no path');
assert.equal(macroUtils.stepTitle({type: 'sound', path: '/a/b/boom.mp3'}), 'boom.mp3');
assert.equal(macroUtils.stepTitle({type: 'sound', path: ''}), 'Play sound');
assert.equal(macroUtils.normalizeStep({type: 'click', button: 'left', x: 10.6, y: 20.2}).x, 11, 'Positions are rounded');
assert.equal(macroUtils.normalizeStep({type: 'click', button: 'left', x: 10.6, y: 20.2}).y, 20);
assert.equal(macroUtils.normalizeStep({type: 'click', button: 'left', x: 'nope', y: 1}).x, undefined, 'Non-numeric positions are dropped');
assert.equal(macroUtils.stepTitle({type: 'click', button: 'left', x: 5, y: 6}), 'left click @ 5,6');
assert.equal(macroUtils.describeTrigger(macroUtils.normalizeTrigger({type: 'timer', seconds: 0})), 'Every 1s');
const binds = macroUtils.bindsLua([macro]);
assert.ok(binds.includes('macro_bind("SUPER + SHIFT + M"'), 'Hotkey binds quote the combo');
assert.ok(binds.includes("pangu run 'macros-run " + macro.id + "'"), 'Macro ids are passed as one run argument');
assert.ok(binds.includes('Macro: Greet \\"friend\\"'), 'Names are escaped for Lua');
assert.ok(binds.includes('local function macro_bind'), 'Each bind is isolated from the others');
assert.ok(binds.includes(', false)'), 'Hotkey binds consume their key');
const sequence = macroUtils.normalizeMacro({
    id: 'm_seq', name: 'Seq', trigger: {type: 'sequence', keys: ['SUPER + A', 'SUPER + B']}, steps: [{type: 'text', text: 'hi'}]
});
const sequenceBinds = macroUtils.bindsLua([sequence]);
assert.ok(sequenceBinds.includes('macros-seq m_seq 0') && sequenceBinds.includes('macros-seq m_seq 1'),
    'Every sequence step gets a bind');
assert.ok(sequenceBinds.includes(', true)'), 'Sequence steps pass the key through to the window');
assert.ok(!macroUtils.bindsLua([Object.assign({}, sequence, {enabled: false})]).includes('macro_bind('),
    'Disabled macros emit no binds');
assert.ok(!macroUtils.bindsLua([{id: 'm_x', name: 'No trigger', trigger: {type: 'none'}, steps: []}]).includes('macro_bind('),
    'Manual macros emit no binds');

assert.equal(macroUtils.sanitizeCombo('CTRL + \u0009'), 'CTRL', 'Control bytes are stripped from combos');
assert.equal(macroUtils.sanitizeCombo(' Ctrl + I '), 'Ctrl + I');
assert.equal(macroUtils.isValidCombo('CTRL'), false, 'Modifier-only combos are rejected');
assert.equal(macroUtils.isValidCombo('CTRL + I'), true);
assert.equal(macroUtils.isValidCombo('CTRL + SHIFT + \u00d6'), false, 'Raw Unicode is not a keysym name');
assert.equal(macroUtils.isValidCombo('CTRL + SHIFT + odiaeresis'), true);
assert.equal(macroUtils.sanitizeCombo('CTRL + \u001f').indexOf('+'), -1);
assert.ok(!macroUtils.bindsLua([{id: 'm_bad', name: 'Bad', enabled: true, trigger: {type: 'hotkey', keys: 'CTRL + \u001f'}, steps: []}]).includes('macro_bind('),
    'Combos without a real key emit no bind');
assert.ok(macroUtils.luaQuote('a\u0001b').includes('\\001'), 'Remaining control bytes are escaped for Lua');
assert.ok(macroUtils.bindsLua([{id: 'm_o', name: 'O', enabled: true, trigger: {type: 'hotkey', keys: 'CTRL + SHIFT + odiaeresis'}, steps: []}])
    .includes('"CTRL + SHIFT + odiaeresis"'), 'Non-ASCII keysym names survive generation');
console.log('Macro normalization, Lua escaping, combo validation and bind coverage tests passed');

const literalId = 'm_\'$HOME $(printf unexpected) "Ö"';
for (const [command, expected] of [
    [macroUtils.runCommand(literalId), 'macros-run ' + literalId],
    [macroUtils.sequenceCommand(literalId, 2), 'macros-seq ' + literalId + ' 2']
]) {
    const ran = spawnSync('bash', ['-c', 'pangu() { [ "$#" = 2 ] && [ "$1" = run ] || exit 1; printf %s "$2"; }; ' + command], {encoding: 'utf8'});
    assert.equal(ran.status, 0, ran.stderr);
    assert.equal(ran.stdout, expected);
}
console.log('Macro hotkeys preserve literal IDs through the command shell');

const macroStarts = [];
const svcMacros = {
    a: {id: 'a', name: 'A', enabled: true, loop: {mode: 'none', count: 1, delayMs: 0}, steps: [{type: 'key', keys: 'A'}]},
    b: {id: 'b', name: 'B', enabled: true, loop: {mode: 'none', count: 1, delayMs: 0}, steps: [{type: 'key', keys: 'B'}]},
    c: {id: 'c', name: 'C', enabled: true, loop: {mode: 'count', count: 2, delayMs: 0}, steps: [{type: 'key', keys: 'C'}]},
};
const macroServiceRoot = {
    enabled: true, playing: false, activeId: '', activeName: '', activeStep: -1,
    repeatLeft: 0, currentMacro: null, currentStepIndex: 0, loopPending: false,
    queue: [], runToken: 0, stepToken: -1, processes: [],
    list: () => Object.values(svcMacros),
    findMacro: id => svcMacros[id] || null,
    _runStep: () => macroStarts.push(macroServiceRoot.activeId),
    _killProcesses: () => { macroServiceRoot.processes = []; }
};
const macroServiceContext = {
    root: macroServiceRoot,
    stepTimer: {stop() {}, restart() {}, interval: 0},
    Qt: {callLater() {}},
    MacroUtils: {normalizeMacro: macro => JSON.parse(JSON.stringify(macro))},
    console
};
serviceFunctions('MacroService.qml', ['run', 'stop', '_enqueue', '_dequeue', '_startMacro', '_start', '_resetPlayback', '_finishPass', '_reconcileActive'], macroServiceContext);

macroServiceRoot.run('a', true);
assert.equal(macroServiceRoot.playing, true);
assert.equal(macroServiceRoot.activeId, 'a');
macroServiceRoot.run('b', false);
assert.equal(JSON.stringify(macroServiceRoot.queue), JSON.stringify(['b']), 'A busy channel queues non-urgent triggers');
assert.equal(macroServiceRoot.activeId, 'a', 'A queued trigger must not interrupt playback');
macroServiceRoot.run('a', false);
assert.equal(macroServiceRoot.playing, true, 'A timer re-firing its own macro must not toggle it off');
assert.equal(JSON.stringify(macroServiceRoot.queue), JSON.stringify(['b']));
macroServiceRoot.run('b', false);
assert.equal(JSON.stringify(macroServiceRoot.queue), JSON.stringify(['b']), 'Duplicate queue entries are collapsed');
macroServiceRoot._finishPass();
assert.equal(macroServiceRoot.activeId, 'b', 'Finishing a run dequeues the next macro');
assert.equal(JSON.stringify(macroServiceRoot.queue), JSON.stringify([]));
macroServiceRoot.run('b', true);
assert.equal(macroServiceRoot.playing, false, 'An urgent trigger toggles the active macro off');
assert.equal(JSON.stringify(macroServiceRoot.queue), JSON.stringify([]), 'Explicit stop clears the queue');
macroServiceRoot.run('a', true);
macroServiceRoot.run('c', true);
assert.equal(macroServiceRoot.activeId, 'c', 'An urgent trigger preempts the active macro');
assert.equal(macroServiceRoot.repeatLeft, 2);
macroServiceRoot.currentMacro = svcMacros.c;
macroServiceRoot.repeatLeft = 2;
macroServiceRoot._finishPass();
assert.equal(macroServiceRoot.playing, true, 'A count loop keeps playing until its count is spent');
assert.equal(macroServiceRoot.repeatLeft, 1);
macroServiceRoot._finishPass();
assert.equal(macroServiceRoot.playing, false);
assert.equal(macroServiceRoot.repeatLeft, 0);
const tokensBefore = macroServiceRoot.runToken;
macroServiceRoot.stop();
assert.ok(macroServiceRoot.runToken > tokensBefore, 'Teardown invalidates stale async continuations');

svcMacros.a.loop = {mode: 'infinite', count: 1, delayMs: 0};
macroServiceRoot.run('a', true);
assert.equal(macroServiceRoot.currentMacro.loop.mode, 'infinite');
svcMacros.a.enabled = false;
macroServiceRoot._reconcileActive();
assert.equal(macroServiceRoot.playing, false, 'Disabling the active macro stops the running instance');
svcMacros.a.enabled = true;
svcMacros.a.loop = {mode: 'infinite', count: 1, delayMs: 0};
macroServiceRoot.run('a', true);
svcMacros.a.loop = {mode: 'none', count: 1, delayMs: 0};
macroServiceRoot._reconcileActive();
assert.equal(macroServiceRoot.currentMacro.loop.mode, 'none', 'A loop edit is adopted by the running instance');
assert.equal(macroServiceRoot.repeatLeft, -1);
assert.equal(macroServiceRoot.playing, true, 'A loop edit does not interrupt the current pass');
console.log('Macro playback queue, loop counts, urgent toggling, run tokens and live edits are consistent');

assert.equal(macroUtils.matchesQuery('Order #4821 ready', '4821'), true);
assert.equal(macroUtils.matchesQuery('Order #4821 ready', '/order #\\d+/i'), true);
assert.equal(macroUtils.matchesQuery('Order #4821 ready', '/^#[0-9]+/'), false);
assert.equal(macroUtils.matchesQuery('anything', '/[unclosed/'), false, 'Invalid regex fails closed');
assert.equal(macroUtils.matchesQuery('anything', '   '), false, 'Empty required query fails closed');
assert.equal(macroUtils.matchesOptionalQuery('anything', ''), true, 'Empty optional query passes');

const legacyFocusApp = macroUtils.normalizeTrigger({type: 'app', match: 'firefox', onFocus: true});
assert.equal(legacyFocusApp.event, 'focus');
assert.equal(legacyFocusApp.onFocus, true);
assert.equal(macroUtils.describeTrigger(legacyFocusApp), 'Focus firefox');
const titleTrigger = macroUtils.normalizeTrigger({type: 'app', event: 'title', match: 'discord', titleMatch: '/\\([1-9]\\)/'});
assert.equal(titleTrigger.onFocus, false);
assert.equal(macroUtils.describeTrigger(titleTrigger), 'Title /\\([1-9]\\)/');

const soundTrigger = macroUtils.normalizeTrigger({
    type: 'sound', mode: 'sample', source: 'both', samplePath: '/tmp/bell.wav',
    trimStart: 1.2, trimEnd: 0.5, minHz: 3000, maxHz: 2000, threshold: 999, cooldownMs: 20
});
assert.equal(soundTrigger.trimStart, 1.2);
assert.equal(soundTrigger.trimEnd, 0, 'Inverted trimEnd resets cleanly');
assert.ok(soundTrigger.maxHz > soundTrigger.minHz, 'Sound frequency range stays ordered');
assert.equal(soundTrigger.threshold, 98);
assert.equal(soundTrigger.cooldownMs, 100);
assert.equal(macroUtils.describeTrigger(soundTrigger), 'Sound: bell.wav');

assert.equal(macroUtils.stepTitle(macroUtils.normalizeStep({type: 'focus', match: 'vesktop'})), 'Focus vesktop');
assert.equal(macroUtils.stepTitle(macroUtils.normalizeStep({type: 'notify', title: 'Bell detected', body: 'Done'})), 'Bell detected');
assert.equal(macroUtils.describeTrigger(macroUtils.normalizeTrigger({type: 'timer', mode: 'daily', at: '7:05'})), 'Daily at 07:05');
assert.equal(macroUtils.normalizeTimeOfDay('25:99', '08:30'), '08:30');

const sampleClients = [{class: 'kitty', title: 'nvim'}, {class: 'steam_app_123', title: 'Elden Ring'}];
assert.equal(macroUtils.conditionMet({appMode: 'focused', appMatch: 'steam_app'}, sampleClients, sampleClients[1]), true);
assert.equal(macroUtils.conditionMet({appMode: 'focused', appMatch: 'steam_app'}, sampleClients, sampleClients[0]), false);
assert.equal(macroUtils.conditionMet({appMode: 'running', appMatch: 'elden'}, sampleClients, sampleClients[0]), true);
assert.equal(macroUtils.conditionMet({appMode: 'not_focused', appMatch: 'kitty'}, sampleClients, sampleClients[1]), true);

const firedEvents = [];
let fakeNow = 10000;
const eventMacros = [
    macroUtils.normalizeMacro({
        id: 'm_notif', name: 'Notif', enabled: true, cooldownMs: 500,
        condition: {appMode: 'focused', appMatch: 'game'},
        trigger: {type: 'notification', appMatch: 'vesktop', textMatch: '/raid|bell/i', urgency: 'normal'},
        steps: [{type: 'notify', title: 'Ack'}]
    }),
    macroUtils.normalizeMacro({
        id: 'm_clip', name: 'Clip', enabled: true,
        trigger: {type: 'clipboard', match: '/^https:\\/\\//'},
        steps: [{type: 'key', keys: 'Return'}]
    }),
    macroUtils.normalizeMacro({
        id: 'm_title', name: 'Title', enabled: true,
        trigger: {type: 'app', event: 'title', match: 'firefox', titleMatch: 'Queue Ready'},
        steps: [{type: 'focus', match: 'firefox'}]
    }),
    macroUtils.normalizeMacro({
        id: 'm_daily', name: 'Daily', enabled: true,
        trigger: {type: 'timer', mode: 'daily', at: '14:30'},
        steps: [{type: 'key', keys: 'F5'}]
    }),
    macroUtils.normalizeMacro({
        id: 'm_snd', name: 'Bell', enabled: true,
        trigger: {type: 'sound', mode: 'sample', source: 'desktop', samplePath: '/tmp/bell.wav', threshold: 72},
        steps: [{type: 'click', button: 'left', x: 100, y: 200}]
    })
];
const eventRoot = {
    enabled: true, playing: false, activeId: '', lastFiredAt: {}, lastTriggerInfo: {},
    dailyFiredStamp: {}, clientSnapshots: {}, clientsInitialized: false, lastFocusedAddress: '',
    maxClipboardId: -1, clipboardInitialized: false,
    list: () => eventMacros,
    findMacro: id => eventMacros.find(m => m.id === id) || null,
    run(id, urgent) { firedEvents.push({id, urgent}); },
    stop() { firedEvents.push({stop: true}); }
};
const eventCtx = {
    root: eventRoot,
    MacroUtils: macroUtils,
    Config: {initialLoadComplete: true},
    Compositor: {clients: {values: [{address: '0x1', class: 'game', title: 'Arena', fullscreen: false}]}, focusedClient: {address: '0x1', class: 'game', title: 'Arena'}},
    ClipboardService: {items: [{id: '10', preview: 'https://old.example', isImage: false}]},
    Date: class extends Date {
        constructor(...args) { super(...(args.length ? args : [fakeNow])); }
        static now() { return fakeNow; }
    },
    console
};
serviceFunctions('MacroService.qml', [
    '_guardsPass', '_recordFire', '_fireTrigger', 'triggerHotkey',
    '_snapshotClient', '_syncAppClients', '_fireAppEvent', '_checkClientEvents',
    '_handleNotification', '_handleClipboardUpdate', '_checkDailyTimers',
    '_soundRuleFromMacro', '_buildSoundConfig', '_pixelRuleFromMacro', '_buildPixelConfig'
], eventCtx);

eventCtx._handleNotification({appName: 'Pangu Macros', summary: 'Bell raid', body: '', urgency: 2});
assert.equal(firedEvents.length, 0, 'Internal macro notifications must never self-trigger');
eventCtx._handleNotification({appName: 'vesktop', summary: 'Bell check', body: 'join now', urgency: 1});
assert.equal(firedEvents.length, 1 && firedEvents[0].id === 'm_notif' ? 1 : 0, 1);
eventCtx._handleNotification({appName: 'vesktop', summary: 'Bell check 2', body: '', urgency: 1});
assert.equal(firedEvents.length, 1, 'Macro cooldown suppresses rapid duplicate triggers');
fakeNow += 600;
eventCtx.Compositor.focusedClient = {address: '0x2', class: 'kitty', title: 'shell'};
eventCtx._handleNotification({appName: 'vesktop', summary: 'Bell check 3', body: '', urgency: 1});
assert.equal(firedEvents.length, 1, 'Focused-window guard blocks trigger when another app is focused');
eventRoot.playing = true;
eventRoot.activeId = 'm_notif';
eventCtx.triggerHotkey('m_notif');
assert.deepEqual(firedEvents.at(-1), {stop: true}, 'Hotkey still stops active playback even if guard no longer matches');
eventRoot.playing = false;
eventRoot.activeId = '';

eventCtx._handleClipboardUpdate();
assert.equal(firedEvents.length, 2, 'Initial clipboard history snapshot must not fire triggers');
eventCtx.ClipboardService.items = [
    {id: '12', preview: 'https://pangu.example', fullContent: 'https://pangu.example', isImage: false},
    {id: '10', preview: 'https://old.example', isImage: false}
];
eventCtx._handleClipboardUpdate();
assert.equal(firedEvents.at(-1).id, 'm_clip');

eventCtx._syncAppClients();
eventCtx.Compositor.clients.values = [
    {address: '0x1', class: 'game', title: 'Arena', fullscreen: false},
    {address: '0x9', class: 'firefox', title: 'Lobby', fullscreen: false}
];
eventCtx._checkClientEvents();
assert.equal(firedEvents.length, 3);
eventCtx.Compositor.clients.values[1].title = 'Queue Ready - Match 1';
eventCtx._checkClientEvents();
assert.equal(firedEvents.at(-1).id, 'm_title');
const countAfterTitle = firedEvents.length;
eventCtx.Compositor.clients.values[1].title = 'Queue Ready - Match 2';
eventCtx._checkClientEvents();
assert.equal(firedEvents.length, countAfterTitle, 'Staying in a matching title does not spam-fire');

const at1430 = new Date(2026, 10, 12, 14, 30, 5);
eventCtx._checkDailyTimers(at1430);
eventCtx._checkDailyTimers(new Date(2026, 10, 12, 14, 30, 40));
assert.equal(firedEvents.filter(e => e.id === 'm_daily').length, 1, 'Daily schedule fires once per day');

const disabledDraft = Object.assign({}, eventMacros[4], {enabled: false, trigger: Object.assign({}, eventMacros[4].trigger, {threshold: 64})});
const sndCfg = eventCtx._buildSoundConfig(eventMacros, true, disabledDraft, true);
assert.equal(sndCfg.rules.length, 1);
assert.equal(sndCfg.rules[0].threshold, 64, 'Open editor draft overrides live sound telemetry parameters');
assert.equal(sndCfg.rules[0].telemetryOnly, true, 'Disabled draft streams telemetry without firing');

assert.equal(macroUtils.normalizeHexColor('#f3a'), '#FF33AA');
assert.equal(macroUtils.normalizeHexColor('12abef'), '#12ABEF');
assert.equal(macroUtils.normalizeHexColor('nothex'), '');
const pxTrig = macroUtils.normalizeTrigger({
    type: 'pixel', targetMode: 'area', watchMode: 'color',
    x: 1400, y: -1200, width: 80, height: 40,
    colors: ['#f3a', '#FF33AA', '34c759', 'invalid'],
    colorLogic: 'all', colorTolerance: 99, areaThreshold: 25,
    fireOnEdge: false, minHoldMs: 120, intervalMs: 20, cooldownMs: 50
});
assert.equal(pxTrig.y, -1200, 'Negative multi-monitor coordinates are preserved');
assert.deepEqual(Array.from(pxTrig.colors), ['#FF33AA', '#34C759']);
assert.equal(pxTrig.colorTolerance, 50);
assert.equal(pxTrig.intervalMs, 50);
assert.equal(pxTrig.cooldownMs, 100);
assert.equal(pxTrig.fireOnEdge, false);
assert.equal(macroUtils.describeTrigger(pxTrig), 'Area 80×40 (all 2 colors)');
assert.equal(macroUtils.describeTrigger(macroUtils.normalizeTrigger({
    type: 'pixel', targetMode: 'pixel', watchMode: 'change', x: 50, y: 60, changeThreshold: 18
})), 'Pixel 50,60 Δ≥18%');

const unconfiguredPixelMacro = macroUtils.normalizeMacro({
    id: 'm_px_empty', name: 'Empty Px', enabled: true,
    trigger: {type: 'pixel', targetMode: 'pixel', watchMode: 'color', x: 10, y: 20, colors: []}
});
assert.equal(eventCtx._buildPixelConfig([unconfiguredPixelMacro], true, null, false).rules.length, 0,
    'Color pixel triggers without target colors stay idle when editor is closed');
const livePxCfg = eventCtx._buildPixelConfig([unconfiguredPixelMacro], true, unconfiguredPixelMacro, true);
assert.equal(livePxCfg.rules.length, 1, 'Open editor streams live swatch telemetry even before colors are picked');
assert.equal(livePxCfg.rules[0].telemetryOnly, false);
console.log('Event scripting triggers, guards, cooldowns, loop prevention and live sound/pixel config tests passed');

assert.equal(macroUtils.sampleDelayMs({type: 'delay', ms: 350}), 350, 'Legacy fixed delay returns exact ms');
assert.equal(macroUtils.stepTitle(macroUtils.normalizeStep({type: 'delay', ms: 350})), '350 ms wait');
const rangeStep = macroUtils.normalizeStep({type: 'delay', mode: 'range', ms: 800, maxMs: 300});
assert.equal(macroUtils.stepTitle(rangeStep), '300–800 ms wait', 'Range title orders swapped bounds');
assert.equal(macroUtils.sampleDelayMs(rangeStep, () => 0), 300);
assert.equal(macroUtils.sampleDelayMs(rangeStep, () => 0.999999), 800);

const bellStep = macroUtils.normalizeStep({type: 'delay', mode: 'gaussian', ms: 500, stdDevMs: 80});
assert.equal(macroUtils.stepTitle(bellStep), '500 ± 80 ms bell wait');
assert.deepEqual({...macroUtils.delayBounds(bellStep)}, {min: 260, max: 740});
assert.ok(Number.isFinite(macroUtils.sampleDelayMs(bellStep, () => 0)), 'u1=0 does not produce Infinity/NaN');
assert.equal(macroUtils.delayBounds({type: 'delay', mode: 'gaussian', ms: 100, stdDevMs: 50}).min, 10,
    'Wide bell curve near zero keeps a human non-zero floor');

let lcg = 123456789;
const nextRng = () => {
    lcg = (1664525 * lcg + 1013904223) >>> 0;
    return lcg / 4294967296;
};
const bellSamples = Array.from({length: 4000}, () => macroUtils.sampleDelayMs(bellStep, nextRng));
const bellMean = bellSamples.reduce((acc, v) => acc + v, 0) / bellSamples.length;
const bellVar = bellSamples.reduce((acc, v) => acc + (v - bellMean) ** 2, 0) / bellSamples.length;
assert.ok(Math.abs(bellMean - 500) < 4, `Expected bell mean near 500, got ${bellMean}`);
assert.ok(Math.abs(Math.sqrt(bellVar) - 80) < 4, `Expected bell stdDev near 80, got ${Math.sqrt(bellVar)}`);
assert.ok(bellSamples.every(v => v >= 260 && v <= 740), 'All bell samples stay inside ±3σ bounds');
console.log('Fixed, uniform range and Gaussian bell-curve delay sampling tests passed');
