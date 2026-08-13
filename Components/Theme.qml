pragma Singleton
import QtQuick

/*
 * One place for the colours the home screen established, so the rest of the UI
 * can be moved onto them page by page without every file inventing its own
 * near-black or its own blue.
 *
 * Values are lifted from Main.qml and OtaPopup.qml rather than picked fresh —
 * the point is to match what already ships, not to introduce a sixth palette.
 *
 * Nothing here is a component: a page that wants the backdrop uses
 * GlassBackground, a tile uses GlassCard, and this only holds the numbers those
 * two and the pages agree on.
 */
QtObject {
    // ---- backdrop
    readonly property color base:        "#020408"
    readonly property color gradientTop: "#0a1628"
    readonly property color gradientMid: "#080e1c"
    readonly property color gradientBot: "#05070a"

    // ---- surfaces
    // Dialogs and flyouts. Nearly opaque on purpose: a modal that is see-through
    // over an animated background is unreadable, whatever it costs in prettiness.
    readonly property color surface:      "#0d1117"
    readonly property color surfaceSunk:  "#0a1220"   // slider tracks, input wells
    readonly property color scrim:        Qt.rgba(0.02, 0.04, 0.08, 0.88)

    // ---- glass
    // The three alphas the whole look rests on. Raising `glassFill` past ~0.10
    // is what turns a glass UI back into a grey-panel UI.
    readonly property color glassFill:       Qt.rgba(1, 1, 1, 0.05)
    readonly property color glassFillHover:  Qt.rgba(1, 1, 1, 0.08)
    readonly property color glassBorder:     Qt.rgba(1, 1, 1, 0.12)
    readonly property color glassBorderSoft: Qt.rgba(1, 1, 1, 0.08)

    // ---- accents
    // One hue per function, so a card is recognisable by its glow alone.
    readonly property color accentBlue:   "#4a9eff"   // primary / navigation
    readonly property color accentCyan:   "#36a9de"   // network, weather
    readonly property color accentMint:   "#21cfa4"   // media, audio
    readonly property color accentAmber:  "#f7c45f"   // brightness
    readonly property color accentViolet: "#a78bfa"   // ambient light
    readonly property color success:      "#3ad07a"
    readonly property color danger:       "#ff5c5c"

    // ---- text
    readonly property color textPrimary:   "#ffffff"
    readonly property color textSecondary: "#8899bb"
    readonly property color textMuted:     "#6677aa"
    readonly property color textOnAccent:  "#aaccff"

    // ---- shape
    readonly property real cardRadius:   28
    readonly property real dialogRadius: 24
    readonly property real chipRadius:   12

    // Tint helper: the same accent at an arbitrary alpha, which is most of what
    // the pages actually need it for (icon wells, pressed states, hover fills).
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
}
