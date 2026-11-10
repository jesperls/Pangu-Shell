pragma Singleton
import QtQuick
import qs.config
import qs.modules.services

QtObject {
    readonly property string defaultFont: Config.defaultFont
    readonly property int animDuration: GameModeService.toggled ? 0 : Config.theme.animDuration

    function radius(offset) {
        return Config.roundness > 0 ? Math.max(Config.roundness + offset, 0) : 0;
    }

    function fontSize(offset) {
        return Math.max(Config.theme.fontSize + offset, 8);
    }

    function monoFontSize(offset) {
        return Math.max(Config.theme.monoFontSize + offset, 8);
    }

    readonly property var transparentConfig: {
        const bgConfig = Config.theme?.srBg;
        return {
            gradient: bgConfig?.gradient ?? [],
            gradientType: bgConfig?.gradientType ?? "linear",
            gradientAngle: bgConfig?.gradientAngle ?? 0,
            gradientCenterX: bgConfig?.gradientCenterX ?? 0.5,
            gradientCenterY: bgConfig?.gradientCenterY ?? 0.5,
            halftoneDotMin: bgConfig?.halftoneDotMin ?? 0,
            halftoneDotMax: bgConfig?.halftoneDotMax ?? 0,
            halftoneStart: bgConfig?.halftoneStart ?? 0,
            halftoneEnd: bgConfig?.halftoneEnd ?? 1,
            halftoneDotColor: bgConfig?.halftoneDotColor ?? "transparent",
            halftoneBackgroundColor: bgConfig?.halftoneBackgroundColor ?? "transparent",
            itemColor: bgConfig?.itemColor ?? "overBackground",
            opacity: 0,
            border: [bgConfig?.border ? bgConfig.border[0] : "transparent", 0],
            radius: 0
        };
    }

    function getStyledRectConfig(variant) {
        switch (variant) {
        case "transparent":
            return transparentConfig;
        case "bg":
            return Config.theme.srBg;
        case "popup":
            return Config.theme.srPopup;
        case "internalbg":
            return Config.theme.srInternalBg;
        case "pane":
            return Config.theme.srPane;
        case "common":
        case "surface":
            return Config.theme.srCommon;
        case "focus":
            return Config.theme.srFocus;
        case "primary":
            return Config.theme.srPrimary;
        case "primaryfocus":
            return Config.theme.srPrimaryFocus;
        case "overprimary":
            return Config.theme.srOverPrimary;
        case "secondary":
            return Config.theme.srSecondary;
        case "secondaryfocus":
            return Config.theme.srSecondaryFocus;
        case "oversecondary":
            return Config.theme.srOverSecondary;
        case "tertiary":
            return Config.theme.srTertiary;
        case "tertiaryfocus":
            return Config.theme.srTertiaryFocus;
        case "overtertiary":
            return Config.theme.srOverTertiary;
        case "error":
            return Config.theme.srError;
        case "errorfocus":
            return Config.theme.srErrorFocus;
        case "overerror":
            return Config.theme.srOverError;
        case "barbg":
            return Config.theme.srBarBg;
        default:
            return Config.theme.srCommon;
        }
    }

    function srItem(variant) {
        return Colors.resolve(getStyledRectConfig(variant).itemColor);
    }
}
