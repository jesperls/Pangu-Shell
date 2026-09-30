pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    readonly property var namedKeys: {
        const map = {};
        const add = (code, name) => {
            if (code !== undefined)
                map[code] = name;
        };
        add(Qt.Key_Return, "Return");
        add(Qt.Key_Enter, "Return");
        add(Qt.Key_Escape, "Escape");
        add(Qt.Key_Tab, "Tab");
        add(Qt.Key_Backtab, "Tab");
        add(Qt.Key_Backspace, "BackSpace");
        add(Qt.Key_Delete, "Delete");
        add(Qt.Key_Insert, "Insert");
        add(Qt.Key_Home, "Home");
        add(Qt.Key_End, "End");
        add(Qt.Key_PageUp, "Prior");
        add(Qt.Key_PageDown, "Next");
        add(Qt.Key_Up, "up");
        add(Qt.Key_Down, "down");
        add(Qt.Key_Left, "left");
        add(Qt.Key_Right, "right");
        add(Qt.Key_Print, "Print");
        add(Qt.Key_Menu, "Menu");
        add(Qt.Key_Pause, "Pause");
        add(Qt.Key_ScrollLock, "Scroll_Lock");
        add(Qt.Key_NumLock, "Num_Lock");
        add(Qt.Key_CapsLock, "Caps_Lock");
        add(Qt.Key_Space, "space");
        add(Qt.Key_Minus, "minus");
        add(Qt.Key_Equal, "equal");
        add(Qt.Key_Comma, "comma");
        add(Qt.Key_Period, "period");
        add(Qt.Key_Slash, "slash");
        add(Qt.Key_Backslash, "backslash");
        add(Qt.Key_Semicolon, "semicolon");
        add(Qt.Key_Apostrophe, "apostrophe");
        add(Qt.Key_QuoteLeft, "grave");
        add(Qt.Key_BracketLeft, "bracketleft");
        add(Qt.Key_BracketRight, "bracketright");
        add(Qt.Key_Plus, "plus");
        add(Qt.Key_Underscore, "underscore");
        add(Qt.Key_sterling, "sterling");
        add(Qt.Key_MediaPlay, "XF86AudioPlay");
        add(Qt.Key_MediaPause, "XF86AudioPause");
        add(Qt.Key_MediaNext, "XF86AudioNext");
        add(Qt.Key_MediaPrevious, "XF86AudioPrev");
        add(Qt.Key_MediaStop, "XF86AudioStop");
        add(Qt.Key_VolumeUp, "XF86AudioRaiseVolume");
        add(Qt.Key_VolumeDown, "XF86AudioLowerVolume");
        add(Qt.Key_VolumeMute, "XF86AudioMute");
        add(Qt.Key_MonBrightnessUp, "XF86MonBrightnessUp");
        add(Qt.Key_MonBrightnessDown, "XF86MonBrightnessDown");
        add(Qt.Key_ScreenSaver, "XF86ScreenSaver");
        add(Qt.Key_Search, "XF86Search");
        return map;
    }

    readonly property var latin1Names: ({
            0xc0: "agrave",
            0xc1: "aacute",
            0xc2: "acircumflex",
            0xc3: "atilde",
            0xc4: "adiaeresis",
            0xc5: "aring",
            0xc6: "ae",
            0xc7: "ccedilla",
            0xc8: "egrave",
            0xc9: "eacute",
            0xca: "ecircumflex",
            0xcb: "ediaeresis",
            0xcc: "igrave",
            0xcd: "iacute",
            0xce: "icircumflex",
            0xcf: "idiaeresis",
            0xd0: "eth",
            0xd1: "ntilde",
            0xd2: "ograve",
            0xd3: "oacute",
            0xd4: "ocircumflex",
            0xd5: "otilde",
            0xd6: "odiaeresis",
            0xd7: "multiply",
            0xd8: "oslash",
            0xd9: "ugrave",
            0xda: "uacute",
            0xdb: "ucircumflex",
            0xdc: "udiaeresis",
            0xdd: "yacute",
            0xde: "thorn",
            0xdf: "ssharp",
            0xe0: "agrave",
            0xe1: "aacute",
            0xe2: "acircumflex",
            0xe3: "atilde",
            0xe4: "adiaeresis",
            0xe5: "aring",
            0xe6: "ae",
            0xe7: "ccedilla",
            0xe8: "egrave",
            0xe9: "eacute",
            0xea: "ecircumflex",
            0xeb: "ediaeresis",
            0xec: "igrave",
            0xed: "iacute",
            0xee: "icircumflex",
            0xef: "idiaeresis",
            0xf0: "eth",
            0xf1: "ntilde",
            0xf2: "ograve",
            0xf3: "oacute",
            0xf4: "ocircumflex",
            0xf5: "otilde",
            0xf6: "odiaeresis",
            0xf7: "division",
            0xf8: "oslash",
            0xf9: "ugrave",
            0xfa: "uacute",
            0xfb: "ucircumflex",
            0xfc: "udiaeresis",
            0xfd: "yacute",
            0xfe: "thorn",
            0xff: "ydiaeresis",
            0x152: "oe",
            0x153: "oe"
        })

    function isModifier(key) {
        return key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Alt
            || key === Qt.Key_Meta || key === Qt.Key_AltGr;
    }

    function modifierNames(modifiers) {
        const names = [];
        if (modifiers & Qt.MetaModifier) names.push("SUPER");
        if (modifiers & Qt.ControlModifier) names.push("CTRL");
        if (modifiers & Qt.AltModifier) names.push("ALT");
        if (modifiers & Qt.ShiftModifier) names.push("SHIFT");
        return names;
    }

    function keyName(event) {
        const key = event.key;
        if (key >= Qt.Key_A && key <= Qt.Key_Z)
            return String.fromCharCode(key);
        if (key >= Qt.Key_0 && key <= Qt.Key_9)
            return String.fromCharCode(key);
        if (key >= Qt.Key_F1 && key <= Qt.Key_F35)
            return "F" + (key - Qt.Key_F1 + 1);
        if (root.namedKeys[key] !== undefined)
            return root.namedKeys[key];
        if (root.latin1Names[key] !== undefined)
            return root.latin1Names[key];
        const text = event.text || "";
        if (text.length === 1) {
            const code = text.charCodeAt(0);
            if (code < 0x20 || code === 0x7f)
                return "";
            if (root.latin1Names[code] !== undefined)
                return root.latin1Names[code];
            if (code < 0x80)
                return text;
        }
        return "";
    }

    function comboFromEvent(event) {
        const key = keyName(event);
        if (!key)
            return "";
        return modifierNames(event.modifiers).concat(key).join(" + ");
    }
}
