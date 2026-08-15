import QtQuick

/*
 * Media-page icons, drawn on a Canvas.
 *
 * Same reason as WeatherGlyph: the pages reach for emoji — 🔍 📻 ⚠ ✕ — inside a
 * Text with `family: "Arial"`, and there is no Arial on the dev laptop or in
 * the Yocto image. It resolves to Liberation Sans, which has none of those
 * codepoints, so every one of them renders as a tofu box on the panel.
 *
 * Strokes instead: no font dependency, no glyph coverage to check, they take
 * the page's accent colour, and they stay sharp at any size on the 1024×600
 * panel.
 *
 * Kept separate from WeatherGlyph rather than merged into one grab-bag — the
 * two share a technique, not a subject, and a caller should not have to import
 * the weather icons to get a magnifier.
 */
Canvas {
    id: glyph

    property string kind: "radio"
    property color  tint: "#ffffff"

    // Secondary colour, for the one part of a glyph worth separating out (the
    // bang inside the warning triangle). Defaults to `tint`, so a caller that
    // does not care gets a single-colour icon.
    property color  accent: tint

    // Multiplier on the derived stroke width, for a heavier or lighter version
    // of the same drawing.
    property real   weight: 1.0

    implicitWidth: 48
    implicitHeight: 48

    onKindChanged:   requestPaint()
    onTintChanged:   requestPaint()
    onAccentChanged: requestPaint()
    onWeightChanged: requestPaint()
    onWidthChanged:  requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()

        const u  = Math.min(width, height)      // everything is a fraction of this
        const lw = Math.max(1.5, u * 0.072) * glyph.weight
        ctx.lineWidth = lw
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.strokeStyle = glyph.tint
        ctx.fillStyle = glyph.tint

        const cx = width / 2, cy = height / 2

        // ---- primitives -----------------------------------------------------

        function disc(x, y, r) {
            ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill()
        }

        function ring(x, y, r) {
            ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.stroke()
        }

        function line(x1, y1, x2, y2) {
            ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
        }

        // Rounded rectangle as an explicit path. Context2D does have
        // roundedRect(), but it is a Qt extension rather than HTML canvas, and
        // quadratic corners cost nothing here.
        function rrect(x, y, w, h, r) {
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.lineTo(x + w - r, y)
            ctx.quadraticCurveTo(x + w, y, x + w, y + r)
            ctx.lineTo(x + w, y + h - r)
            ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
            ctx.lineTo(x + r, y + h)
            ctx.quadraticCurveTo(x, y + h, x, y + h - r)
            ctx.lineTo(x, y + r)
            ctx.quadraticCurveTo(x, y, x + r, y)
            ctx.closePath()
        }

        // ---- the glyphs -----------------------------------------------------

        switch (glyph.kind) {

        case "radio": {
            // A receiver seen face-on: aerial, case, speaker grille, tuning
            // dial. Chosen over a broadcast mast because the mast is the same
            // drawing as "waves" below, and the two appear side by side.
            line(cx - u * 0.13, cy - u * 0.07, cx + u * 0.23, cy - u * 0.39)
            disc(cx + u * 0.25, cy - u * 0.41, lw * 0.55)

            rrect(cx - u * 0.38, cy - u * 0.08, u * 0.76, u * 0.46, u * 0.10)
            ctx.stroke()

            ring(cx - u * 0.17, cy + u * 0.15, u * 0.12)

            // Tuning slot and its two knobs, on the half the grille leaves free.
            ctx.lineWidth = lw * 0.8
            line(cx + u * 0.03, cy + u * 0.04, cx + u * 0.30, cy + u * 0.04)
            ctx.lineWidth = lw
            disc(cx + u * 0.09, cy + u * 0.23, lw * 0.6)
            disc(cx + u * 0.24, cy + u * 0.23, lw * 0.6)
            break
        }

        case "waves": {
            // Transmitting: a source with arcs opening away from it on both
            // sides. Symmetric on purpose — a one-sided fan reads as a wifi
            // meter, which is a different idea.
            disc(cx, cy, u * 0.075)
            ctx.lineWidth = lw * 0.9
            for (let i = 1; i <= 2; i++) {
                const r = u * (0.055 + i * 0.145)
                ctx.beginPath()
                ctx.arc(cx, cy, r, Math.PI * 0.74, Math.PI * 1.26)
                ctx.stroke()
                ctx.beginPath()
                ctx.arc(cx, cy, r, Math.PI * -0.26, Math.PI * 0.26)
                ctx.stroke()
            }
            break
        }

        case "search":
            ring(cx - u * 0.07, cy - u * 0.07, u * 0.22)
            line(cx + u * 0.09, cy + u * 0.09, cx + u * 0.29, cy + u * 0.29)
            break

        case "folder": {
            rrect(cx - u * 0.36, cy - u * 0.19, u * 0.72, u * 0.46, u * 0.07)
            ctx.stroke()
            // The tab, stroked over the body rather than cut into one path:
            // the join where a tab meets a rounded corner is fiddly to get
            // right and invisible at this size either way.
            ctx.beginPath()
            ctx.moveTo(cx - u * 0.36, cy - u * 0.19)
            ctx.lineTo(cx - u * 0.34, cy - u * 0.31)
            ctx.lineTo(cx - u * 0.12, cy - u * 0.31)
            ctx.lineTo(cx - u * 0.03, cy - u * 0.19)
            ctx.stroke()
            break
        }

        case "usb": {
            // A stick end-on: connector shell above, body below.
            rrect(cx - u * 0.11, cy - u * 0.37, u * 0.22, u * 0.19, u * 0.03)
            ctx.stroke()
            ctx.lineWidth = lw * 0.7
            line(cx - u * 0.04, cy - u * 0.31, cx - u * 0.04, cy - u * 0.24)
            line(cx + u * 0.04, cy - u * 0.31, cx + u * 0.04, cy - u * 0.24)
            ctx.lineWidth = lw
            rrect(cx - u * 0.23, cy - u * 0.18, u * 0.46, u * 0.54, u * 0.09)
            ctx.stroke()
            ctx.fillStyle = glyph.accent
            disc(cx, cy + u * 0.20, lw * 0.6)
            ctx.fillStyle = glyph.tint
            break
        }

        case "bluetooth": {
            // The rune, as one stroke. Drawn rather than taken from the ✱/🔵
            // the pages used, which are not in the shipped font.
            const s = u * 0.32
            ctx.beginPath()
            ctx.moveTo(cx - s * 0.62, cy - s * 0.5)
            ctx.lineTo(cx + s * 0.62, cy + s * 0.5)
            ctx.lineTo(cx,            cy + s)
            ctx.lineTo(cx,            cy - s)
            ctx.lineTo(cx + s * 0.62, cy - s * 0.5)
            ctx.lineTo(cx - s * 0.62, cy + s * 0.5)
            ctx.stroke()
            break
        }

        case "music": {
            // Eighth note. The head is an ellipse via a scaled arc — Context2D
            // does have ellipse(), but it is a Qt extension.
            ctx.save()
            ctx.translate(cx - u * 0.13, cy + u * 0.22)
            ctx.rotate(-0.34)
            ctx.scale(1.0, 0.74)
            ctx.beginPath()
            ctx.arc(0, 0, u * 0.155, 0, Math.PI * 2)
            ctx.fill()
            ctx.restore()

            line(cx + u * 0.02, cy + u * 0.22, cx + u * 0.02, cy - u * 0.31)
            ctx.beginPath()
            ctx.moveTo(cx + u * 0.02, cy - u * 0.31)
            ctx.quadraticCurveTo(cx + u * 0.30, cy - u * 0.24,
                                 cx + u * 0.24, cy - u * 0.02)
            ctx.stroke()
            break
        }

        case "film": {
            // A frame with a play mark in it. A filmstrip with sprocket holes
            // is the more literal icon and turns to mush at row size.
            rrect(cx - u * 0.36, cy - u * 0.28, u * 0.72, u * 0.56, u * 0.09)
            ctx.stroke()
            ctx.fillStyle = glyph.accent
            ctx.beginPath()
            ctx.moveTo(cx - u * 0.09, cy - u * 0.15)
            ctx.lineTo(cx + u * 0.19, cy)
            ctx.lineTo(cx - u * 0.09, cy + u * 0.15)
            ctx.closePath()
            ctx.fill()
            ctx.fillStyle = glyph.tint
            break
        }

        case "warning": {
            ctx.beginPath()
            ctx.moveTo(cx, cy - u * 0.34)
            ctx.lineTo(cx + u * 0.37, cy + u * 0.29)
            ctx.lineTo(cx - u * 0.37, cy + u * 0.29)
            ctx.closePath()
            ctx.stroke()
            ctx.strokeStyle = glyph.accent
            ctx.fillStyle = glyph.accent
            line(cx, cy - u * 0.11, cx, cy + u * 0.07)
            disc(cx, cy + u * 0.18, lw * 0.55)
            ctx.strokeStyle = glyph.tint
            ctx.fillStyle = glyph.tint
            break
        }

        case "close":
            line(cx - u * 0.22, cy - u * 0.22, cx + u * 0.22, cy + u * 0.22)
            line(cx + u * 0.22, cy - u * 0.22, cx - u * 0.22, cy + u * 0.22)
            break

        default:
            ring(cx, cy, u * 0.28)
            break
        }
    }
}
