pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.globals
import qs.modules.theme

Singleton {
    id: root

    readonly property var builtinPresets: [
        {
            id: "pangu",
            name: "Pangu",
            description: "The stock layout: floating pill bar on top, centered notch.",
            icon: Icons.cube,
            lightMode: false,
            colorPreset: "",
            theme: {
                roundness: 16,
                enableCorners: true,
                font: "Inter",
                srBarBg: { gradient: [["surfaceDim", 0.0], ["surfaceContainerLow", 1.0]], opacity: 1.0, border: ["surfaceBright", 0] }
            },
            bar: { position: "top", height: 0, pillStyle: "default", clockPosition: "right", launcherPosition: "start", flatButtons: false, showWorkspaces: true, launcherIcon: Icons.cube, launcherIconTint: false, launcherIconSize: 24, use12hFormat: false },
            dock: { enabled: false, theme: "default", position: "bottom" },
            notch: { theme: "default", position: "top", keepHidden: false },
            overview: { enabled: true, layout: "standard", rows: 2, columns: 5 },
            lockscreen: { position: "bottom" },
            compositor: { gapsIn: 2, gapsOut: 4, borderSize: 2, syncRoundness: true }
        }
    ]

    ConfigFile {
        id: presetsFile
        name: "layouts"
        pathOverride: Paths.configPath("layouts.json")

        adapter: JsonAdapter {
            property var presets: []
        }
    }

    readonly property var userPresets: (presetsFile.adapter && presetsFile.adapter.presets) ? presetsFile.adapter.presets : []
    readonly property var presets: builtinPresets.concat(userPresets)

    function isBuiltin(id) {
        for (let i = 0; i < builtinPresets.length; i++) {
            if (builtinPresets[i].id === id)
                return true;
        }
        return false;
    }

    function getPreset(id) {
        return presets.find(p => p.id === id) || null;
    }

    readonly property var _sections: ["theme", "bar", "dock", "notch", "workspaces", "overview", "dashboard", "launcher", "lockscreen", "osd", "compositor"]

    function captureCurrent(name, description) {
        const manager = GlobalStates.wallpaperManager;
        const preset = {
            id: slugify(name),
            name: name,
            description: description || "",
            icon: Icons.cube,
            lightMode: Config.theme.lightMode,
            colorPreset: manager ? (manager.activeColorPreset || "") : ""
        };
        for (const section of _sections)
            preset[section] = Config.snapshot(section);
        return preset;
    }

    function slugify(name) {
        const s = String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
        return s || "layout";
    }

    function saveCurrent(name, description) {
        const cleaned = String(name || "").trim();
        if (!cleaned)
            return "";

        let id = slugify(cleaned);
        if (isBuiltin(id)) {
            let n = 2;
            while (isBuiltin(id + "-" + n) || userPresets.some(p => p.id === id + "-" + n))
                n++;
            id = id + "-" + n;
        }

        const preset = captureCurrent(cleaned, description);
        preset.id = id;

        let list = userPresets.filter(p => p.id !== id);
        list.push(preset);
        presetsFile.adapter.presets = list;
        presetsFile.writeAdapter();
        return id;
    }

    function deletePreset(id) {
        if (isBuiltin(id))
            return false;
        const list = userPresets.filter(p => p.id !== id);
        presetsFile.adapter.presets = list;
        presetsFile.writeAdapter();
        return true;
    }

    function apply(id) {
        const preset = getPreset(id);
        if (!preset) {
            console.warn("LayoutPresets: unknown preset", id);
            return;
        }

        Config.pauseAutoSave = true;

        try {
            for (const section of _sections)
                if (section !== "theme") Config.restore(section, preset[section]);

            if (preset.colorPreset !== undefined) {
                const manager = GlobalStates.wallpaperManager;
                if (manager)
                    manager.setColorPreset(preset.colorPreset);
            }

            Config.restore("theme", preset.theme);

            if (preset.lightMode !== undefined)
                Config.theme.lightMode = preset.lightMode;
        } finally {
            Config.pauseAutoSave = false;
        }

        for (const name of _sections)
            Config.save(name);

        GlobalStates.resetChangeTracking();
    }
}
