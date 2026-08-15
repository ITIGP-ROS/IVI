import QtQuick

/*
 * GlassCard's sibling, for surfaces that sit on top of a live scene.
 *
 * Same four layers — halo, pane, sheen, hairline — but the pane is INK, not
 * white. On the settings pages the glass is 5% white over a near-black page,
 * and that works because the page behind it is dark and still. Over Drive View
 * the background is a lit road that changes every frame: white at 5% vanishes
 * against pale tarmac, and any text on it goes with it. A dark translucent pane
 * does the opposite — it holds its contrast wherever the camera points, and
 * still shows the road moving underneath.
 *
 * So: the app's shape language and accent behaviour, inverted fill.
 */
Item {
    id: panel

    property color accent: "#4a9eff"
    property real  cardRadius: 18

    // Raise toward 1.0 where legibility matters more than seeing through —
    // the speed readout is the driver's instrument, the legend is not.
    property real inkAlpha: 0.72

    property bool interactive: false
    property bool showAccentBar: false

    readonly property bool hovered: interactive && hoverHandler.hovered

    signal clicked()

    default property alias content: body.data

    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: panel.cardRadius + 2
        z: -1
        color: panel.accent
        opacity: panel.hovered ? 0.22 : 0.10
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    Rectangle {
        anchors.fill: parent
        radius: panel.cardRadius
        color: Qt.rgba(0.02, 0.04, 0.08,
                       panel.hovered ? Math.min(1.0, panel.inkAlpha + 0.10)
                                     : panel.inkAlpha)
        border.width: 1
        border.color: panel.hovered
                      ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.55)
                      : Qt.rgba(1, 1, 1, 0.14)
        Behavior on color        { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        // Lit along the top edge. The one thing that separates a pane of glass
        // from a rectangle of paint, and it survives being this dark.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 0.45; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.10) }
            }
        }
    }

    Rectangle {
        visible: panel.showAccentBar
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.36
        height: 2
        radius: 1
        color: panel.accent
        opacity: panel.hovered ? 0.95 : 0.7
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: panel.interactive
        hoverEnabled: panel.interactive
        cursorShape: panel.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: panel.clicked()
    }

    HoverHandler { id: hoverHandler; enabled: panel.interactive }

    Item { id: body; anchors.fill: parent }
}
