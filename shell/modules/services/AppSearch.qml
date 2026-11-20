pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services
import qs.config

Singleton {
    id: root

    property var iconCache: ({})
    
    function getCachedIcon(str) {
        if (!str) return "image-missing";
        if (iconCache[str]) return iconCache[str];
        
        const result = guessIcon(str);
        iconCache[str] = result;
        return result;
    }

    function iconExists(iconName) {
        return (Quickshell.iconPath(iconName, true).length > 0) 
            && !iconName.includes("image-missing");
    }

    function validateIcon(iconName) {
        if (!iconName || iconName.length === 0) {
            return "image-missing";
        }
        
        if (iconName.startsWith("/")) {
            const resolvedPath = Quickshell.iconPath(iconName, true);
            if (resolvedPath.length === 0) {
                return "image-missing";
            }
            return iconName;
        }
        
        if (iconExists(iconName)) {
            return iconName;
        }
        
        return "image-missing";
    }

    function getIconFromDesktopEntry(className) {
        if (!className || className.length === 0) return null;

        const normalizedClassName = className.toLowerCase();

        for (let i = 0; i < list.length; i++) {
            const app = list[i];
            if (app.command && app.command.length > 0) {
                const executableLower = app.command[0].toLowerCase();
                if (executableLower === normalizedClassName) {
                    return app.icon || "application-x-executable";
                }
            }
            if (app.name && app.name.toLowerCase() === normalizedClassName) {
                return app.icon || "application-x-executable";
            }
            if (app.keywords && app.keywords.length > 0) {
                for (let j = 0; j < app.keywords.length; j++) {
                    if (app.keywords[j].toLowerCase() === normalizedClassName) {
                        return app.icon || "application-x-executable";
                    }
                }
            }
        }
        return null;
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";

        const desktopIcon = getIconFromDesktopEntry(str);
        if (desktopIcon) return desktopIcon;

        if (substitutions[str])
            return substitutions[str];

        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str) return replacedName;
        }

        if (iconExists(str)) return str;

        const extensionGuess = str.split('.').pop().toLowerCase();
        if (iconExists(extensionGuess)) return extensionGuess;

        const dashedGuess = str.toLowerCase().replace(/\s+/g, "-");
        if (iconExists(dashedGuess)) return dashedGuess;

        return str;
    }

    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
        "zen": "zen-browser",
    })
    property list<var> regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]




    
    readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values)
        .sort((a, b) => a.name.localeCompare(b.name))
    
    property var searchIndex: []
    
    function buildIndex() {
        const newIndex = [];
        for (let i = 0; i < list.length; i++) {
            const app = list[i];
            newIndex.push({
                name: app.name.toLowerCase(),
                command: (app.command && app.command.length > 0) ? app.command.join(' ').toLowerCase() : "",
                executable: (app.command && app.command.length > 0) ? app.command[0].toLowerCase() : "",
                comment: (app.comment || "").toLowerCase(),
                genericName: (app.genericName || "").toLowerCase(),
                keywords: (app.keywords || []).map(k => k.toLowerCase()),
                original: app
            });
        }
        searchIndex = newIndex;
    }
    
    property var allAppsCache: null

    signal resultsChanged()

    function invalidateCache() {
        allAppsCache = null;
        resultsChanged();
    }

    onListChanged: {
        iconCache = {};
        buildIndex();
        invalidateCache();
    }

    Connections {
        target: UsageTracker
        function onUsageDataReady() { root.invalidateCache(); }
        function onUsageChanged() { root.invalidateCache(); }
    }

    Connections {
        target: Config.launcher
        function onSortByUsageChanged() {
            invalidateCache();
        }
    }
    
    Component.onCompleted: {
        buildIndex();
    }
    

    function launchApp(app) {
        if (!app || !app.id)
            return;
        ApplicationLauncher.launchDesktop(app.id, app.name);
    }

    function getAllApps() {
        if (allAppsCache) return allAppsCache;

        const results = [];
        
        for (let i = 0; i < list.length; i++) {
            const app = list[i];
            const usageScore = (Config.launcher.sortByUsage ?? true) ? UsageTracker.getUsageScore(app.id) : 0;
            
            let iconToUse = app.icon || "application-x-executable";
            if (iconCache[iconToUse]) {
                iconToUse = iconCache[iconToUse];
            } else {
                let validated = validateIcon(iconToUse);
                iconCache[iconToUse] = validated;
                iconToUse = validated;
            }

            results.push({
                name: app.name,
                icon: iconToUse,
                id: app.id,
                execString: app.execString,
                comment: app.comment || "",
                categories: app.categories || [],
                runInTerminal: app.runInTerminal || false,
                usageScore: usageScore,
                execute: () => {
                    launchApp(app);
                }
            });
        }
        
        results.sort((a, b) => {
            if (a.usageScore !== b.usageScore) {
                return b.usageScore - a.usageScore;
            }
            return a.name.localeCompare(b.name);
        });
        
        allAppsCache = results;
        return results;
    }
    
    function fuzzyScore(query, target) {
        if (!query || !target) return -1;
        if (target === query) return 120;
        if (target.startsWith(query)) return 95 - Math.min(15, target.length - query.length);
        const subIdx = target.indexOf(query);
        if (subIdx !== -1) {
            const boundary = subIdx === 0 || " -_./".includes(target[subIdx - 1]);
            return (boundary ? 82 : 68) - Math.min(12, subIdx);
        }
        let qi = 0;
        let score = 0;
        let consecutive = 0;
        let acronymHits = 0;
        for (let i = 0; i < target.length && qi < query.length; i++) {
            if (target[i] === query[qi]) {
                const boundary = i === 0 || " -_./".includes(target[i - 1]);
                if (boundary) {
                    score += 14;
                    acronymHits++;
                } else {
                    score += 4;
                }
                consecutive++;
                score += Math.min(consecutive, 4) * 3;
                qi++;
            } else {
                consecutive = 0;
            }
        }
        if (qi !== query.length) return -1;
        if (acronymHits === query.length) score += 20;
        return Math.max(10, Math.min(64, score - Math.min(20, Math.floor((target.length - query.length) / 3))));
    }

    function scoreEntry(entry, searchLower, tokens) {
        let best = 0;
        const nameScore = fuzzyScore(searchLower, entry.name);
        if (nameScore > 0) best = Math.max(best, nameScore);

        if (entry.executable) {
            const execBase = entry.executable.split("/").pop();
            const execScore = fuzzyScore(searchLower, execBase);
            if (execScore > 0) best = Math.max(best, Math.round(execScore * 0.85));
        }
        if (entry.command && entry.command.includes(searchLower)) best = Math.max(best, 42);
        if (entry.genericName) {
            const genScore = fuzzyScore(searchLower, entry.genericName);
            if (genScore > 0) best = Math.max(best, Math.round(genScore * 0.65));
        }
        if (entry.comment && entry.comment.includes(searchLower)) best = Math.max(best, 30);
        for (let j = 0; j < entry.keywords.length; j++) {
            const kwScore = fuzzyScore(searchLower, entry.keywords[j]);
            if (kwScore > 0) best = Math.max(best, Math.round(kwScore * 0.6));
        }

        if (best > 0 || tokens.length <= 1) return best;

        const haystack = [entry.name, entry.executable, entry.genericName, entry.comment, entry.keywords.join(" ")].join(" ");
        let tokenSum = 0;
        for (let t = 0; t < tokens.length; t++) {
            const tok = tokens[t];
            const s = Math.max(
                fuzzyScore(tok, entry.name),
                entry.genericName ? Math.round(fuzzyScore(tok, entry.genericName) * 0.7) : -1,
                haystack.includes(tok) ? 35 : -1
            );
            if (s <= 0) return 0;
            tokenSum += s;
        }
        return Math.round(tokenSum / tokens.length);
    }

    function fuzzyQuery(search) {
        if (!search || search.length === 0) return [];
        
        const searchLower = search.trim().toLowerCase();
        if (searchLower.length === 0) return [];
        const tokens = searchLower.split(/\s+/).filter(t => t.length > 0);
        const results = [];
        
        if (searchIndex.length === 0 && list.length > 0) buildIndex();
        
        for (let i = 0; i < searchIndex.length; i++) {
            const entry = searchIndex[i];
            const score = scoreEntry(entry, searchLower, tokens);
            if (score > 0) {
                const app = entry.original;
                const usageScore = (Config.launcher.sortByUsage ?? true) ? UsageTracker.getUsageScore(app.id) : 0;
                let iconToUse = app.icon || "application-x-executable";
                if (iconCache[iconToUse]) {
                    iconToUse = iconCache[iconToUse];
                } else {
                    let validated = validateIcon(iconToUse);
                    iconCache[iconToUse] = validated;
                    iconToUse = validated;
                }
                
                results.push({
                    name: app.name,
                    icon: iconToUse,
                    score: score,
                    id: app.id,
                    execString: app.execString,
                    comment: app.comment || "",
                    categories: app.categories || [],
                    runInTerminal: app.runInTerminal || false,
                    usageScore: usageScore,
                    execute: () => {
                        launchApp(app);
                    }
                });
            }
        }
        
        results.sort((a, b) => {
            const totalScoreA = a.score + a.usageScore;
            const totalScoreB = b.score + b.usageScore;
            
            if (totalScoreA !== totalScoreB) {
                return totalScoreB - totalScoreA;
            }
            return (a.name || "").localeCompare(b.name || "");
        });
        
        return results.slice(0, 25);
    }
}
