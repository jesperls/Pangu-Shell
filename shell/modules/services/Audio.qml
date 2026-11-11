pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.config
import qs.modules.services
import qs.modules.theme

Singleton {
    id: root

    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: Config.system.audio.overAmplify ? 1.5 : 1.0
    property real value: Number.isFinite(sink?.audio?.volume) ? sink.audio.volume : 0

    property bool protectionEnabled: true
    readonly property real maxVolumeJump: 0.15
    property bool protectionTriggered: false

    property bool _sinkSettled: false
    property bool _sourceSettled: false

    Timer {
        id: sinkSettleTimer
        interval: 400
        onTriggered: root._sinkSettled = true
    }

    Timer {
        id: sourceSettleTimer
        interval: 400
        onTriggered: root._sourceSettled = true
    }

    onSinkChanged: {
        root._sinkSettled = false;
        sinkSettleTimer.restart();
    }

    onSourceChanged: {
        root._sourceSettled = false;
        sourceSettleTimer.restart();
    }

    Component.onCompleted: {
        if (StateService.initialized)
            root.protectionEnabled = StateService.get("volumeProtectionEnabled", true);
        sinkSettleTimer.restart();
        sourceSettleTimer.restart();
    }

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

    signal sinkProtectionTriggered(string reason)
    signal volumeChanged(real volume, bool muted, var node)
    signal micVolumeChanged(real volume, bool muted, var node)

    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    Connections {
        target: root.sink?.audio ?? null
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            if (root._sinkSettled && root.sink?.ready && SuspendManager.wakeReady && Number.isFinite(root.sink.audio.volume)) {
                root.volumeChanged(root.sink.audio.volume, root.sink.audio.muted, root.sink);
            }
        }
        function onVolumesChanged() {
            if (root._sinkSettled && root.sink?.ready && SuspendManager.wakeReady && Number.isFinite(root.sink.audio.volume)) {
                root.volumeChanged(root.sink.audio.volume, root.sink.audio.muted, root.sink);
            }
        }
        function onMutedChanged() {
            if (root._sinkSettled && root.sink?.ready && SuspendManager.wakeReady && Number.isFinite(root.sink.audio.volume)) {
                root.volumeChanged(root.sink.audio.volume, root.sink.audio.muted, root.sink);
            }
        }
    }

    Connections {
        target: root.source?.audio ?? null
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            if (root._sourceSettled && root.source?.ready && SuspendManager.wakeReady && Number.isFinite(root.source.audio.volume)) {
                root.micVolumeChanged(root.source.audio.volume, root.source.audio.muted, root.source);
            }
        }
        function onVolumesChanged() {
            if (root._sourceSettled && root.source?.ready && SuspendManager.wakeReady && Number.isFinite(root.source.audio.volume)) {
                root.micVolumeChanged(root.source.audio.volume, root.source.audio.muted, root.source);
            }
        }
        function onMutedChanged() {
            if (root._sourceSettled && root.source?.ready && SuspendManager.wakeReady && Number.isFinite(root.source.audio.volume)) {
                root.micVolumeChanged(root.source.audio.volume, root.source.audio.muted, root.source);
            }
        }
    }

    function friendlyDeviceName(node) {
        return (node?.description || node?.nickname || node?.name || "Unknown");
    }

    function appNodeDisplayName(node) {
        return (node?.properties?.["application.name"] || node?.description || node?.name || "Unknown");
    }

    function isHiddenDevice(node) {
        const name = node?.name ?? "";
        if (!name) return true;
        if (name.startsWith("alsa_input.hw_") || name.startsWith("alsa_output.hw_")) return true;
        if (name.includes(".split") || name.includes("/Internal") || name.startsWith("loopback-")) return true;
        if (name === "easyeffects_sink" || name === "easyeffects_source" || name.startsWith("ee_soe_") || name.startsWith("ee_sie_")) return true;
        return false;
    }

    function isInternalStream(node) {
        const name = (node?.name ?? "").toLowerCase();
        const app = (node?.properties?.["application.name"] ?? "").toLowerCase();
        if (name.startsWith("ee_") || name.includes(".split") || name.startsWith("loopback-"))
            return true;
        if (app === "quickshell" || app === "cava" || app === "easyeffects" || app === "easy effects" || app === "gpu-screen-recorder")
            return true;
        if (name === "quickshell" || name === "cava" || name === "gpu-screen-recorder")
            return true;
        return false;
    }

    function correctType(node, isSink) {
        return (node?.isSink === isSink) && node?.audio;
    }

    function appNodes(isSink) {
        return Pipewire.nodes.values.filter(node => root.correctType(node, isSink) && node.isStream && !root.isInternalStream(node));
    }

    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => root.correctType(node, isSink) && !node.isStream && !root.isHiddenDevice(node));
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
        if (!node?.audio || !Number.isFinite(volume))
            return;
        const current = Number.isFinite(node.audio.volume) ? node.audio.volume : 0;
        const safeVolume = (!node.isStream && node.isSink) ? protectedSetVolume(node, volume, current) : volume;
        node.audio.volume = Math.max(0, Math.min(root.hardMaxValue, safeVolume));
    }

    function setVolume(volume: real) {
        setNodeVolume(root.sink, volume);
    }

    function setMicVolume(volume: real) {
        setNodeVolume(root.source, volume);
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
