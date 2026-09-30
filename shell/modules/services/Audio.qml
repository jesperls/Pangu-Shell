pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.modules.services
import qs.modules.theme

Singleton {
    id: root

    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00
    property real value: sink?.audio?.volume ?? 0

    property bool protectionEnabled: true
    readonly property real maxVolumeJump: 0.15  // 15% max jump
    property bool protectionTriggered: false

    Connections {
        target: StateService
        function onStateLoaded() {
            root.protectionEnabled = StateService.get("volumeProtectionEnabled", true);
        }
    }

    function setProtectionEnabled(enabled: bool) {
        root.protectionEnabled = enabled;
        StateService.set("volumeProtectionEnabled", enabled);
    }

    signal sinkProtectionTriggered(string reason);
    signal volumeChanged(real volume, bool muted, var node);
    signal micVolumeChanged(real volume, bool muted, var node);

    PwObjectTracker {
        objects: [sink, source]
    }

    Connections {
        target: root.sink?.audio ?? null
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            if (root.sink?.ready) {
                root.volumeChanged(root.sink.audio.volume, root.sink.audio.muted, root.sink);
            }
        }
        function onMutedChanged() {
            if (root.sink?.ready) {
                root.volumeChanged(root.sink.audio.volume, root.sink.audio.muted, root.sink);
            }
        }
    }

    Connections {
        target: root.source?.audio ?? null
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            if (root.source?.ready) {
                root.micVolumeChanged(root.source.audio.volume, root.source.audio.muted, root.source);
            }
        }
        function onMutedChanged() {
            if (root.source?.ready) {
                root.micVolumeChanged(root.source.audio.volume, root.source.audio.muted, root.source);
            }
        }
    }

    function friendlyDeviceName(node) {
        return (node?.nickname || node?.description || "Unknown");
    }

    function appNodeDisplayName(node) {
        return (node?.properties?.["application.name"] || node?.description || node?.name || "Unknown");
    }

    function correctType(node, isSink) {
        return (node?.isSink === isSink) && node?.audio;
    }

    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => {
            return root.correctType(node, isSink) && node.isStream;
        });
    }

    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream;
        });
    }

    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    function protectedSetVolume(node, targetVolume: real, currentVolume: real) {
        if (!root.protectionEnabled) {
            return targetVolume;
        }

        const jump = targetVolume - currentVolume;
        
        if (jump <= 0) {
            root.protectionTriggered = false;
            return targetVolume;
        }

        if (jump > root.maxVolumeJump) {
            root.protectionTriggered = true;
            root.sinkProtectionTriggered("Volume jump limited");
            
            protectionResetTimer.restart();
            
            return currentVolume + root.maxVolumeJump;
        }

        root.protectionTriggered = false;
        return targetVolume;
    }

    Timer {
        id: protectionResetTimer
        interval: 1500
        onTriggered: root.protectionTriggered = false
    }

    function setNodeVolume(node, volume: real) {
        if (node?.audio) {
            const current = node.audio.volume;
            const safeVolume = protectedSetVolume(node, volume, current);
            node.audio.volume = Math.max(0, Math.min(hardMaxValue, safeVolume));
        }
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    function volumeIcon(volume: real, muted: bool): string {
        if (muted) return Icons.speakerX;
        if (volume <= 0) return Icons.speakerNone;
        if (volume < 0.33) return Icons.speakerLow;
        return Icons.speakerHigh;
    }
}
