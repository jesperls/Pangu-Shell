pragma Singleton
pragma ComponentBehavior: Bound

import QtQml.Models
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.config
import qs.modules.services
import qs.modules.theme

Singleton {
    id: root

    property var trackedPlayer: null

    function isPlayerAllowed(player) {
        if (!player) return false;
        const dbusName = (player.dbusName || "").toLowerCase();
        return Config.bar.enableFirefoxPlayer || !dbusName.includes("firefox");
    }

    property var filteredPlayers: Mpris.players.values.filter(player => root.isPlayerAllowed(player))

    readonly property var activePlayer: filteredPlayers.includes(trackedPlayer) ? trackedPlayer : (filteredPlayers.find(player => player.isPlaying) ?? filteredPlayers[0] ?? null)

    property bool isInitializing: true
    property string cachedDbusName: ""
    property string cachedIdentity: ""

    property bool isPlaying: activePlayer ? activePlayer.isPlaying : false
    property bool canTogglePlaying: activePlayer ? activePlayer.canTogglePlaying : false
    property bool canGoPrevious: activePlayer ? activePlayer.canGoPrevious : false
    property bool canGoNext: activePlayer ? activePlayer.canGoNext : false
    property bool loopSupported: activePlayer ? (activePlayer.loopSupported && activePlayer.canControl) : false
    property var loopState: activePlayer ? activePlayer.loopState : (typeof MprisLoopState !== "undefined" ? MprisLoopState.None : 0)
    property bool shuffleSupported: activePlayer ? (activePlayer.shuffleSupported && activePlayer.canControl) : false
    property bool hasShuffle: activePlayer ? activePlayer.shuffle : false

    function playerBaseName(name) {
        return (name || "").toLowerCase().replace(/\.instance[-_a-z0-9]*$/, "");
    }

    function matchesSavedPlayer(player) {
        if (!player) return false;
        if (root.cachedDbusName && playerBaseName(player.dbusName) === playerBaseName(root.cachedDbusName))
            return true;
        if (root.cachedIdentity && (player.identity || "").toLowerCase() === root.cachedIdentity.toLowerCase())
            return true;
        return false;
    }

    function getPlayerIcon(player) {
        if (!player)
            return Icons.player;
        const dbusName = (player.dbusName || "").toLowerCase();
        const desktopEntry = (player.desktopEntry || "").toLowerCase();
        const identity = (player.identity || "").toLowerCase();
        if (dbusName.includes("spotify") || desktopEntry.includes("spotify") || identity.includes("spotify"))
            return Icons.spotify;
        if (dbusName.includes("chromium") || dbusName.includes("chrome") || desktopEntry.includes("chromium") || desktopEntry.includes("chrome"))
            return Icons.chromium;
        if (dbusName.includes("firefox") || desktopEntry.includes("firefox"))
            return Icons.firefox;
        if (dbusName.includes("telegram") || desktopEntry.includes("telegram") || identity.includes("telegram"))
            return Icons.telegram;
        return Icons.player;
    }

    onFilteredPlayersChanged: {
        if (!root.filteredPlayers.includes(root.trackedPlayer))
            root.trackedPlayer = root.filteredPlayers.find(player => player.isPlaying) ?? root.filteredPlayers[0] ?? null;
        if (root.isInitializing && (root.cachedDbusName || root.cachedIdentity) && root.filteredPlayers.length > 0) {
            const matched = root.filteredPlayers.find(player => root.matchesSavedPlayer(player));
            if (matched) {
                root.trackedPlayer = matched;
                root.isInitializing = false;
            }
        }
    }

    Component.onCompleted: {
        if (StateService.initialized) {
            root.cachedDbusName = StateService.get("lastPlayerDbusName", "");
            root.cachedIdentity = StateService.get("lastPlayerIdentity", "");
            root.loadLastPlayer();
        }
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            root.cachedDbusName = StateService.get("lastPlayerDbusName", "");
            root.cachedIdentity = StateService.get("lastPlayerIdentity", "");
            root.loadLastPlayer();
        }
    }

    function loadLastPlayer() {
        if (!root.cachedDbusName && !root.cachedIdentity) {
            root.isInitializing = false;
            return;
        }
        const matched = root.filteredPlayers.find(player => root.matchesSavedPlayer(player));
        if (matched)
            root.trackedPlayer = matched;
        root.isInitializing = false;
    }

    function saveLastPlayer() {
        if (!root.trackedPlayer || root.isInitializing)
            return;
        StateService.set("lastPlayerDbusName", root.trackedPlayer.dbusName || "");
        StateService.set("lastPlayerIdentity", root.trackedPlayer.identity || "");
    }

    function togglePlaying() {
        if (root.canTogglePlaying)
            root.activePlayer.togglePlaying();
    }

    function previous() {
        if (root.canGoPrevious)
            root.activePlayer.previous();
    }

    function next() {
        if (root.canGoNext)
            root.activePlayer.next();
    }

    function setLoopState(loopState) {
        if (root.loopSupported)
            root.activePlayer.loopState = loopState;
    }

    function setShuffle(shuffle) {
        if (root.shuffleSupported)
            root.activePlayer.shuffle = shuffle;
    }

    function setActivePlayer(player) {
        root.trackedPlayer = player ? player : (root.filteredPlayers.length > 0 ? root.filteredPlayers[0] : null);
        root.saveLastPlayer();
    }

    function cyclePlayer(direction) {
        const players = root.filteredPlayers;
        if (players.length === 0)
            return;

        const currentIndex = players.indexOf(root.activePlayer);
        const newIndex = direction > 0
            ? (currentIndex + 1) % players.length
            : (currentIndex - 1 + players.length) % players.length;

        root.trackedPlayer = players[newIndex];
        root.saveLastPlayer();
    }

    Instantiator {
        model: Mpris.players

        Connections {
            required property var modelData
            target: modelData

            Component.onCompleted: {
                if (!root.isPlayerAllowed(modelData))
                    return;
                if (!root.trackedPlayer || (modelData.isPlaying && !root.trackedPlayer.isPlaying))
                    root.trackedPlayer = modelData;
            }

            function onPlaybackStateChanged() {
                if (!modelData.isPlaying || !root.isPlayerAllowed(modelData))
                    return;
                if (root.trackedPlayer !== modelData && !(root.trackedPlayer && root.trackedPlayer.isPlaying)) {
                    root.isInitializing = false;
                    root.trackedPlayer = modelData;
                    root.saveLastPlayer();
                }
            }
        }
    }
}
