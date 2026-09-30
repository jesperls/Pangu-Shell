import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.modules.theme
import qs.config
import "MpvShaderGenerator.js" as ShaderGenerator

PanelWindow {
    id: wallpaper

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "pangu:wallpaper"
    exclusionMode: ExclusionMode.Ignore

    color: "transparent"

    readonly property string currentScreenName: screen ? screen.name : ""
    readonly property string effectiveWallpaper: WallpaperService.perScreenWallpapers[currentScreenName] || WallpaperService.currentWallpaper
    readonly property bool tintEnabled: WallpaperService.tintEnabled
    readonly property string weScriptPath: WallpaperService.weScriptPath

    function getFileType(path) { return WallpaperService.getFileType(path); }
    function requestVideoSync() { WallpaperService.requestVideoSync(); }

    Connections {
        target: WallpaperService
        function onSyncVideo() { mpvIpc.send(wallpaper.mpvSocket, ["set_property", "time-pos", 0], 0); }
    }

    property string mpvShaderPath: ""
    property bool shaderWriting: false
    property string pendingShader: ""
    property int shaderSlot: 0
    readonly property bool usesMpv: ["video", "gif"].includes(getFileType(effectiveWallpaper))

    readonly property var optimizedPalette: ["background", "overBackground", "shadow", "surface", "surfaceBright", "surfaceDim", "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest", "surfaceContainerLow", "surfaceContainerLowest", "primary", "secondary", "tertiary", "red", "lightRed", "green", "lightGreen", "blue", "lightBlue", "yellow", "lightYellow", "cyan", "lightCyan", "magenta", "lightMagenta"]

    property string mpvSocket: Paths.runtimePath("mpv-" + (currentScreenName ? currentScreenName : "ALL") + ".sock")

    function updateMpvRuntime(enable) {
        mpvIpc.send(mpvSocket, ["set_property", "glsl-shaders", enable ? mpvShaderPath : ""], 10);
    }

    function updateMpvShader() {
        if (!usesMpv) {
            return;
        }
        if (!wallpaper.tintEnabled) {
            pendingShader = "";
            updateMpvRuntime(false);
            return;
        }

        var colors = [];
        var firstColorRaw = Colors[optimizedPalette[0]];
        console.log("Generating MPV shader. First palette color (" + optimizedPalette[0] + "):", firstColorRaw);

        for (var i = 0; i < optimizedPalette.length; i++) {
            var rawColor = Colors[optimizedPalette[i]];
            if (rawColor) {
                var c = Qt.darker(rawColor, 1.0);
                if (c && !isNaN(c.r) && !isNaN(c.g) && !isNaN(c.b)) {
                    colors.push({
                        r: c.r,
                        g: c.g,
                        b: c.b
                    });
                }
            }
        }

        if (colors.length === 0) {
            console.warn("MpvShaderGenerator: No valid colors found for palette! Aborting.");
            return;
        }

        pendingShader = ShaderGenerator.generate(colors);
        startShaderWrite();
    }

    function startShaderWrite() {
        if (shaderWriting || !pendingShader)
            return;
        shaderWriting = true;
        shaderSlot = 1 - shaderSlot; // Alternating paths force mpv to reload the shader.
        mpvShaderWriter.path = Paths.runtimePath("mpv-tint-" + (currentScreenName || "ALL") + "-" + shaderSlot + ".glsl");
        var content = pendingShader;
        pendingShader = "";
        mpvShaderWriter.setText(content);
    }

    function finishShaderWrite(saved) {
        shaderWriting = false;
        if (saved && !pendingShader) {
            mpvShaderPath = mpvShaderWriter.path;
            if (usesMpv)
                updateMpvRuntime(tintEnabled);
        }
        Qt.callLater(wallpaper.startShaderWrite); // FileView must finish its saved signal before changing paths.
    }

    Socket {
        id: mpvIpc

        property var queue: []
        property var job: null

        function send(sockPath, cmd, retries) {
            var key = sockPath + ":" + cmd[0] + ":" + cmd[1];
            queue = queue.filter(entry => entry.key !== key);
            if (job && job.key === key)
                job.retries = 0;
            if (ipcRetryTimer.job && ipcRetryTimer.job.key === key) {
                ipcRetryTimer.stop();
                ipcRetryTimer.job = null;
            }
            queue.push({
                key: key,
                path: sockPath,
                data: JSON.stringify({
                    "command": cmd
                }) + "\n",
                retries: retries
            });
            pump();
        }

        function pump() {
            if (connected || job || queue.length === 0)
                return;
            job = queue.shift();
            path = job.path;
            connected = true;
        }

        onConnectionStateChanged: {
            if (connected && job) {
                write(job.data);
                flush();
                job = null;
                connected = false;
            } else if (!connected) {
                Qt.callLater(pump);
            }
        }

        onError: {
            if (job) {
                if (job.retries > 0) {
                    job.retries--;
                    ipcRetryTimer.job = job;
                    ipcRetryTimer.restart();
                } else {
                    console.warn("MPV IPC failed (is mpvpaper running?):", path);
                }
                job = null;
            }
            Qt.callLater(pump);
        }
    }

    Timer {
        id: ipcRetryTimer
        interval: 200
        repeat: false
        property var job: null
        onTriggered: {
            if (job) {
                mpvIpc.queue.push(job);
                job = null;
                mpvIpc.pump();
            }
        }
    }

    FileView {
        id: mpvShaderWriter
        preload: false
        atomicWrites: true
        onSaved: wallpaper.finishShaderWrite(true)
        onSaveFailed: error => {
            console.warn("Failed to write MPV tint shader:", error);
            wallpaper.finishShaderWrite(false);
        }
    }

    Timer {
        id: shaderUpdateDebounce
        interval: 500
        onTriggered: {
            console.log("Shader debounce triggered, updating MPV...");
            updateMpvShader();
        }
    }

    Connections {
        target: Colors
        function onFileChanged() {
            console.log("Colors file changed, scheduling update...");
            shaderUpdateDebounce.restart();
        }
        function onBackgroundChanged() {
            console.log("Colors background changed, scheduling update...");
            shaderUpdateDebounce.restart();
        }
        function onPrimaryChanged() {
            console.log("Colors primary changed, scheduling update...");
            shaderUpdateDebounce.restart();
        }
    }

    Connections {
        target: Config
        function onOledModeChanged() {
            console.log("Config OLED mode changed, scheduling update...");
            shaderUpdateDebounce.restart();
        }
    }

    onTintEnabledChanged: {
        console.log("Tint enabled changed to", tintEnabled);
        updateMpvShader();
    }

    onEffectiveWallpaperChanged: {
        if (usesMpv) {
            shaderUpdateDebounce.restart();
        }
    }

    Rectangle {
        id: background
        anchors.fill: parent
        color: getFileType(wallpaper.effectiveWallpaper) === 'wallpaperengine' ? "transparent" : "black"
        focus: true

        Keys.onLeftPressed: {
            if (WallpaperService.wallpaperPaths.length > 0) {
                WallpaperService.previousWallpaper();
            }
        }

        Keys.onRightPressed: {
            if (WallpaperService.wallpaperPaths.length > 0) {
                WallpaperService.nextWallpaper();
            }
        }

        WallpaperImage {
            id: wallImage
            anchors.fill: parent
            source: wallpaper.effectiveWallpaper
        }
    }

    component WallpaperImage: Item {
        property string source
        property string previousSource

        onSourceChanged: {
            if (previousSource !== "" && source !== previousSource) {
                if (Styling.animDuration > 0) {
                    transitionAnimation.restart();
                }
            }
            previousSource = source;

        }

        SequentialAnimation {
            id: transitionAnimation

            ParallelAnimation {
                NumberAnimation {
                    target: wallImage
                    property: "scale"
                    to: 1.01
                    duration: Styling.animDuration
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: wallImage
                    property: "opacity"
                    to: 0.5
                    duration: Styling.animDuration
                    easing.type: Easing.OutCubic
                }
            }

            ParallelAnimation {
                NumberAnimation {
                    target: wallImage
                    property: "scale"
                    to: 1.0
                    duration: Styling.animDuration
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: wallImage
                    property: "opacity"
                    to: 1.0
                    duration: Styling.animDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        Loader {
            anchors.fill: parent
            sourceComponent: {
                if (!parent.source)
                    return null;

                var fileType = getFileType(parent.source);
                if (fileType === 'image') {
                    return staticImageComponent;
                } else if (fileType === 'gif' || fileType === 'video') {
                    return mpvpaperComponent;
                } else if (fileType === 'wallpaperengine') {
                    return wallpaperEngineComponent;
                }
                return staticImageComponent;  // fallback
            }

            property string sourceFile: parent.source
        }

        Component {
            id: staticImageComponent
            Item {
                id: staticImageRoot
                width: parent.width
                height: parent.height
                property string sourceFile: parent.sourceFile
                property bool tint: wallpaper.tintEnabled

                readonly property var optimizedPalette: ["background", "overBackground", "shadow", "surface", "surfaceBright", "surfaceDim", "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest", "surfaceContainerLow", "surfaceContainerLowest", "primary", "secondary", "tertiary", "red", "lightRed", "green", "lightGreen", "blue", "lightBlue", "yellow", "lightYellow", "cyan", "lightCyan", "magenta", "lightMagenta"]

                Item {
                    id: paletteSourceItem
                    visible: true
                    width: staticImageRoot.optimizedPalette.length
                    height: 1
                    opacity: 0

                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: staticImageRoot.optimizedPalette
                            Rectangle {
                                width: 1
                                height: 1
                                color: Colors[modelData]
                            }
                        }
                    }
                }

                ShaderEffectSource {
                    id: paletteTextureSource
                    sourceItem: paletteSourceItem
                    hideSource: true
                    visible: false
                    smooth: false
                    recursive: false
                }

                Image {
                    mipmap: true
                    id: rawImage
                    anchors.fill: parent
                    source: parent.sourceFile ? "file://" + parent.sourceFile : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    sourceSize.width: wallpaper.width
                    sourceSize.height: wallpaper.height
                    layer.enabled: parent.tint
                    layer.effect: ShaderEffect {
                        property var paletteTexture: paletteTextureSource
                        property real paletteSize: staticImageRoot.optimizedPalette.length
                        property real texWidth: rawImage.width
                        property real texHeight: rawImage.height

                        vertexShader: "palette.vert.qsb"
                        fragmentShader: "palette.frag.qsb"
                    }
                }
            }
        }

        Component {
            id: wallpaperEngineComponent
            Item {
                property string sourceFile: parent.sourceFile

                function reapply() {
                    weApplyProcess.running = false;
                    weApplyDebounce.restart();
                }

                Timer {
                    id: weApplyDebounce
                    interval: 50
                    repeat: false
                    onTriggered: {
                        weApplyProcess.running = !!sourceFile && !!wallpaper.currentScreenName;
                    }
                }

                onSourceFileChanged: {
                    if (sourceFile) {
                        reapply();
                    }
                }

                Component.onCompleted: {
                    if (sourceFile) {
                        reapply();
                    }
                }

                Component.onDestruction: weApplyProcess.running = false

                Process {
                    id: weApplyProcess
                    running: false
                    command: sourceFile && wallpaper.currentScreenName ? ["bash", wallpaper.weScriptPath, "apply", sourceFile, wallpaper.currentScreenName] : []

                    stdout: StdioCollector {}
                    stderr: StdioCollector {
                        onStreamFinished: {
                            if (text.length > 0) {
                                console.warn("wallpaperengine apply error:", text);
                            }
                        }
                    }

                    onExited: function (exitCode) {
                        if (exitCode !== 0) {
                            console.warn("wallpaperengine apply exited with code:", exitCode);
                        }
                    }
                }
            }
        }

        Component {
            id: mpvpaperComponent
            Item {
                property string sourceFile: parent.sourceFile
                property string scriptPath: decodeURIComponent(Qt.resolvedUrl("mpvpaper.sh").toString().replace("file://", ""))

                Timer {
                    id: mpvpaperRestartTimer
                    interval: 100
                    onTriggered: {
                        if (sourceFile) {
                            console.log("Restarting mpvpaper for:", sourceFile);
                            mpvpaperProcess.running = true;
                            wallpaper.requestVideoSync();
                        }
                    }
                }

                onSourceFileChanged: {
                    if (sourceFile) {
                        console.log("Source file changed to:", sourceFile);
                        mpvpaperProcess.running = false;
                        mpvpaperRestartTimer.restart();
                    }
                }

                Component.onCompleted: {
                    if (sourceFile) {
                        console.log("Initial mpvpaper run for:", sourceFile);
                        mpvpaperProcess.running = true;
                        wallpaper.requestVideoSync();
                    }
                }

                Component.onDestruction: mpvpaperProcess.running = false

                Process {
                    id: mpvpaperProcess
                    running: false
                    command: sourceFile && wallpaper.currentScreenName ? ["bash", scriptPath, sourceFile, (wallpaper.tintEnabled ? wallpaper.mpvShaderPath : ""), wallpaper.currentScreenName] : []

                    stdout: StdioCollector {
                        onStreamFinished: {
                            if (text.length > 0) {
                                console.log("mpvpaper output:", text);
                            }
                        }
                    }

                    stderr: StdioCollector {
                        onStreamFinished: {
                            if (text.length > 0) {
                                console.warn("mpvpaper error:", text);
                            }
                        }
                    }

                    onExited: function (exitCode) {
                        console.log("mpvpaper process exited with code:", exitCode);
                    }
                }
            }
        }
    }
}
