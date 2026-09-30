pragma Singleton

import Quickshell

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")

    readonly property string shellDir: Quickshell.shellDir
    readonly property string assetsDir: shellDir + "/assets"
    readonly property string scriptsDir: shellDir + "/scripts"

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (home + "/.cache")
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")

    readonly property string configDir: configHome + "/pangu"
    readonly property string cacheDir: cacheHome + "/pangu"
    readonly property string dataDir: dataHome + "/pangu"

    readonly property string notesDir: dataDir + "-notes"

    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/pangu"

    readonly property string wallpapersDir: Quickshell.env("PANGU_WALLPAPERS") || (home + "/Pictures/Wallpapers")
    readonly property string picturesDir: Quickshell.env("XDG_PICTURES_DIR") || (home + "/Pictures")
    readonly property string videosDir: Quickshell.env("XDG_VIDEOS_DIR") || (home + "/Videos")

    readonly property string avatar: home + "/.face.icon"

    function asset(relative) {
        return assetsDir + "/" + relative;
    }

    function assetUrl(relative) {
        return "file://" + assetsDir + "/" + relative;
    }

    function script(relative) {
        return scriptsDir + "/" + relative;
    }

    function cachePath(relative) {
        return cacheDir + "/" + relative;
    }

    function dataPath(relative) {
        return dataDir + "/" + relative;
    }

    function configPath(relative) {
        return configDir + "/" + relative;
    }

    function runtimePath(relative) {
        return runtimeDir + "/" + relative;
    }
}
