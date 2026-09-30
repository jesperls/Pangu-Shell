pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: wallpaper

    property string wallpaperDir: wallpaperConfig.adapter.wallPath
    property string fallbackDir: Paths.wallpapersDir
    property var wallpaperPaths: []
    property var subfolderFilters: []
    property var allSubdirs: []
    property int currentIndex: 0
    readonly property string currentWallpaper: initialLoadCompleted && currentIndex >= 0 && currentIndex < wallpaperPaths.length ? wallpaperPaths[currentIndex] : ""
    property bool initialLoadCompleted: false
    onInitialLoadCompletedChanged: {
        if (initialLoadCompleted && currentWallpaper) {
            generateLockscreenFrame(currentWallpaper);
            runMatugenForCurrentWallpaper();
        }
    }
    readonly property bool dynamicColors: Config.theme.dynamicColors ?? true
    onDynamicColorsChanged: if (dynamicColors) runMatugenForCurrentWallpaper()
    property bool usingFallback: false
    property bool _wallpaperDirInitialized: false
    readonly property string currentMatugenScheme: wallpaperConfig.adapter.matugenScheme
    property var perScreenWallpapers: wallpaperConfig.adapter.perScreenWallpapers || {}
    property alias tintEnabled: wallpaperAdapter.tintEnabled
    property int thumbnailsVersion: 0
    property int lockscreenVersion: 0
    property string pendingLockscreenFrame: ""

    property var scannedPaths: []  // regular files from wallPath
    property var wePaths: []  // Wallpaper Engine wallpaper dirs
    property var weWallpapers: ({})  // dir -> cached static preview jpg
    property var weTitles: ({})  // dir -> title from project.json
    property string wallpaperEngineDir: wallpaperConfig.adapter.wallpaperEnginePath || (Paths.home + "/.local/share/Steam/steamapps/workshop/content/431960")
    property string weScriptPath: Paths.script("wallpaperengine.sh")
    property bool _regularScanDone: false
    property bool _weScanDone: false

    function mergeWallpaperLists() {
        var merged = scannedPaths.concat(wePaths);
        if (JSON.stringify(merged) !== JSON.stringify(wallpaperPaths)) {
            console.log("Wallpaper list updated:", scannedPaths.length, "files +", wePaths.length, "Wallpaper Engine");
            wallpaperPaths = merged;
        }

        if (wallpaperPaths.length === 0 || !_regularScanDone || !_weScanDone)
            return;

        if (wallpaperConfig.adapter.currentWall) {
            var savedIndex = wallpaperPaths.indexOf(wallpaperConfig.adapter.currentWall);
            if (savedIndex !== -1) {
                currentIndex = savedIndex;
            } else {
                currentIndex = 0;
                console.log("Saved wallpaper not found, using first");
            }
        } else {
            currentIndex = 0;
        }

        if (!initialLoadCompleted) {
            if (!wallpaperConfig.adapter.currentWall) {
                wallpaperConfig.adapter.currentWall = wallpaperPaths[0];
            }
            initialLoadCompleted = true;
        }
    }

    function scanWallpaperEngine() {
        scanWallpaperEngineProcess.running = true;
    }

    function getDisplayName(path) {
        if (weTitles[path] !== undefined) {
            return weTitles[path];
        }
        return path.split('/').pop();
    }

    property string colorPresetsDir: Paths.configPath("colors")
    property string officialColorPresetsDir: Paths.asset("colors")
    property list<string> colorPresets: []
    property alias activeColorPreset: wallpaperAdapter.activeColorPreset

    property bool isLightMode: Config.theme.lightMode
    onIsLightModeChanged: {
        if (activeColorPreset) {
            applyColorPreset();
        } else {
            runMatugenForCurrentWallpaper(true);
        }
    }

    onActiveColorPresetChanged: {
        if (activeColorPreset) {
            applyColorPreset();
        } else {
            runMatugenForCurrentWallpaper(true);
        }
    }

    function scanColorPresets() {
        scanPresetsProcess.running = true;
    }

    function applyColorPreset() {
        if (!activeColorPreset)
            return;

        var mode = Config.theme.lightMode ? "light.json" : "dark.json";

        var officialFile = officialColorPresetsDir + "/" + activeColorPreset + "/" + mode;
        var userFile = colorPresetsDir + "/" + activeColorPreset + "/" + mode;
        var dest = Paths.cachePath("colors.json");

        requestPalette(["bash", "-c", 'set -e; source=$1; [ -f "$source" ] || source=$2; tmp=$(mktemp "$3.XXXXXX"); trap \'rm -f "$tmp"\' EXIT; cp -- "$source" "$tmp"; mv -- "$tmp" "$3"', "pangu-preset", officialFile, userFile, dest]);
    }

    function setColorPreset(name) {
        wallpaperConfig.adapter.activeColorPreset = name;
    }

    function getFileType(path) {
        if (weWallpapers[path] !== undefined) {
            return 'wallpaperengine';
        }
        var extension = path.toLowerCase().split('.').pop();
        if (['jpg', 'jpeg', 'png', 'webp', 'tif', 'tiff', 'bmp'].includes(extension)) {
            return 'image';
        } else if (['gif'].includes(extension)) {
            return 'gif';
        } else if (['mp4', 'webm', 'mov', 'avi', 'mkv'].includes(extension)) {
            return 'video';
        }
        return 'unknown';
    }

    function getThumbnailPath(filePath) {
        if (getFileType(filePath) === 'wallpaperengine') {
            return weWallpapers[filePath];
        }

        var basePath = wallpaperDir.endsWith("/") ? wallpaperDir : wallpaperDir + "/";
        var relativePath = filePath.replace(basePath, "");

        var pathParts = relativePath.split('/');
        var fileName = pathParts.pop();
        var thumbnailName = fileName + ".jpg";
        var relativeDir = pathParts.join('/');

        var thumbnailPath = Paths.cachePath("thumbnails/" + Qt.md5(wallpaperDir.replace(/\/+$/, "") || "/") + "/" + relativeDir + "/" + thumbnailName);
        return thumbnailPath;
    }

    function getColorSource(filePath) {
        var fileType = getFileType(filePath);

        if (fileType === 'video' || fileType === 'wallpaperengine') {
            return getThumbnailPath(filePath);
        }

        return filePath;
    }

    function getLockscreenFramePath(filePath) {
        if (!filePath) {
            return "";
        }

        var fileType = getFileType(filePath);

        if (fileType === 'image') {
            return filePath;
        }

        if (fileType === 'wallpaperengine') {
            return weWallpapers[filePath];
        }

        if (fileType === 'video' || fileType === 'gif') {
            var cachePath = Paths.cachePath("lockscreen/" + Qt.md5(filePath) + ".jpg");
            return cachePath;
        }

        return filePath;
    }

    function generateLockscreenFrame(filePath) {
        if (!filePath) {
            console.warn("generateLockscreenFrame: empty filePath");
            return;
        }

        if (getFileType(filePath) === 'wallpaperengine') {
            return;
        }

        if (lockscreenWallpaperScript.running) {
            pendingLockscreenFrame = filePath;
            return;
        }
        console.log("Generating lockscreen frame for:", filePath);

        var scriptPath = Paths.script("lockwall.py");
        var dataPath = Paths.cacheDir;

        lockscreenWallpaperScript.command = ["python3", scriptPath, filePath, dataPath];

        lockscreenWallpaperScript.running = true;
    }

    function getSubfolderFromPath(filePath) {
        if (getFileType(filePath) === 'wallpaperengine') {
            return "";
        }
        var basePath = wallpaperDir.endsWith("/") ? wallpaperDir : wallpaperDir + "/";
        var relativePath = filePath.replace(basePath, "");
        var parts = relativePath.split("/");
        if (parts.length > 1) {
            return parts[0];
        }
        return "";
    }

    function setWallpaperDirectory(path) {
        wallpaperAdapter.wallPath = path.trim() || fallbackDir;
    }

    function scanSubfolders() {
        if (!wallpaperDir)
            return;
        var cmd = ["find", wallpaperDir, "-mindepth", "1", "-name", ".*", "-prune", "-o", "-type", "d", "-print"];
        scanSubfoldersProcess.command = cmd;
        scanSubfoldersProcess.running = true;
    }

    onWallpaperDirChanged: {
        if (!_wallpaperDirInitialized)
            return;


        console.log("Wallpaper directory changed to:", wallpaperDir);
        usingFallback = false;

        scannedPaths = [];
        wallpaperPaths = wePaths.slice();
        subfolderFilters = [];

        directoryWatcher.path = wallpaperDir;

        var cmd = ["find", wallpaperDir, "-name", ".*", "-prune", "-o", "-type", "f", "(", "-name", "*.jpg", "-o", "-name", "*.jpeg", "-o", "-name", "*.png", "-o", "-name", "*.webp", "-o", "-name", "*.tif", "-o", "-name", "*.tiff", "-o", "-name", "*.gif", "-o", "-name", "*.mp4", "-o", "-name", "*.webm", "-o", "-name", "*.mov", "-o", "-name", "*.avi", "-o", "-name", "*.mkv", ")", "-print"];
        scanWallpapers.command = cmd;
        scanWallpapers.running = true;

        scanSubfolders();

        if (delayedThumbnailGen.running)
            delayedThumbnailGen.restart();
        else
            delayedThumbnailGen.start();
    }

    function setWallpaper(path, targetScreen = null) {

        console.log("setWallpaper called with:", path, "for screen:", targetScreen);
        initialLoadCompleted = true;
        var pathIndex = wallpaperPaths.indexOf(path);
        if (pathIndex !== -1) {
            if (targetScreen) {
                let perScreen = Object.assign({}, wallpaperConfig.adapter.perScreenWallpapers || {});
                perScreen[targetScreen] = path;
                wallpaperConfig.adapter.perScreenWallpapers = perScreen;

                const isPrimary = targetScreen === Quickshell.screens[0]?.name;

                if (isPrimary || !wallpaperConfig.adapter.currentWall) {
                    currentIndex = pathIndex;
                    wallpaperConfig.adapter.currentWall = path;

                    runMatugenForCurrentWallpaper();
                }
            } else {
                currentIndex = pathIndex;
                wallpaperConfig.adapter.currentWall = path;

                runMatugenForCurrentWallpaper();
            }
            generateLockscreenFrame(path);
        } else {
            console.warn("Wallpaper path not found in current list:", path);
        }
    }

    function clearPerScreenWallpaper(targetScreen) {

        console.log("Clearing per-screen wallpaper for:", targetScreen);
        let perScreen = Object.assign({}, wallpaperConfig.adapter.perScreenWallpapers || {});
        if (perScreen[targetScreen]) {
            delete perScreen[targetScreen];
            wallpaperConfig.adapter.perScreenWallpapers = perScreen;
        }
    }

    function nextWallpaper() {

        if (wallpaperPaths.length === 0)
            return;
        initialLoadCompleted = true;
        currentIndex = (currentIndex + 1) % wallpaperPaths.length;

        wallpaperConfig.adapter.currentWall = wallpaperPaths[currentIndex];
        runMatugenForCurrentWallpaper();
        generateLockscreenFrame(wallpaperPaths[currentIndex]);
    }

    function previousWallpaper() {

        if (wallpaperPaths.length === 0)
            return;
        initialLoadCompleted = true;
        currentIndex = currentIndex === 0 ? wallpaperPaths.length - 1 : currentIndex - 1;

        wallpaperConfig.adapter.currentWall = wallpaperPaths[currentIndex];
        runMatugenForCurrentWallpaper();
        generateLockscreenFrame(wallpaperPaths[currentIndex]);
    }

    function setWallpaperByIndex(index) {

        if (index >= 0 && index < wallpaperPaths.length) {
            initialLoadCompleted = true;
            currentIndex = index;

            wallpaperConfig.adapter.currentWall = wallpaperPaths[currentIndex];
            runMatugenForCurrentWallpaper();
            generateLockscreenFrame(wallpaperPaths[currentIndex]);
        }
    }

    function setMatugenScheme(scheme) {
        wallpaperConfig.adapter.matugenScheme = scheme;

        if (wallpaperConfig.adapter.activeColorPreset) {
            console.log("Switching to Matugen scheme, clearing preset");
            wallpaperConfig.adapter.activeColorPreset = "";
        } else {
            runMatugenForCurrentWallpaper(true);
        }
    }

    function runMatugenForCurrentWallpaper(force) {
        if (activeColorPreset) {
            console.log("Skipping Matugen because color preset is active:", activeColorPreset);
            return;
        }

        if (!force && !(Config.theme.dynamicColors ?? true)) {
            console.log("Skipping Matugen because dynamic colors are disabled");
            return;
        }

        if (currentWallpaper && initialLoadCompleted) {
            console.log("Running Matugen for current wallpaper:", currentWallpaper);

            var fileType = getFileType(currentWallpaper);
            var matugenSource = getColorSource(currentWallpaper);

            console.log("Using source for matugen:", matugenSource, "(type:", fileType + ")");

            var command = ["matugen", "image", matugenSource, "--source-color-index", "0", "-c", Paths.asset("matugen/config.toml"), "-t", wallpaperConfig.adapter.matugenScheme];
            command.push("-m", Config.theme.lightMode ? "light" : "dark");
            requestPalette(command);
        }
    }

    signal syncVideo()
    function requestVideoSync() { videoSyncTimer.restart(); }
    Timer {
        id: videoSyncTimer
        interval: 1200
        onTriggered: wallpaper.syncVideo()
    }

    Component.onCompleted: {
        scanColorPresets();
        scanWallpaperEngine();
        presetsWatcher.reload();
        wallpaperConfig.reload();

        Qt.callLater(function () {
            if (currentWallpaper) {
                generateLockscreenFrame(currentWallpaper);
            }
        });
    }

    ConfigFile {
        id: wallpaperConfig
        name: "wallpapers"
        pathOverride: Paths.cachePath("wallpapers.json")

        adapter: JsonAdapter {
            id: wallpaperAdapter
            property string currentWall: ""
            property string wallPath: ""
            property string wallpaperEnginePath: ""
            property string matugenScheme: "scheme-tonal-spot"
            property string activeColorPreset: ""
            property bool tintEnabled: false
            property var perScreenWallpapers: ({})

            onCurrentWallChanged: {
                if (!wallpaper._wallpaperDirInitialized)
                    return;

                if (currentWall && currentWall !== wallpaper.currentWallpaper) {
                    if (wallpaper.wallpaperPaths.length === 0) {
                        return;
                    }

                    var pathIndex = wallpaper.wallpaperPaths.indexOf(currentWall);
                    if (pathIndex !== -1) {
                        wallpaper.currentIndex = pathIndex;
                        if (!wallpaper.initialLoadCompleted) {
                            wallpaper.initialLoadCompleted = true;
                        }
                        wallpaper.runMatugenForCurrentWallpaper();
                    } else {
                        console.warn("Saved wallpaper not found in current list:", currentWall);
                    }
                }
            }

            onWallPathChanged: {
                if (wallPath) {
                    console.log("Config wallPath updated:", wallPath);

                    if (!wallpaper._wallpaperDirInitialized) {
                        wallpaper._wallpaperDirInitialized = true;

                        directoryWatcher.path = wallPath;
                        directoryWatcher.reload();

                        var cmd = ["find", wallPath, "-name", ".*", "-prune", "-o", "-type", "f", "(", "-name", "*.jpg", "-o", "-name", "*.jpeg", "-o", "-name", "*.png", "-o", "-name", "*.webp", "-o", "-name", "*.tif", "-o", "-name", "*.tiff", "-o", "-name", "*.gif", "-o", "-name", "*.mp4", "-o", "-name", "*.webm", "-o", "-name", "*.mov", "-o", "-name", "*.avi", "-o", "-name", "*.mkv", ")", "-print"];
                        scanWallpapers.command = cmd;
                        scanWallpapers.running = true;
                        wallpaper.scanSubfolders();

                        delayedThumbnailGen.start();
                    }
                }
            }
        }
    }

    Connections {
        target: wallpaperConfig
        function onReadyChanged() {
            if (wallpaperConfig.ready && !wallpaperAdapter.wallPath)
                wallpaperAdapter.wallPath = wallpaper.fallbackDir;
        }
    }

    property var pendingPalette: []

    function requestPalette(command) {
        pendingPalette = command;
        startPalette();
    }

    function startPalette() {
        if (paletteProcess.running || pendingPalette.length === 0) return;
        paletteProcess.command = pendingPalette;
        pendingPalette = [];
        paletteProcess.running = true;
    }

    Process {
        id: paletteProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn("Palette generator:", text.trim())
        }
        onExited: code => {
            if (code !== 0) console.warn("Palette generation failed:", code);
            Qt.callLater(wallpaper.startPalette);
        }
    }

    Process {
        id: thumbnailGeneratorScript
        running: false
        command: ["python3", Paths.script("thumbgen.py"), Paths.cachePath("wallpapers.json"), Paths.cacheDir, fallbackDir]

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.log("Thumbnail Generator:", text);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Thumbnail Generator Error:", text);
                }
            }
        }

        onExited: function (exitCode) {
            if (exitCode === 0) {
                console.log("✅ Video thumbnails generated successfully");
                thumbnailsVersion++;
                if (getFileType(currentWallpaper) === "video") runMatugenForCurrentWallpaper();
            } else {
                console.warn("⚠️ Thumbnail generation failed with code:", exitCode);
            }
        }
    }

    Timer {
        id: delayedThumbnailGen
        interval: 2000
        repeat: false
        onTriggered: thumbnailGeneratorScript.running = true
    }

    Process {
        id: lockscreenWallpaperScript
        running: false
        command: []

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.log("Lockscreen Wallpaper Generator:", text);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Lockscreen Wallpaper Generator Error:", text);
                }
            }
        }

        onExited: function (exitCode) {
            if (pendingLockscreenFrame) {
                const next = pendingLockscreenFrame;
                pendingLockscreenFrame = "";
                Qt.callLater(() => generateLockscreenFrame(next));
            }
            if (exitCode === 0) {
                lockscreenVersion++;
                console.log("✅ Lockscreen wallpaper ready");
            } else {
                console.warn("⚠️ Lockscreen wallpaper generation failed with code:", exitCode);
            }
        }
    }

    Process {
        id: scanSubfoldersProcess
        running: false
        command: wallpaperDir ? ["find", wallpaperDir, "-mindepth", "1", "-name", ".*", "-prune", "-o", "-type", "d", "-print"] : []

        stdout: StdioCollector {
            onStreamFinished: {
                console.log("scanSubfolders stdout:", text);
                var rawPaths = text.trim().split("\n").filter(function (f) {
                    return f.length > 0;
                });

                allSubdirs = rawPaths;

                var basePath = wallpaperDir.endsWith("/") ? wallpaperDir : wallpaperDir + "/";

                var topLevelFolders = rawPaths.filter(function (path) {
                    var relative = path.replace(basePath, "");
                    return relative.indexOf("/") === -1;
                }).map(function (path) {
                    return path.split("/").pop();
                }).filter(function (name) {
                    return name.length > 0 && !name.startsWith(".");
                });

                topLevelFolders.sort();
                subfolderFilters = topLevelFolders;
                console.log("Updated subfolderFilters:", subfolderFilters);
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Error scanning subfolders:", text);
                }
            }
        }

        onRunningChanged: {
            if (running) {
                console.log("Starting scanSubfolders for directory:", wallpaperDir);
            } else {
                console.log("Finished scanSubfolders");
            }
        }
    }

    FileView {
        id: directoryWatcher
        path: wallpaperDir
        watchChanges: true
        printErrors: false

        onFileChanged: {
            if (wallpaperDir === "")
                return;
            console.log("Wallpaper directory changed, rescanning...");
            scanWallpapers.running = true;
            scanSubfoldersProcess.running = true;
            if (delayedThumbnailGen.running)
                delayedThumbnailGen.restart();
            else
                delayedThumbnailGen.start();
        }

    }

    Instantiator {
        model: allSubdirs

        delegate: FileView {
            path: modelData
            watchChanges: true
            printErrors: false
            onFileChanged: {
                console.log("Subdirectory content changed (" + path + "), rescanning...");
                scanWallpapers.running = true;
                scanSubfoldersProcess.running = true;

                if (delayedThumbnailGen.running)
                    delayedThumbnailGen.restart();
                else
                    delayedThumbnailGen.start();
            }
        }
    }

    FileView {
        id: presetsWatcher
        path: colorPresetsDir
        watchChanges: true
        printErrors: false

        onFileChanged: {
            console.log("User color presets directory changed, rescanning...");
            scanPresetsProcess.running = true;
        }
    }

    Process {
        id: scanWallpapers
        running: false
        command: wallpaperDir ? ["find", wallpaperDir, "-name", ".*", "-prune", "-o", "-type", "f", "(", "-name", "*.jpg", "-o", "-name", "*.jpeg", "-o", "-name", "*.png", "-o", "-name", "*.webp", "-o", "-name", "*.tif", "-o", "-name", "*.tiff", "-o", "-name", "*.gif", "-o", "-name", "*.mp4", "-o", "-name", "*.webm", "-o", "-name", "*.mov", "-o", "-name", "*.avi", "-o", "-name", "*.mkv", ")", "-print"] : []

        onRunningChanged: {
            if (running && wallpaperDir === "") {
                console.log("Blocking scanWallpapers because wallpaperDir is empty");
                running = false;
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                var files = text.trim().split("\n").filter(function (f) {
                    return f.length > 0;
                });
                if (files.length === 0) {
                    console.log("No wallpapers found in main directory, using fallback");
                    usingFallback = true;
                    scanFallback.running = true;
                } else {
                    usingFallback = false;
                    var newFiles = files.sort();
                    if (JSON.stringify(newFiles) !== JSON.stringify(scannedPaths)) {
                        console.log("Wallpaper directory updated. Found", newFiles.length, "images");
                        scannedPaths = newFiles;

                        if (delayedThumbnailGen.running)
                            delayedThumbnailGen.restart();
                        else
                            delayedThumbnailGen.start();
                    }
                    _regularScanDone = true;
                    mergeWallpaperLists();
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Error scanning wallpaper directory:", text);
                    if (wallpaperPaths.length === 0 && wallpaperDir !== "") {
                        console.log("Directory scan failed for " + wallpaperDir + ", using fallback");
                        usingFallback = true;
                        scanFallback.running = true;
                    }
                }
            }
        }
    }

    Process {
        id: scanWallpaperEngineProcess
        running: false
        command: ["bash", weScriptPath, "scan", wallpaperConfig.adapter.wallpaperEnginePath || ""]

        stdout: StdioCollector {
            onStreamFinished: {
                var map = {};
                var titles = {};
                var dirs = [];
                var lines = text.trim().split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split("|");
                    if (parts.length >= 2 && parts[0].length > 0) {
                        map[parts[0]] = parts[1];
                        titles[parts[0]] = parts.length > 2 && parts[2].length > 0 ? parts[2] : parts[0].split('/').pop();
                        dirs.push(parts[0]);
                    }
                }
                dirs.sort();
                if (JSON.stringify(dirs) !== JSON.stringify(wePaths) || JSON.stringify(titles) !== JSON.stringify(weTitles)) {
                    console.log("Wallpaper Engine wallpapers found:", dirs.length);
                    weWallpapers = map;
                    weTitles = titles;
                    wePaths = dirs;
                }
                _weScanDone = true;
                mergeWallpaperLists();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Wallpaper Engine scan error:", text);
                }
            }
        }
    }

    FileView {
        id: weDirWatcher
        path: wallpaperEngineDir
        watchChanges: true
        printErrors: false
        onFileChanged: scanWallpaperEngine()
    }

    Process {
        id: scanFallback
        running: false
        command: ["find", fallbackDir, "-name", ".*", "-prune", "-o", "-type", "f", "(", "-name", "*.jpg", "-o", "-name", "*.jpeg", "-o", "-name", "*.png", "-o", "-name", "*.webp", "-o", "-name", "*.tif", "-o", "-name", "*.tiff", "-o", "-name", "*.gif", "-o", "-name", "*.mp4", "-o", "-name", "*.webm", "-o", "-name", "*.mov", "-o", "-name", "*.avi", "-o", "-name", "*.mkv", ")", "-print"]

        stdout: StdioCollector {
            onStreamFinished: {
                var files = text.trim().split("\n").filter(function (f) {
                    return f.length > 0;
                });
                console.log("Using fallback wallpapers. Found", files.length, "images");

                if (usingFallback) {
                    scannedPaths = files.sort();
                    _regularScanDone = true;
                    mergeWallpaperLists();
                }
            }
        }
    }

    Process {
        id: scanPresetsProcess
        running: false
        command: ["find", officialColorPresetsDir, colorPresetsDir, "-mindepth", "1", "-maxdepth", "1", "-type", "d"]

        stdout: StdioCollector {
            onStreamFinished: {
                console.log("Scan Presets Output:", text);
                var rawLines = text.trim().split("\n");
                var uniqueNames = [];
                for (var i = 0; i < rawLines.length; i++) {
                    var line = rawLines[i].trim();
                    if (line.length === 0)
                        continue;
                    var name = line.split('/').pop();
                    if (uniqueNames.indexOf(name) === -1) {
                        uniqueNames.push(name);
                    }
                }
                uniqueNames.sort();
                console.log("Found color presets:", uniqueNames);
                colorPresets = uniqueNames;
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
            }
        }
    }

}
