import QtQuick

/*
 * The "leave this page" pill at the foot of every media page's left rail.
 *
 * Outlined in the danger colour rather than the page accent: it is the one
 * control on the rail that discards where you are, and it reads the same on all
 * three pages so it can be hit without looking.
 */
Rectangle {
    id: button

    property alias label: labelText.text
    property color accent: "#ff5c5c"
    property real  fontSize: 18

    signal clicked()

    implicitWidth: labelText.implicitWidth * 2.5
    implicitHeight: labelText.implicitHeight * 1.6
    radius: height / 1.5

    color: area.pressed       ? Qt.rgba(accent.r, accent.g, accent.b, 0.55)
         : area.containsMouse ? Qt.rgba(accent.r, accent.g, accent.b, 0.40)
                              : Qt.rgba(1, 1, 1, 0.05)
    border.color: accent
    border.width: 1
    Behavior on color { ColorAnimation { duration: 150 } }

    Text {
        id: labelText
        anchors.centerIn: parent
        text: "Back"
        color: "#ffffff"
        font { pixelSize: button.fontSize; family: "Arial"; bold: true }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: button.clicked()
    }
}
