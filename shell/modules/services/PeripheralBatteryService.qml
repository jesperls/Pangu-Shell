pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.modules.services
import qs.modules.theme

Singleton {
    id: root

    property var headsetDevices: []

    readonly property var upowerDevices: {
        const raw = UPower.devices?.values ?? [];
        const out = [];
        for (let i = 0; i < raw.length; i++) {
            const d = raw[i];
            if (!d || d.isLaptopBattery || d.type === UPowerDevice.LinePower || d.type === UPowerDevice.Battery)
                continue;
            const rawPct = Number(d.percentage);
            if (!Number.isFinite(rawPct) || rawPct <= 0)
                continue;
            const pct = rawPct <= 1.0 ? Math.round(rawPct * 100) : Math.round(rawPct);
            if (pct <= 0 || pct > 100)
                continue;
            const label = String(d.model || d.nativePath || "Wireless Device").trim();
            out.push({
                id: "upower:" + (d.nativePath || label),
                name: label,
                percentage: pct,
                charging: d.state === UPowerDevice.Charging || d.state === UPowerDevice.PendingCharge,
                icon: root.iconForDevice(label, d.type)
            });
        }
        return out;
    }

    readonly property var devices: {
        const combined = root.upowerDevices.slice();
        const existingNames = combined.map(d => d.name.toLowerCase());
        for (let i = 0; i < root.headsetDevices.length; i++) {
            const hc = root.headsetDevices[i];
            const lower = hc.name.toLowerCase();
            if (!existingNames.some(n => n.includes(lower) || lower.includes(n)))
                combined.push(hc);
        }
        return combined;
    }

    function iconForDevice(name, upowerType) {
        const lower = String(name || "").toLowerCase();
        if (upowerType === UPowerDevice.Mouse || lower.includes("mouse") || lower.includes("superstrike") || lower.includes("superlight") || lower.includes("viper") || lower.includes("deathadder"))
            return Icons.mouse;
        if (upowerType === UPowerDevice.Keyboard || lower.includes("keyboard") || lower.includes("keychron"))
            return Icons.keyboard;
        if (upowerType === UPowerDevice.Headset || upowerType === UPowerDevice.Headphones || lower.includes("headset") || lower.includes("a50") || lower.includes("arctis") || lower.includes("buds") || lower.includes("airpods"))
            return Icons.headset;
        if (upowerType === UPowerDevice.GamingInput || lower.includes("controller") || lower.includes("dualsense") || lower.includes("xbox"))
            return Icons.gamepad;
        return Icons.bluetoothConnected;
    }

    function refresh() {
        if (!SuspendManager.isSuspending && !headsetProcess.running)
            headsetProcess.running = true;
    }

    Timer {
        interval: 60000
        running: !SuspendManager.isSuspending
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: headsetProcess
        command: ["sh", "-c", "command -v headsetcontrol >/dev/null 2>&1 && headsetcontrol -o json 2>/dev/null || true"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const raw = text.trim();
                if (!raw) {
                    root.headsetDevices = [];
                    return;
                }
                try {
                    const data = JSON.parse(raw);
                    const list = Array.isArray(data?.devices) ? data.devices : [];
                    const parsed = [];
                    for (let i = 0; i < list.length; i++) {
                        const dev = list[i];
                        const bat = dev?.battery;
                        if (!bat || bat.status === "BATTERY_UNAVAILABLE")
                            continue;
                        const lvl = Number(bat.level);
                        if (!Number.isFinite(lvl) || lvl < 0)
                            continue;
                        const label = String(dev.product || dev.device || "Headset").trim();
                        parsed.push({
                            id: "hc:" + label,
                            name: label,
                            percentage: Math.min(100, Math.round(lvl)),
                            charging: bat.status === "BATTERY_CHARGING",
                            icon: Icons.headset
                        });
                    }
                    root.headsetDevices = parsed;
                } catch (e) {
                    root.headsetDevices = [];
                }
            }
        }
    }
}
