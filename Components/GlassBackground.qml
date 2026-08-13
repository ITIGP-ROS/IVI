import QtQuick

/*
 * The home screen's backdrop, factored out so every other page can sit on the
 * same one.
 *
 * Three layers: a near-black base, a cool navy gradient over it, and two large
 * coloured orbs drifting behind the content. The orbs are what stop the page
 * reading as a flat dark rectangle — they put a slow, off-centre light source
 * behind the glass so the panes have something to be translucent *against*.
 */
Rectangle {
    id: bg

    color: "#020408"

    // Overridable so a page can tint its own atmosphere — the ambient light
    // page follows the cabin colour — without forking the file.
    property color orbA: "#1a3a5c"
    property color orbB: "#2d1b4e"
    property real  orbAStrength: 0.42
    property real  orbBStrength: 0.36

    // The drift costs two running animations for the whole page. Off for
    // anything already spending its frame budget on 3D or video.
    property bool animated: true

    /*
     * A soft light blob, built from concentric discs rather than a radial
     * gradient.
     *
     * Qt5Compat's RadialGradient is the obvious tool and was tried first: on
     * this Qt it paints its whole bounding box flat, which put two visible
     * rectangles on the page. Stacked discs at a low alpha each need no shader,
     * no offscreen target and no compat module, and at this size the steps are
     * invisible — what you see is the accumulated alpha, densest at the centre.
     */
    component Orb: Item {
        id: orb
        property color tint: "#ffffff"
        property real  strength: 0.3
        // More rings than looks necessary: at six the steps between them were
        // visible as concentric bands, most of all under a saturated tint.
        readonly property int rings: 14

        Repeater {
            model: orb.rings
            Rectangle {
                required property int index
                anchors.centerIn: parent
                width: orb.width * (1.0 - index * 0.068)
                height: width
                radius: width / 2
                color: orb.tint
                opacity: orb.strength / orb.rings
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0a1628" }
            GradientStop { position: 0.5; color: "#080e1c" }
            GradientStop { position: 1.0; color: "#05070a" }
        }
    }

    Orb {
        x: parent.width * 0.2
        y: parent.height * 0.3
        width: 340; height: 340
        tint: bg.orbA
        strength: bg.orbAStrength

        SequentialAnimation on x {
            running: bg.animated
            loops: Animation.Infinite
            NumberAnimation { to: bg.width * 0.25; duration: 8000; easing.type: Easing.InOutSine }
            NumberAnimation { to: bg.width * 0.20; duration: 8000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on y {
            running: bg.animated
            loops: Animation.Infinite
            NumberAnimation { to: bg.height * 0.35; duration: 10000; easing.type: Easing.InOutSine }
            NumberAnimation { to: bg.height * 0.30; duration: 10000; easing.type: Easing.InOutSine }
        }
    }

    Orb {
        x: parent.width * 0.7
        y: parent.height * 0.6
        width: 440; height: 440
        tint: bg.orbB
        strength: bg.orbBStrength

        SequentialAnimation on x {
            running: bg.animated
            loops: Animation.Infinite
            NumberAnimation { to: bg.width * 0.65; duration: 12000; easing.type: Easing.InOutSine }
            NumberAnimation { to: bg.width * 0.70; duration: 12000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on y {
            running: bg.animated
            loops: Animation.Infinite
            NumberAnimation { to: bg.height * 0.55; duration: 9000; easing.type: Easing.InOutSine }
            NumberAnimation { to: bg.height * 0.60; duration: 9000; easing.type: Easing.InOutSine }
        }
    }
}
