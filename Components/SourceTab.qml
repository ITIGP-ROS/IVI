import QtQuick

/*
 * One entry in a media page's left rail — Local / Bluetooth / USB.
 *
 * Takes either a MediaGlyph `kind` or a bitmap `iconSource`, because the
 * Bluetooth mark already ships as a PNG that matches the rest of the app while
 * the others were emoji with no glyph in the shipped font.
 */
Rectangle {
    id: tab

    property color  accent: "#4a9eff"
    property string kind: ""
    property url    iconSource
    property alias  label: labelText.text
    property bool   selected: false
    property real   fontSize: 15

    signal clicked()

    implicitWidth: 160
    implicitHeight: 44
    radius: height / 3

    color: selected           ? Qt.rgba(accent.r, accent.g, accent.b, 0.22)
         : area.containsMouse ? Qt.rgba(1, 1, 1, 0.08)
                              : Qt.rgba(1, 1, 1, 0.05)
    border.color: selected ? accent : Qt.rgba(1, 1, 1, 0.12)
    border.width: selected ? 2 : 1

    Behavior on color        { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    // Identity stripe down the leading edge of the selected tab, the same mark
    // the station rows use, so "this one is active" means one thing everywhere.
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: parent.height * 0.45
        radius: 1.5
        color: tab.accent
        opacity: tab.selected ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: parent.height * 0.42
        anchors.right: parent.right
        anchors.rightMargin: parent.height * 0.25
        spacing: parent.height * 0.28

        MediaGlyph {
            anchors.verticalCenter: parent.verticalCenter
            width: tab.height * 0.44
            height: width
            kind: tab.kind
            tint: tab.selected ? tab.accent : "#8899bb"
            visible: tab.kind !== ""
        }

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: tab.height * 0.42
            height: width
            source: tab.iconSource
            visible: String(tab.iconSource) !== ""
            fillMode: Image.PreserveAspectFit
            mipmap: true
        }

        Text {
            id: labelText
            anchors.verticalCenter: parent.verticalCenter
            color: tab.selected ? tab.accent : "#ffffff"
            font { pixelSize: tab.fontSize; family: "Arial"; bold: tab.selected }
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: tab.clicked()
    }
}
