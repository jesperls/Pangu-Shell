pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower as UPower
import qs.modules.theme

Singleton {
    id: root

    readonly property var availableProfiles: UPower.PowerProfiles.hasPerformanceProfile ? ["power-saver", "balanced", "performance"] : ["power-saver", "balanced"]

    readonly property string currentProfile: {
        switch (UPower.PowerProfiles.profile) {
        case UPower.PowerProfile.PowerSaver:
            return "power-saver";
        case UPower.PowerProfile.Performance:
            return "performance";
        default:
            return "balanced";
        }
    }

    function setProfile(profileName) {
        if (!root.availableProfiles.includes(profileName)) return;
        switch (profileName) {
        case "power-saver":
            UPower.PowerProfiles.profile = UPower.PowerProfile.PowerSaver;
            break;
        case "performance":
            UPower.PowerProfiles.profile = UPower.PowerProfile.Performance;
            break;
        default:
            UPower.PowerProfiles.profile = UPower.PowerProfile.Balanced;
        }
    }

    function getProfileIcon(profileName) {
        if (profileName === "power-saver")
            return Icons.powerSave;
        if (profileName === "performance")
            return Icons.performance;
        return Icons.balanced;
    }

    function getProfileDisplayName(profileName) {
        if (profileName === "power-saver")
            return "Power Save";
        if (profileName === "balanced")
            return "Balanced";
        if (profileName === "performance")
            return "Performance";
        return profileName;
    }
}
