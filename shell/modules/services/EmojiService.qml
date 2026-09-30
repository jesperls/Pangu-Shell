pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.components

Singleton {
    id: root

    property var emojis: []
    property var pending: []
    readonly property var recent: history.ready ? history.data : []

    function normalizeCatalog(value) {
        const result = [];
        if (!value || typeof value !== "object" || Array.isArray(value)) return result;
        for (const [emoji, info] of Object.entries(value)) {
            if (!info || typeof info.name !== "string") continue;
            const slug = typeof info.slug === "string" ? info.slug : "";
            result.push({emoji: emoji, name: info.name, slug: slug,
                group: typeof info.group === "string" ? info.group : "",
                search: info.name + " " + slug, skin_tone_support: info.skin_tone_support === true});
        }
        return result;
    }

    function normalizeRecent(value) {
        const result = [];
        if (!Array.isArray(value)) return result;
        for (const entry of value) {
            if (!entry || typeof entry.emoji !== "string" || !entry.emoji
                || result.some(item => item.emoji === entry.emoji)) continue;
            const name = typeof entry.name === "string" ? entry.name : entry.emoji;
            const slug = typeof entry.slug === "string" ? entry.slug : "";
            result.push({emoji: entry.emoji, name: name, slug: slug,
                group: typeof entry.group === "string" ? entry.group : "",
                search: typeof entry.search === "string" ? entry.search : name + " " + slug,
                skin_tone_support: entry.skin_tone_support === true,
                usage: Number.isFinite(entry.usage) && entry.usage >= 1 ? Math.min(Number.MAX_SAFE_INTEGER, Math.floor(entry.usage)) : 1,
                lastUsed: Number.isFinite(entry.lastUsed) && entry.lastUsed >= 0 ? entry.lastUsed : 0});
        }
        return result.sort((a, b) => b.usage - a.usage || b.lastUsed - a.lastUsed).slice(0, 50);
    }

    function addRecent(list, entry, time) {
        const previous = list.find(item => item.emoji === entry.emoji);
        const next = Object.assign({}, entry, {
            usage: Math.min(Number.MAX_SAFE_INTEGER, (previous ? previous.usage : 0) + 1),
            lastUsed: time
        });
        return list.filter(item => item.emoji !== next.emoji).concat([next])
            .sort((a, b) => b.usage - a.usage || b.lastUsed - a.lastUsed).slice(0, 50);
    }

    function remember(emoji) {
        const entry = normalizeRecent([emoji])[0];
        if (!entry) return;
        const time = Date.now();
        if (!history.ready) {
            pending = pending.concat([{entry: entry, time: time}]);
            return;
        }
        history.data = addRecent(history.data, entry, time);
        history.save();
    }

    function clearRecent() {
        if (!history.ready) {
            pending = pending.concat([{clear: true}]);
            return;
        }
        history.data = [];
        history.save();
    }

    function finishLoad() {
        if (!pending.length) return;
        let next = history.data;
        for (const request of pending)
            next = request.clear ? [] : addRecent(next, request.entry, request.time);
        pending = [];
        history.data = next;
        history.save();
    }

    FileView {
        path: Paths.asset("emojis.json")
        onLoaded: {
            try { root.emojis = root.normalizeCatalog(JSON.parse(text())); }
            catch (error) { console.warn("Unreadable emoji catalog:", error); }
        }
    }

    JsonStore {
        id: history
        filePath: Paths.cachePath("emojis.json")
        normalize: root.normalizeRecent
        onDataLoaded: root.finishLoad()
    }
}
