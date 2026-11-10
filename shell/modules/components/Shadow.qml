import QtQuick
import QtQuick.Effects
import qs.modules.theme
import qs.config

MultiEffect {
    shadowEnabled: true
    shadowHorizontalOffset: Config.theme?.shadowXOffset ?? 0
    shadowVerticalOffset: Config.theme?.shadowYOffset ?? 4
    shadowBlur: Config.theme?.shadowBlur ?? 0.5
    shadowColor: Colors.resolve(Config.theme?.shadowColor ?? "shadow")
    shadowOpacity: Config.theme?.shadowOpacity ?? 0.5
}
