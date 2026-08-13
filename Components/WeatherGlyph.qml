import QtQuick

/*
 * Weather and metric icons, drawn on a Canvas.
 *
 * The page used to draw all of these with emoji — ☀️ 🌧️ ⛈️ 💨 💧 🧭 — in a Text
 * with `family: "Arial"`. There is no Arial on the dev laptop or in the Yocto
 * image, so that resolves to Liberation Sans, which has none of those
 * codepoints: every icon on the weather page rendered as a tofu box. Shipping a
 * colour-emoji font would fix the boxes and hand the page's whole look to
 * whatever that font's house style happens to be.
 *
 * So they are strokes instead. No font dependency, no glyph coverage to check,
 * they take the page's accent colours, and they stay sharp at any size on the
 * 1024×600 panel.
 *
 * `kind` takes either a weather condition ("clear-day", "rain", …) or a metric
 * ("wind", "humidity", …); they live in one component because they are the same
 * kind of object to a caller — a square that draws itself in a given colour.
 */
Canvas {
    id: glyph

    property string kind: "clear-day"
    property color  tint: "#ffffff"

    // Secondary colour, used where a glyph has two parts worth separating: the
    // sun behind a cloud, the rain under it. Defaults to `tint`, so a caller
    // that does not care gets a single-colour icon.
    property color  accent: tint

    // Multiplier on the derived stroke width, for the rare caller that wants a
    // heavier or lighter version of the same drawing.
    property real   weight: 1.0

    implicitWidth: 64
    implicitHeight: 64

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
        const lw = Math.max(1.6, u * 0.075) * glyph.weight
        ctx.lineWidth = lw
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.strokeStyle = glyph.tint
        ctx.fillStyle = glyph.tint

        // ---- primitives -----------------------------------------------------

        function disc(cx, cy, r) {
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.fill()
        }

        function ring(cx, cy, r) {
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()
        }

        function line(x1, y1, x2, y2) {
            ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
        }

        // Sun: a disc with rays clear of it, so the two never merge into a blob.
        function sun(cx, cy, r, rays) {
            disc(cx, cy, r)
            if (!rays) return
            const inner = r * 1.45, outer = r * 2.05
            for (let i = 0; i < 8; i++) {
                const a = i * Math.PI / 4
                line(cx + Math.cos(a) * inner, cy + Math.sin(a) * inner,
                     cx + Math.cos(a) * outer, cy + Math.sin(a) * outer)
            }
        }

        /*
         * Crescent: a filled disc with a second disc punched out of it.
         *
         * destination-out rather than two arcs joined into one path — the arc
         * pair needs its start and end angles kept in agreement with the offset,
         * and gets it subtly wrong (a lumpy tip) the moment either is tweaked.
         * Safe here because the canvas holds nothing but this glyph, and every
         * caller that layers something over a moon draws it after this returns.
         */
        function moon(cx, cy, r) {
            disc(cx, cy, r)
            ctx.save()
            ctx.globalCompositeOperation = "destination-out"
            disc(cx - r * 0.40, cy - r * 0.34, r * 0.88)
            ctx.restore()
        }

        // Cloud: three discs and a bar, unioned by overlap. Filled rather than
        // outlined because an outlined cloud at 40 px is mostly outline.
        function cloud(cx, cy, w) {
            const r = w * 0.30
            disc(cx - w * 0.24, cy + r * 0.22, r * 0.82)
            disc(cx + w * 0.02, cy - r * 0.30, r * 1.05)
            disc(cx + w * 0.27, cy + r * 0.20, r * 0.76)
            ctx.beginPath()
            ctx.rect(cx - w * 0.30, cy + r * 0.10, w * 0.60, r * 0.92)
            ctx.fill()
        }

        // Slanted streaks under a cloud. `n` of them, spread across `w`.
        function streaks(cx, cy, w, n, len) {
            ctx.strokeStyle = glyph.accent
            ctx.lineWidth = lw * 0.85
            for (let i = 0; i < n; i++) {
                const x = cx - w * 0.28 + (w * 0.56) * (n === 1 ? 0.5 : i / (n - 1))
                line(x + len * 0.22, cy, x - len * 0.14, cy + len)
            }
            ctx.strokeStyle = glyph.tint
            ctx.lineWidth = lw
        }

        function flakes(cx, cy, w, n, r) {
            ctx.strokeStyle = glyph.accent
            ctx.lineWidth = lw * 0.7
            for (let i = 0; i < n; i++) {
                const x = cx - w * 0.26 + (w * 0.52) * (n === 1 ? 0.5 : i / (n - 1))
                const y = cy + r
                for (let k = 0; k < 3; k++) {
                    const a = k * Math.PI / 3
                    line(x - Math.cos(a) * r, y - Math.sin(a) * r,
                         x + Math.cos(a) * r, y + Math.sin(a) * r)
                }
            }
            ctx.strokeStyle = glyph.tint
            ctx.lineWidth = lw
        }

        function bolt(cx, cy, h) {
            ctx.fillStyle = glyph.accent
            ctx.beginPath()
            ctx.moveTo(cx + h * 0.20, cy)
            ctx.lineTo(cx - h * 0.16, cy + h * 0.52)
            ctx.lineTo(cx + h * 0.02, cy + h * 0.52)
            ctx.lineTo(cx - h * 0.14, cy + h)
            ctx.lineTo(cx + h * 0.26, cy + h * 0.42)
            ctx.lineTo(cx + h * 0.04, cy + h * 0.42)
            ctx.closePath()
            ctx.fill()
            ctx.fillStyle = glyph.tint
        }

        // ---- the glyphs -----------------------------------------------------

        const cx = width / 2, cy = height / 2

        switch (glyph.kind) {

        case "clear-day":
            sun(cx, cy, u * 0.20, true)
            break

        case "clear-night":
            moon(cx + u * 0.05, cy, u * 0.30)
            // Two stars, off the crescent's open side so they do not crowd it.
            disc(cx - u * 0.28, cy - u * 0.24, u * 0.035)
            disc(cx - u * 0.20, cy + u * 0.26, u * 0.025)
            break

        case "partly-day":
            ctx.fillStyle = glyph.accent
            sun(cx + u * 0.17, cy - u * 0.19, u * 0.145, true)
            ctx.fillStyle = glyph.tint
            cloud(cx - u * 0.06, cy + u * 0.12, u * 0.66)
            break

        case "partly-night":
            ctx.fillStyle = glyph.accent
            moon(cx + u * 0.19, cy - u * 0.18, u * 0.19)
            ctx.fillStyle = glyph.tint
            cloud(cx - u * 0.06, cy + u * 0.12, u * 0.66)
            break

        case "overcast":
            // The back cloud is dimmer so the pair reads as depth, not as one
            // wide shape with a notch in it.
            ctx.globalAlpha = 0.45
            cloud(cx + u * 0.10, cy - u * 0.14, u * 0.54)
            ctx.globalAlpha = 1.0
            cloud(cx - u * 0.06, cy + u * 0.09, u * 0.68)
            break

        case "fog":
            cloud(cx, cy - u * 0.12, u * 0.66)
            ctx.strokeStyle = glyph.accent
            for (let i = 0; i < 3; i++) {
                const y = cy + u * (0.22 + i * 0.13)
                const inset = i === 1 ? u * 0.06 : 0
                line(cx - u * 0.30 + inset, y, cx + u * 0.30 - inset, y)
            }
            ctx.strokeStyle = glyph.tint
            break

        case "drizzle":
            cloud(cx, cy - u * 0.13, u * 0.66)
            streaks(cx, cy + u * 0.22, u, 3, u * 0.13)
            break

        case "rain":
            cloud(cx, cy - u * 0.13, u * 0.66)
            streaks(cx, cy + u * 0.20, u, 3, u * 0.22)
            break

        case "showers":
            ctx.fillStyle = glyph.accent
            sun(cx + u * 0.20, cy - u * 0.24, u * 0.115, true)
            ctx.fillStyle = glyph.tint
            cloud(cx - u * 0.05, cy - u * 0.06, u * 0.60)
            streaks(cx - u * 0.05, cy + u * 0.24, u, 3, u * 0.17)
            break

        case "snow":
            cloud(cx, cy - u * 0.14, u * 0.66)
            flakes(cx, cy + u * 0.20, u, 3, u * 0.075)
            break

        case "thunder":
            cloud(cx, cy - u * 0.17, u * 0.66)
            bolt(cx, cy + u * 0.10, u * 0.34)
            break

        // ---- metrics --------------------------------------------------------

        case "wind": {
            // Three flow lines, each ending in a curl, at different lengths so
            // it reads as moving air rather than as a hamburger menu.
            const ys = [-0.20, 0.02, 0.24]
            const ws = [0.30, 0.36, 0.24]
            for (let i = 0; i < 3; i++) {
                const y = cy + u * ys[i]
                ctx.beginPath()
                ctx.moveTo(cx - u * 0.32, y)
                ctx.lineTo(cx + u * ws[i], y)
                ctx.arc(cx + u * ws[i], y - u * 0.09, u * 0.09,
                        Math.PI * 0.5, Math.PI * 1.6)
                ctx.stroke()
            }
            break
        }

        case "humidity": {
            // Droplet: a point at the top, shoulders bowing out, closed by a
            // near-circular base.
            const r = u * 0.24, top = cy - u * 0.34
            ctx.beginPath()
            ctx.moveTo(cx, top)
            ctx.bezierCurveTo(cx + r * 1.25, top + r * 1.15,
                              cx + r,        cy + r * 0.30,
                              cx,            cy + r * 0.95)
            ctx.bezierCurveTo(cx - r,        cy + r * 0.30,
                              cx - r * 1.25, top + r * 1.15,
                              cx,            top)
            ctx.closePath()
            ctx.fill()
            break
        }

        case "compass": {
            ring(cx, cy, u * 0.33)
            // Needle: the lit half in the accent, the tail in the base colour,
            // so the direction is readable at tile size.
            ctx.fillStyle = glyph.accent
            ctx.beginPath()
            ctx.moveTo(cx, cy - u * 0.24)
            ctx.lineTo(cx + u * 0.11, cy + u * 0.04)
            ctx.lineTo(cx, cy)
            ctx.closePath(); ctx.fill()
            ctx.fillStyle = glyph.tint
            ctx.beginPath()
            ctx.moveTo(cx, cy + u * 0.24)
            ctx.lineTo(cx - u * 0.11, cy - u * 0.04)
            ctx.lineTo(cx, cy)
            ctx.closePath(); ctx.fill()
            break
        }

        case "pressure": {
            // Gauge: an open dial with tick marks and a hand.
            ctx.beginPath()
            ctx.arc(cx, cy + u * 0.08, u * 0.30, Math.PI * 1.15, Math.PI * 1.85)
            ctx.stroke()
            for (let i = 0; i <= 4; i++) {
                const a = Math.PI * (1.15 + 0.175 * i)
                line(cx + Math.cos(a) * u * 0.30, cy + u * 0.08 + Math.sin(a) * u * 0.30,
                     cx + Math.cos(a) * u * 0.22, cy + u * 0.08 + Math.sin(a) * u * 0.22)
            }
            ctx.strokeStyle = glyph.accent
            line(cx, cy + u * 0.08, cx + u * 0.17, cy - u * 0.12)
            ctx.strokeStyle = glyph.tint
            disc(cx, cy + u * 0.08, u * 0.055)
            break
        }

        case "search":
            ring(cx - u * 0.06, cy - u * 0.06, u * 0.22)
            line(cx + u * 0.10, cy + u * 0.10, cx + u * 0.28, cy + u * 0.28)
            break

        case "refresh": {
            // Open circle with an arrowhead, i.e. the usual reload mark.
            const r = u * 0.28
            ctx.beginPath()
            ctx.arc(cx, cy, r, Math.PI * 0.35, Math.PI * 1.95)
            ctx.stroke()
            const a = Math.PI * 0.35
            const ax = cx + Math.cos(a) * r, ay = cy + Math.sin(a) * r
            ctx.beginPath()
            ctx.moveTo(ax + u * 0.13, ay - u * 0.02)
            ctx.lineTo(ax - u * 0.02, ay + u * 0.10)
            ctx.lineTo(ax + u * 0.02, ay - u * 0.10)
            ctx.closePath(); ctx.fill()
            break
        }

        default:
            ring(cx, cy, u * 0.28)
            break
        }
    }
}
