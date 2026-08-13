import QtQuick

/*
 * Pill button for use on top of a GlassCard.
 *
 * Outlined rather than filled: a solid button on a translucent card is the one
 * element that gives the whole illusion away, because it is the only thing on
 * the pane that light plainly does not pass through. The fill only appears
 * under the finger.
 */
Item {
    id: button

    property color  accent: "#4a9eff"
    property alias  text: label.text
    property real   fontSize: 13
    property bool   enabledLook: true

    signal clicked()

    implicitWidth: 120
    implicitHeight: 34

    opacity: enabledLook ? 1.0 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: area.pressed  ? Qt.rgba(button.accent.r, button.accent.g, button.accent.b, 0.30)
             : area.containsMouse ? Qt.rgba(button.accent.r, button.accent.g, button.accent.b, 0.15)
                                  : "transparent"
        border.color: Qt.rgba(button.accent.r, button.accent.g, button.accent.b,
                              area.containsMouse ? 0.9 : 0.6)
        border.width: 1
        Behavior on color        { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }

    Text {
        id: label
        anchors.centerIn: parent
        color: "#ffffff"
        font { pixelSize: button.fontSize; family: "Arial"; bold: true }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabledLook
        onClicked: button.clicked()
    }
}
