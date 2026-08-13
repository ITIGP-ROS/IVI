import QtQuick

/*
 * Wi-Fi signal glyph: three arcs over a dot, with an optional padlock.
 *
 * Drawn, not typed and not an image.
 *
 * A glyph was the obvious answer — 📶 is one character — but the emoji fonts
 * render it in full colour, which is why the list came out with an orange bar
 * chart and a blue satellite dish on a page that has neither colour. Forcing a
 * monochrome symbol font instead means depending on that font existing on the
 * head unit, and this codebase has already been bitten by that: see the note on
 * the × in VirtualKeyboard, where a Dingbats glyph came up blank on the target
 * image. A PNG would have to ship at every size the list is ever laid out at.
 *
 * Canvas has none of those problems: it inherits the page's colour, scales to
 * whatever the row is, and looks the same on the bench and in the car.
 */
Item {
    id: glyph

    property color color: "#ffffff"

    // 0-100, exactly as NetworkManager reports it.
    property int strength: 100

    property bool secured: false

    // Arcs above the current signal level are drawn, not dropped: a two-bar
    // network should read as "two of three", which needs the third one there to
    // be missing from.
    property real dimAlpha: 0.25

    implicitWidth: implicitHeight * 1.32
    implicitHeight: 26

    onColorChanged:    canvas.requestPaint()
    onStrengthChanged: canvas.requestPaint()
    onSecuredChanged:  canvas.requestPaint()
    onDimAlphaChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var w = width
            var h = height
            if (w <= 0 || h <= 0)
                return

            // The lock lives in the right-hand third, so the cone shifts left to
            // make room for it rather than sitting under it.
            var cx = glyph.secured ? w * 0.36 : w * 0.5
            var cy = h * 0.80
            var lw = h * 0.11

            ctx.lineWidth = lw
            ctx.lineCap = "round"
            ctx.strokeStyle = glyph.color
            ctx.fillStyle = glyph.color

            // Three thresholds, evenly spaced: anything below a quarter is one
            // bar's worth of nothing and shows the dot alone.
            var bars = glyph.strength >= 70 ? 3
                     : glyph.strength >= 45 ? 2
                     : glyph.strength >= 20 ? 1 : 0

            var radii = [h * 0.22, h * 0.43, h * 0.64]
            for (var i = 0; i < radii.length; i++) {
                ctx.globalAlpha = (i < bars) ? 1.0 : glyph.dimAlpha
                ctx.beginPath()
                // 225°→315° in canvas angles (y grows downward), i.e. the upper
                // 90° wedge — the shape everything else in the world uses.
                ctx.arc(cx, cy, radii[i], Math.PI * 1.25, Math.PI * 1.75)
                ctx.stroke()
            }

            ctx.globalAlpha = 1.0
            ctx.beginPath()
            ctx.arc(cx, cy, lw * 0.62, 0, Math.PI * 2)
            ctx.fill()

            if (glyph.secured) {
                var s  = h * 0.40           // body width
                var bx = w - s * 1.15       // left edge of the body
                var by = h * 0.52           // top edge of the body
                var bh = h * 0.30           // body height

                // Shackle first, so the body covers where its legs end.
                ctx.lineWidth = s * 0.16
                ctx.beginPath()
                ctx.arc(bx + s / 2, by, s * 0.30, Math.PI, Math.PI * 2)
                ctx.stroke()

                ctx.beginPath()
                ctx.roundedRect(bx, by, s, bh, s * 0.18, s * 0.18)
                ctx.fill()
            }
        }
    }
}
