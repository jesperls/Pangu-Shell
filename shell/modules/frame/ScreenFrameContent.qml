import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.modules.components
import qs.modules.corners
import qs.modules.services
import qs.modules.theme
import qs.config
import qs.modules.globals

Item {
    id: root

    required property ShellScreen targetScreen
    readonly property string screenName: targetScreen?.name ?? ""
    property bool hasFullscreenWindow: false

    readonly property bool frameEnabled: Config.bar?.frameEnabled ?? false
    readonly property bool configContainBar: Config.bar?.containBar ?? false
    readonly property string barPos: Config.bar?.position ?? "top"
    readonly property string notchPos: Config.notchPosition ?? "top"
    
    readonly property var barPanel: Visibilities.barPanels[screenName]
    readonly property var dockPanel: Visibilities.dockPanels[screenName]
    
    readonly property bool barReveal: barPanel ? barPanel.reveal : true
    readonly property bool dockReveal: dockPanel ? dockPanel.reveal : true
    readonly property bool notchReveal: barPanel ? barPanel.notchReveal : true

    readonly property bool barHovered: barPanel ? (barPanel.barHoverActive || barPanel.notchHoverActive || barPanel.notchOpen) : false
    readonly property bool dockHovered: dockPanel ? (dockPanel.reveal && (dockPanel.activeWindowFullscreen || dockPanel.keepHidden || !dockPanel.pinned)) : false

    readonly property real baseThickness: {
        const base = Config.bar?.frameThickness ?? 6;
        return Math.max(0, Math.min(Math.round(base), 40));
    }

    readonly property int barSize: {
        if (!barPanel) return 44;
        const isHoriz = barPos === "top" || barPos === "bottom";
        return isHoriz ? barPanel.barTargetHeight : barPanel.barTargetWidth;
    }

    readonly property var centerGap: (Config.bar?.splitOnCenteredLayout ?? true) ? Compositor.gapFor(screenName) : null
    readonly property bool splitActive: centerGap !== null && width > 0 && (barPos === "top" || barPos === "bottom")
    readonly property int splitGapPadding: (centerGap && centerGap.square) ? 0 : (Config.bar?.splitGapPadding ?? 4)
    readonly property real splitStart: splitActive ? Math.max(0, centerGap.x - splitGapPadding) : 0
    readonly property real splitEnd: splitActive ? Math.min(width, centerGap.x + centerGap.width + splitGapPadding) : 0
    readonly property real stripSize: barPos === "top" ? topThickness : bottomThickness
    readonly property bool splitSquare: splitActive && (centerGap.square ?? false)
    readonly property real stripRadius: splitSquare ? 0 : Math.min(innerRadius, stripSize / 2)
    readonly property real stripFilletSize: splitSquare ? 0 : Math.max(1, Math.min(innerRadius, stripSize))
    readonly property color stripColor: Colors.resolve(Config.theme.srBg.gradient[0][0])

    property real _barAnimProgress: barReveal ? 1.0 : 0.0
    Behavior on _barAnimProgress {
        enabled: Styling.animDuration > 0
        NumberAnimation { duration: Styling.animDuration / 2; easing.type: Easing.OutCubic }
    }

    property real _dockAnimProgress: dockReveal ? 1.0 : 0.0
    Behavior on _dockAnimProgress {
        enabled: Styling.animDuration > 0
        NumberAnimation { duration: Styling.animDuration / 2; easing.type: Easing.OutCubic }
    }

    property real _notchAnimProgress: notchReveal ? 1.0 : 0.0
    Behavior on _notchAnimProgress {
        enabled: Styling.animDuration > 0
        NumberAnimation { duration: Styling.animDuration / 2; easing.type: Easing.OutCubic }
    }

    readonly property int barExpansion: (frameEnabled && configContainBar) ? Math.round((barSize + baseThickness) * _barAnimProgress) : 0



    readonly property int topThickness: calculateSideThickness("top")
    readonly property int bottomThickness: calculateSideThickness("bottom")
    readonly property int leftThickness: calculateSideThickness("left")
    readonly property int rightThickness: calculateSideThickness("right")

    function calculateSideThickness(side) {
        let t = baseThickness;
        if (hasFullscreenWindow) {
            let restore = false;
            let progress = 0.0;

            if (barPos === side && barHovered) { restore = true; progress = Math.max(progress, _barAnimProgress); }
            if (notchPos === side && barHovered) { restore = true; progress = Math.max(progress, _notchAnimProgress); }
            if (dockPanel && dockPanel.position === side && dockHovered) { restore = true; progress = Math.max(progress, _dockAnimProgress); }
            
            t = restore ? (baseThickness * progress) : 0;
        }
        
        let expansion = (configContainBar && barPos === side) ? barExpansion : 0;
        return Math.round(t) + expansion;
    }

    readonly property real targetInnerRadius: {
        if (!root.hasFullscreenWindow) return Styling.radius(4);
        if (!barHovered && !dockHovered) return 0;
        
        let progress = Math.max(_barAnimProgress, _dockAnimProgress, _notchAnimProgress);
        return Styling.radius(4) * progress;
    }
    
    property real innerRadius: targetInnerRadius

    StyledRect {
        id: frameFill
        anchors.fill: parent
        variant: "bg"
        radius: 0
        enableBorder: false
        visible: root.frameEnabled
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: frameMask
            maskInverted: true
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    Item {
        id: frameMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        readonly property real topInset: root.splitActive && root.barPos === "top" ? -root.innerRadius : root.topThickness
        readonly property real bottomInset: root.splitActive && root.barPos === "bottom" ? -root.innerRadius : root.bottomThickness

        Rectangle {
            id: maskRect
            x: root.leftThickness
            y: frameMask.topInset
            width: parent.width - (root.leftThickness + root.rightThickness)
            height: parent.height - (frameMask.topInset + frameMask.bottomInset)
            radius: root.innerRadius
            color: "white"
            visible: width > 0 && height > 0
        }
    }

    StyledRect {
        id: stripSegmentLeft
        variant: "bg"
        enableBorder: false
        radius: 0
        visible: root.frameEnabled && root.splitActive
        x: 0
        y: root.barPos === "top" ? 0 : parent.height - height
        width: Math.max(0, root.splitStart)
        height: root.stripSize
        topRightRadius: root.barPos === "top" ? 0 : root.stripRadius
        bottomRightRadius: root.barPos === "top" ? root.stripRadius : 0
    }

    StyledRect {
        id: stripSegmentRight
        variant: "bg"
        enableBorder: false
        radius: 0
        visible: root.frameEnabled && root.splitActive
        x: root.splitEnd
        y: root.barPos === "top" ? 0 : parent.height - height
        width: Math.max(0, parent.width - root.splitEnd)
        height: root.stripSize
        topLeftRadius: root.barPos === "top" ? 0 : root.stripRadius
        bottomLeftRadius: root.barPos === "top" ? root.stripRadius : 0
    }

    RoundCorner {
        id: stripFilletLeft
        visible: stripSegmentLeft.visible && root.stripFilletSize > 0 && root.splitStart > 0 && root.stripSize > 0
        size: root.stripFilletSize
        x: root.splitStart
        y: root.barPos === "top" ? 0 : parent.height - size
        corner: root.barPos === "top" ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.BottomLeft
        color: root.stripColor
        opacity: Config.theme.srBg.opacity
    }

    RoundCorner {
        id: stripFilletRight
        visible: stripSegmentRight.visible && root.stripFilletSize > 0 && root.splitEnd < parent.width && root.stripSize > 0
        size: root.stripFilletSize
        x: root.splitEnd - size
        y: root.barPos === "top" ? 0 : parent.height - size
        corner: root.barPos === "top" ? RoundCorner.CornerEnum.TopRight : RoundCorner.CornerEnum.BottomRight
        color: root.stripColor
        opacity: Config.theme.srBg.opacity
    }

    RoundCorner {
        id: stripFilletOuterLeft
        visible: stripSegmentLeft.visible && !root.splitSquare && root.stripSize > 0
        size: Math.max(1, root.innerRadius)
        x: root.leftThickness
        y: root.barPos === "top" ? root.stripSize : parent.height - root.stripSize - size
        corner: root.barPos === "top" ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.BottomLeft
        color: root.stripColor
        opacity: Config.theme.srBg.opacity
    }

    RoundCorner {
        id: stripFilletOuterRight
        visible: stripSegmentRight.visible && !root.splitSquare && root.stripSize > 0
        size: Math.max(1, root.innerRadius)
        x: parent.width - root.rightThickness - size
        y: root.barPos === "top" ? root.stripSize : parent.height - root.stripSize - size
        corner: root.barPos === "top" ? RoundCorner.CornerEnum.TopRight : RoundCorner.CornerEnum.BottomRight
        color: root.stripColor
        opacity: Config.theme.srBg.opacity
    }
}
