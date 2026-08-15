import QtQuick

/*
 * Busy indicator: a dim track ring with a lit arc over it, spun by the scene
 * graph rather than repainted.
 *
 * Replaces the rotating-rectangle-with-a-notch-cut-in-it that the audio, video
 * and radio pages each had a copy of. That cost the same to run and read as a
 * rendering fault rather than as progress.
 */
Item {
    id: spin

    property color tint: "#ffffff"
    property bool  running: true

    // Fraction of the radius given to the stroke.
    property real  thickness: 0.09

    implicitWidth: 44
    implicitHeight: 44

    onTintChanged:      arc.requestPaint()
    onThicknessChanged: arc.requestPaint()

    Canvas {
        id: arc
        anchors.fill: parent

        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = Math.max(2, Math.min(width, height) * spin.thickness)
            const r = Math.min(width, height) / 2 - w
            if (r <= 0) return
            ctx.lineWidth = w
            ctx.lineCap = "round"

            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.10)
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2)
            ctx.stroke()

            ctx.strokeStyle = spin.tint
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, r, -Math.PI / 2, Math.PI * 0.7)
            ctx.stroke()
        }

        RotationAnimation on rotation {
            running: spin.running
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 900
        }
    }
}
