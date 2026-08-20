// BluetoothGlyph.qml
//
// The Bluetooth rune in a round well, with a connected and a disconnected
// state. Replaces the two characters the device list used to print beside a
// device name: 🔵 for connected and ⬡ (U+2B21) for not.
//
// Drawn rather than typed, for the reason WifiGlyph, MediaGlyph and
// WeatherGlyph are all drawn — and this pair was a live example of it. U+2B21
// lives in Noto Sans Symbols2, which is not in the image's font set, so the
// disconnected half rendered as a tofu box on the panel while looking fine on
// the bench. The connected half fared no better as design: a flat blue dot from
// the emoji font says "something is here", not "this phone is connected", and
// it carried the emoji font's own colour into a page that sets its own accent.
//
// Strokes have no font to be missing, take the colour they are given, and stay
// sharp at whatever fraction of the row height the list decides on.
//
// The well is the same treatment as IconWell — accent at 0.15 behind, accent at
// 0.5 around — so a device row seats its icon the way the launcher cards do.
import QtQuick

Item {
    id: glyph

    property bool  connected: false

    // Colour of the rune when connected, and the tint of the well behind it.
    property color accent: "#4a9eff"

    // Colour when not connected. The well follows it at a lower alpha, so a
    // disconnected row recedes instead of competing with a connected one.
    property color idleColor: "#8899bb"

    // Rune height as a fraction of the well. 0.5 leaves the well reading as a
    // seat rather than a badge with something crammed into it.
    property real  runeScale: 0.5

    implicitWidth: 34
    implicitHeight: 34

    readonly property color activeColor: connected ? accent : idleColor

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: glyph.connected ? Qt.rgba(glyph.accent.r, glyph.accent.g, glyph.accent.b, 0.15)
                               : Qt.rgba(glyph.idleColor.r, glyph.idleColor.g, glyph.idleColor.b, 0.08)
        border.color: glyph.connected ? Qt.rgba(glyph.accent.r, glyph.accent.g, glyph.accent.b, 0.50)
                                      : Qt.rgba(glyph.idleColor.r, glyph.idleColor.g, glyph.idleColor.b, 0.22)
        border.width: 1

        // The list flips this on a connect, and a well that snaps reads as a
        // redraw rather than as a state change.
        Behavior on color       { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }
    }

    onConnectedChanged: canvas.requestPaint()
    onAccentChanged:    canvas.requestPaint()
    onIdleColorChanged: canvas.requestPaint()
    onRuneScaleChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var w = width, h = height
            if (w <= 0 || h <= 0)
                return

            // The rune's own box. It is taller than wide — 0.69 is the aspect of
            // the real mark, and forcing it square is what makes hand-drawn
            // Bluetooth logos look squat.
            var rh = Math.min(w, h) * glyph.runeScale
            var rw = rh * 0.69
            var bx = (w - rw) / 2
            var by = (h - rh) / 2

            function X(f) { return bx + f * rw }
            function Y(f) { return by + f * rh }

            var lw = Math.max(1.4, rh * 0.13)

            ctx.lineWidth = lw
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.strokeStyle = glyph.activeColor

            // One unbroken polyline, which is what the mark actually is: the
            // stem drawn once, with a bowtie crossing it above and below.
            //
            //   lower-left → upper-right → stem foot → stem head →
            //   upper-right → lower-left
            ctx.beginPath()
            ctx.moveTo(X(0.00), Y(0.25))
            ctx.lineTo(X(1.00), Y(0.75))
            ctx.lineTo(X(0.50), Y(1.00))
            ctx.lineTo(X(0.50), Y(0.00))
            ctx.lineTo(X(1.00), Y(0.25))
            ctx.lineTo(X(0.00), Y(0.75))
            ctx.stroke()

            if (glyph.connected)
                return

            // Disconnected: the universal slash, carved rather than laid on top.
            //
            // Three things this has to get right, and the obvious version gets
            // none of them:
            //
            //  - TOP-LEFT TO BOTTOM-RIGHT, at a true 45°. That is the direction
            //    every "off" badge in the world runs, and it is also the one
            //    that is NOT parallel to the arm of the rune that sweeps up to
            //    the right. Run it the other way and the slash lies along that
            //    arm and the two read as one thick stroke.
            //  - MEASURED OFF THE WELL, not the rune, so it emerges on both
            //    sides. A slash that stops inside the rune's own box looks like
            //    a sixth stroke of the letter rather than something crossing it.
            //  - A THIN knockout. destination-out clears the Canvas so the well
            //    shows through, which is what separates the two shapes; at much
            //    over 2x the stroke it stops being a gap and starts eating the
            //    rune, and what is left no longer reads as Bluetooth at all.
            var cx = w / 2, cy = h / 2
            var half = Math.min(w, h) * 0.36 * Math.SQRT1_2

            ctx.globalCompositeOperation = "destination-out"
            ctx.lineWidth = lw * 1.9
            ctx.beginPath()
            ctx.moveTo(cx - half, cy - half)
            ctx.lineTo(cx + half, cy + half)
            ctx.stroke()

            ctx.globalCompositeOperation = "source-over"
            ctx.lineWidth = lw
            ctx.strokeStyle = glyph.idleColor
            ctx.beginPath()
            ctx.moveTo(cx - half, cy - half)
            ctx.lineTo(cx + half, cy + half)
            ctx.stroke()
        }
    }
}
