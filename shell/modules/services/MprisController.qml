pragma Singleton
pragma ComponentBehavior: Bound

import QtQml.Models
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.config
import qs.modules.theme

Singleton {
    id: root

    property var trackedPlayer: null
    property var filteredPlayers: {
        const filtered = Mpris.players.values.filter(player => {
            const dbusName = (player.dbusName || "").toLowerCase();
            if (!Config.bar.enableFirefoxPlayer && dbusName.includes("firefox")) {
                return false;
            }
            return true;
        });
        return filtered;
    }

    readonly property var activePlayer: filteredPlayers.includes(trackedPlayer) ? trackedPlayer : (filteredPlayers.find(player => player.isPlaying) ?? filteredPlayers[0] ?? null)
    
    property bool isInitializing: true
    property string cachedDbusName: ""

    property bool isPlaying: activePlayer ? activePlayer.isPlaying : false
    property bool canTogglePlaying: activePlayer ? activePlayer.canTogglePlaying : false
    property bool canGoPrevious: activePlayer ? activePlayer.canGoPrevious : false
    property bool canGoNext: activePlayer ? activePlayer.canGoNext : false
    property bool loopSupported: activePlayer && activePlayer.loopSupported && activePlayer.canControl
    property var loopState: activePlayer ? activePlayer.loopState : (typeof MprisLoopState !== 'undefined' ? MprisLoopState.None : 0)
    property bool shuffleSupported: activePlayer && activePlayer.shuffleSupported && activePlayer.canControl
    property bool hasShuffle: activePlayer ? activePlayer.shuffle : false

    function playerBaseName(name) {
        return (name || "").toLowerCase().replace(/\.instance[-_a-z0-9]*$/, "");
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
        if (root.isInitializing && root.cachedDbusName && root.filteredPlayers.length > 0) {
            for (let i = 0; i < root.filteredPlayers.length; i++) {
                const player = root.filteredPlayers[i];
                if (playerBaseName(player.dbusName) === playerBaseName(root.cachedDbusName)) {
                    root.trackedPlayer = player;
                    root.isInitializing = false;
                    return;
                }
            }
        }
    }

    Component.onCompleted: {
        root.cachedDbusName = StateService.get("lastPlayerDbusName", "");
        if (StateService.initialized) {
            root.loadLastPlayer();
        }
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            root.cachedDbusName = StateService.get("lastPlayerDbusName", "");
            root.loadLastPlayer();
        }
    }

    function loadLastPlayer() {
        if (!root.cachedDbusName) {
            root.isInitializing = false;
            return;
        }

        for (let i = 0; i < root.filteredPlayers.length; i++) {
            const player = root.filteredPlayers[i];
            if (playerBaseName(player.dbusName) === playerBaseName(root.cachedDbusName)) {
                root.trackedPlayer = player;
                break;
            }
        }
        root.isInitializing = false;
    }

    function saveLastPlayer() {
        if (!root.trackedPlayer || root.isInitializing)
            return;

        StateService.set("lastPlayerDbusName", root.trackedPlayer.dbusName);
    }

    function togglePlaying() {
        if (root.canTogglePlaying)
            root.activePlayer.togglePlaying();
    }

    function previous() {
        if (root.canGoPrevious) {
            root.activePlayer.previous();
        }
    }

    function next() {
        if (root.canGoNext) {
            root.activePlayer.next();
        }
    }

    function setLoopState(loopState) {
        if (root.loopSupported) {
            root.activePlayer.loopState = loopState;
        }
    }

    function setShuffle(shuffle) {
        if (root.shuffleSupported) {
            root.activePlayer.shuffle = shuffle;
        }
    }

    function setActivePlayer(player) {
        const targetPlayer = player ? player : (root.filteredPlayers.length > 0 ? root.filteredPlayers[0] : null);

        root.trackedPlayer = targetPlayer;
        root.saveLastPlayer();
    }

    function cyclePlayer(direction) {
        const players = root.filteredPlayers;
        if (players.length === 0)
            return;

        const currentIndex = players.indexOf(root.activePlayer);
        let newIndex;

        if (direction > 0) {
            newIndex = (currentIndex + 1) % players.length;
        } else {
            newIndex = (currentIndex - 1 + players.length) % players.length;
        }

        root.trackedPlayer = players[newIndex];
        root.saveLastPlayer();
    }

    Instantiator {
        model: root.filteredPlayers

        Connections {
            required property var modelData
            target: modelData

            Component.onCompleted: {
                if (!root.trackedPlayer || (modelData.isPlaying && !root.trackedPlayer.isPlaying))
                    root.trackedPlayer = modelData;
            }

            function onPlaybackStateChanged() {
                if (!modelData.isPlaying)
                    return;
                const dbusName = (modelData.dbusName || "").toLowerCase();
                if (!Config.bar.enableFirefoxPlayer && dbusName.includes("firefox"))
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
