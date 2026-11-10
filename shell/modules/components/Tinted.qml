pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.modules.theme
import qs.config

Item {
    id: root
    property var sourceItem: null
    property bool fullTint: false

    readonly property var optimizedPalette: [
        "background", "overBackground", "shadow",
        "surface", "surfaceBright", "surfaceDim",
        "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest", "surfaceContainerLow", "surfaceContainerLowest",
        "primary", "secondary", "tertiary",
        "red", "lightRed",
        "green", "lightGreen",
        "blue", "lightBlue",
        "yellow", "lightYellow",
        "cyan", "lightCyan",
        "magenta", "lightMagenta"
    ]

    property bool active: Config.tintIcons

    Loader {
        active: root.active
        anchors.fill: parent
        sourceComponent: Item {
            anchors.fill: parent

            Item {
                id: paletteSourceItem
                visible: !root.fullTint
                width: root.optimizedPalette.length
                height: 1
                opacity: 0

                Row {
                    anchors.fill: parent
                    Repeater {
                        model: root.optimizedPalette
                        delegate: Rectangle {
                            id: paletteRect
                            required property string modelData
                            width: 1
                            height: 1
                            color: Colors[modelData]
                        }
                    }
                }
            }

            ShaderEffectSource {
                id: paletteTextureSource
                sourceItem: !root.fullTint ? paletteSourceItem : null
                hideSource: true
                visible: false
                smooth: false
                recursive: false
                live: !root.fullTint
            }

            ShaderEffectSource {
                id: internalSource
                sourceItem: root.sourceItem
                hideSource: true
                live: false

                Component.onCompleted: scheduleUpdate()
            }
            
            Connections {
                target: root.sourceItem
                function onSourceChanged() { internalSource.scheduleUpdate(); }
                function onStatusChanged() { internalSource.scheduleUpdate(); }
            }
            
            Connections {
                target: root
                function onSourceItemChanged() { internalSource.scheduleUpdate(); }
                function onVisibleChanged() { if (root.visible) internalSource.scheduleUpdate(); }
            }

            MultiEffect {
                visible: root.fullTint
                anchors.fill: parent
                source: internalSource
                brightness: 1.0
                colorization: 1.0
                colorizationColor: Styling.srItem("overprimary")
            }

            ShaderEffect {
                visible: !root.fullTint
                anchors.fill: parent
                
                property var source: internalSource
                property var paletteTexture: paletteTextureSource
                property real paletteSize: root.optimizedPalette.length
                property real texWidth: root.width
                property real texHeight: root.height

                vertexShader: "../widgets/dashboard/wallpapers/palette.vert.qsb"
                fragmentShader: "../widgets/dashboard/wallpapers/palette.frag.qsb"
            }
        }
    }
}
