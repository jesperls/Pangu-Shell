import QtQuick
import QtQuick.Window
import qs.modules.theme

Canvas {
    id: root

    property color color: Styling.srItem("overprimary")
    property real lineWidth: 2
    property real frequency: 2
    property real amplitudeMultiplier: 0.5
    property real fullLength: width
    property bool running: true

    property bool animationsEnabled: true

    readonly property bool shouldAnimate: running && animationsEnabled && 
                                          visible && width > 0 && opacity > 0 &&
                                          (root.Window.window?.visible ?? false)

    onColorChanged: requestPaint()
    onLineWidthChanged: requestPaint()
    onFrequencyChanged: requestPaint()
    onAmplitudeMultiplierChanged: requestPaint()
    onFullLengthChanged: requestPaint()
    onShouldAnimateChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        if (width <= 0 || height <= 0 || fullLength <= 0) return;

        var amp = root.lineWidth * root.amplitudeMultiplier;
        var freq = root.frequency;
        var phase = Date.now() / 400.0;
        var centerY = height / 2;

        ctx.strokeStyle = root.color;
        ctx.lineWidth = root.lineWidth;
        ctx.lineCap = "round";
        ctx.beginPath();

        for (var x = ctx.lineWidth / 2; x <= root.width - ctx.lineWidth / 2; x += 1) {
            var waveY = centerY + amp * Math.sin(freq * 2 * Math.PI * x / root.fullLength + phase);
            if (x === ctx.lineWidth / 2)
                ctx.moveTo(x, waveY);
            else
                ctx.lineTo(x, waveY);
        }

        ctx.stroke();
    }

    FrameAnimation {
        running: root.shouldAnimate
        onTriggered: root.requestPaint()
    }
}
