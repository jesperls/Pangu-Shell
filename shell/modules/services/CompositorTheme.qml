pragma Singleton

import QtQuick
import qs.modules.components
import Quickshell
import qs.config
import qs.modules.theme
Singleton {
    id: root

    readonly property string outputPath: Paths.dataPath("hyprland.lua")

    function color(name) {
        const resolved = Colors.resolve(name);
        return typeof resolved === "string" ? Qt.color(resolved) : resolved;
    }

    function format(c) {
        const hex = v => Math.round(v * 255).toString(16).padStart(2, "0");
        const rgb = hex(c.r) + hex(c.g) + hex(c.b);
        return c.a === 1.0 ? `rgb(${rgb})` : `rgba(${rgb}${hex(c.a)})`;
    }

    function opaque(name) {
        const c = color(name);
        return format(Qt.rgba(c.r, c.g, c.b, 1.0));
    }

    function borderSpec(names, angle, fallback) {
        if (!names || names.length === 0)
            return `"${opaque(fallback)}"`;
        if (names.length === 1)
            return `"${opaque(names[0])}"`;
        const list = names.map(n => `"${opaque(n)}"`).join(", ");
        return `{ colors = { ${list} }, angle = ${angle} }`;
    }

    function shadowSpec(name) {
        const c = color(name);
        return format(Qt.rgba(c.r, c.g, c.b, c.a * Config.compositorShadowOpacity));
    }

    readonly property real ignoreAlpha: {
        if (Config.compositor.blurExplicitIgnoreAlpha)
            return Config.compositor.blurIgnoreAlphaValue;
        const bar = Config.theme.srBarBg.opacity;
        const bg = Config.theme.srBg.opacity;
        return bar > 0 ? Math.min(bar, bg) : bg;
    }

    readonly property string lua: {
        const c = Config.compositor;
        const active = c.syncBorderColor ? [Config.compositorBorderColor] : c.activeBorderColor;

        void Colors.background;

        return `hl.config({
    general = {
        gaps_in = ${c.gapsIn},
        gaps_out = ${c.gapsOut},
        border_size = ${Config.compositorBorderSize},
        col = {
            active_border = ${borderSpec(active, c.borderAngle, "primary")},
            inactive_border = ${borderSpec(c.inactiveBorderColor, c.inactiveBorderAngle, "surface")},
        },
    },
    decoration = {
        rounding = ${Config.compositorRounding},
        shadow = {
            enabled = ${c.shadowEnabled},
            range = ${c.shadowRange},
            render_power = ${c.shadowRenderPower},
            sharp = ${c.shadowSharp},
            color = "${shadowSpec(Config.compositorShadowColor)}",
            color_inactive = "${shadowSpec(Config.compositorShadowColorInactive)}",
            offset = "${c.shadowOffset}",
            scale = ${c.shadowScale.toFixed(2)},
        },
        blur = {
            enabled = ${c.blurEnabled},
            size = ${c.blurSize},
            passes = ${c.blurPasses},
            ignore_opacity = ${c.blurIgnoreOpacity},
            new_optimizations = ${c.blurNewOptimizations},
            xray = ${c.blurXray},
            noise = ${c.blurNoise.toFixed(3)},
            contrast = ${c.blurContrast.toFixed(2)},
            brightness = ${c.blurBrightness.toFixed(2)},
            vibrancy = ${c.blurVibrancy.toFixed(4)},
            vibrancy_darkness = ${c.blurVibrancyDarkness.toFixed(2)},
            special = ${c.blurSpecial},
            popups = ${c.blurPopups},
            popups_ignorealpha = ${c.blurPopupsIgnorealpha.toFixed(2)},
            input_methods = ${c.blurInputMethods},
            input_methods_ignorealpha = ${c.blurInputMethodsIgnorealpha.toFixed(2)},
        },
    },
})

hl.layer_rule({
    match = { namespace = "pangu" },
    no_anim = true,
    blur = true,
    blur_popups = true,
    ignore_alpha = ${ignoreAlpha.toFixed(2)},
})

hl.layer_rule({ match = { namespace = "selection" }, no_anim = true }) -- Animations lag behind slurp's drag.
`;
    }

    GeneratedFile {
        id: file
        path: root.outputPath
        onWritten: Compositor.reloadConfig()
    }

    Timer {
        id: debounce
        interval: 100
        onTriggered: file.write(root.lua)
    }

    onLuaChanged: debounce.restart()

    Component.onCompleted: debounce.restart()

    Connections {
        target: Colors
        function onLoaded() {
            debounce.restart();
        }
        function onFileChanged() {
            debounce.restart();
        }
    }
}
