import QtQuick

/*
 * The home screen's bento tile, factored out.
 *
 * Four layers, in the order they have to be drawn:
 *
 *   halo   an inflated accent rectangle *behind* the pane. Reads as light
 *          escaping from under the glass; it is what gives each card its own
 *          identity colour without painting the card itself.
 *   pane   1.5–3% white. Almost nothing — the card is a hole you see the
 *          background through, not a surface laid on top of it. This is the
 *          single value that decides whether the page looks like glass.
 *   sheen  lit along the top edge, shaded along the bottom. Fakes a thick
 *          pane catching the light; without it the card is a flat translucent
 *          rectangle no matter how the alpha is tuned.
 *   border a hairline at 12% white, going accent-tinted on hover.
 *
 * Deliberately no DropShadow/InnerShadow. Those need a layer per card, which
 * on the settings row alone was five offscreen render targets — and the drop
 * shadow they produced sat *outside* the pane, giving the cards a hard edge
 * that fights the whole see-through idea.
 *
 * Put content inside as ordinary children; they land in an Item filling the
 * card, above the card-level MouseArea, so nested controls still get their
 * own clicks.
 */
Item {
    id: card

    property color accent: "#4a9eff"
    property real  cardRadius: 28

    // Hover response and the clicked() signal both hang off this, so a card
    // that is a display rather than a button just turns it off.
    property bool  interactive: true

    property bool  showAccentBar: true

    /*
     * Idle drift, in pixels. Off by default: it is one running animation per
     * card, and a whole grid breathing in unison looks like a rendering fault
     * rather than a flourish — stagger `floatPhase` when using it on more than
     * one card at a time.
     */
    property real floatAmplitude: 0
    property int  floatDuration: 4000
    property int  floatPhase: 0

    readonly property bool hovered: interactive && hoverHandler.hovered

    signal clicked()

    default property alias content: body.data

    scale: hovered ? 1.03 : 1.0
    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

    transform: Translate { id: drift }

    // The phase pause sits outside the looping part on purpose: inside, it
    // would replay every cycle and turn the drift into a stutter.
    SequentialAnimation {
        running: card.floatAmplitude > 0
        PauseAnimation { duration: card.floatPhase }
        SequentialAnimation {
            loops: Animation.Infinite
            NumberAnimation {
                target: drift; property: "y"; to: -card.floatAmplitude
                duration: card.floatDuration; easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: drift; property: "y"; to: card.floatAmplitude
                duration: card.floatDuration; easing.type: Easing.InOutSine
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: card.cardRadius + 2
        z: -1
        color: card.accent
        opacity: card.hovered ? 0.18 : 0.07
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    Rectangle {
        id: pane
        anchors.fill: parent
        radius: card.cardRadius
        color: card.hovered ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: card.hovered
                      ? Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.45)
                      : Qt.rgba(1, 1, 1, 0.12)
        Behavior on color        { ColorAnimation { duration: 200 } }
        Behavior on border.color { ColorAnimation { duration: 200 } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.08) }
                GradientStop { position: 0.5; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.08) }
            }
        }
    }

    // Identity stripe. Short, centred and inset from the corner radius so it
    // sits on the pane rather than cutting across its rounded edge.
    Rectangle {
        visible: card.showAccentBar
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.4
        height: 3
        radius: 2
        color: card.accent
        opacity: card.hovered ? 0.95 : 0.7
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // Below `body` in declaration order, so anything interactive placed in the
    // card — a slider, a button — takes the press first and only the bare
    // areas fall through to here.
    MouseArea {
        anchors.fill: parent
        enabled: card.interactive
        onClicked: card.clicked()
    }

    HoverHandler { id: hoverHandler; enabled: card.interactive }

    Item { id: body; anchors.fill: parent }
}
