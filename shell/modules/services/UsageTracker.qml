pragma Singleton

import QtQuick
import Quickshell
import qs.config
import qs.modules.components

Singleton {
    id: root

    readonly property string usageFilePath: Paths.cachePath("usage.json")
    property var pendingUsage: []
    property bool dataLoaded: false

    signal usageDataReady()
    signal usageChanged()

    readonly property int maxBoostScore: 200
    readonly property int dayInMs: 86400000

    property alias usageData: store.data

    JsonStore {
        id: store
        filePath: root.usageFilePath
        normalize: root.validate
        onDataLoaded: root.finishLoad()
    }

    function validate(data) {
        const entries = Object.create(null);
        const now = Date.now();
        if (data && typeof data === "object" && !Array.isArray(data)) {
            for (const [id, entry] of Object.entries(data)) {
                if (!entry || !Number.isFinite(entry.count) || entry.count < 1 || !Number.isFinite(entry.lastUsed) || entry.lastUsed < 0)
                    continue;
                entries[id] = {
                    count: Math.min(Number.MAX_SAFE_INTEGER, Math.floor(entry.count)),
                    lastUsed: Math.min(now, entry.lastUsed)
                };
            }
        }
        return entries;
    }

    function finishLoad() {
        if (dataLoaded)
            return;
        dataLoaded = true;
        const pending = pendingUsage;
        pendingUsage = [];
        for (const id of pending) recordUsage(id);
        usageDataReady();
    }

    function recordUsage(appId) {
        if (typeof appId !== "string" || !appId) return;
        if (!dataLoaded) {
            pendingUsage = pendingUsage.concat(appId);
            return;
        }
        const previous = Object.prototype.hasOwnProperty.call(usageData, appId) ? usageData[appId] : null;
        const next = Object.assign(Object.create(null), usageData);
        next[appId] = {
            count: Math.min(Number.MAX_SAFE_INTEGER, (previous ? previous.count : 0) + 1),
            lastUsed: Date.now()
        };
        usageData = next;
        if (store.ready) saveTimer.restart();
        usageChanged();
    }

    function getUsageScore(appId) {
        if (!Object.prototype.hasOwnProperty.call(usageData, appId)) return 0;
        const data = usageData[appId];
        const daysSinceLastUse = Math.max(0, (Date.now() - data.lastUsed) / dayInMs);
        return maxBoostScore * Math.exp(-daysSinceLastUse / 7) + Math.log(data.count + 1) * 20;
    }

    Timer {
        id: saveTimer
        interval: 100
        onTriggered: store.save()
    }
}
