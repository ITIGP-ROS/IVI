import QtQuick

/*
 * One file in a media library list.
 *
 * The audio and video pages had four copies of this delegate between them —
 * local audio, USB audio, local video, USB video — differing only in which
 * emoji they put on the left and which player property they compared against.
 * They had already drifted apart in row height and hover colour.
 *
 * The caller supplies `active` / `playing`; this does not know what a
 * MediaPlayer is.
 */
Rectangle {
    id: row

    property color  accent: "#4a9eff"
    property string kind: "music"          // MediaGlyph kind for the tile
    property alias  title: titleText.text
    property string subtitle: ""

    // Loaded in this list, and actually producing sound right now. `playing`
    // implies `active`; the meter only runs for the second.
    property bool   active: false
    property bool   playing: false

    signal clicked()

    implicitHeight: 56
    radius: height / 4

    color: active             ? Qt.rgba(accent.r, accent.g, accent.b, 0.16)
         : area.containsMouse ? Qt.rgba(1, 1, 1, 0.08)
                              : Qt.rgba(1, 1, 1, 0.05)
    border.color: active             ? accent
                : area.containsMouse ? Qt.rgba(accent.r, accent.g, accent.b, 0.45)
                                     : Qt.rgba(1, 1, 1, 0.12)
    border.width: active ? 2 : 1

    Behavior on color        { ColorAnimation { duration: 140 } }
    Behavior on border.color { ColorAnimation { duration: 160 } }

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: parent.height * 0.5
        radius: 2
        color: row.accent
        opacity: row.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: parent.height * 0.22
        anchors.rightMargin: parent.height * 0.28

        Rectangle {
            id: tile
            width: parent.height * 0.58
            height: width
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            radius: width * 0.28
            color: row.active ? Qt.rgba(row.accent.r, row.accent.g, row.accent.b, 0.18)
                              : Qt.rgba(1, 1, 1, 0.05)
            border.color: row.active
                          ? Qt.rgba(row.accent.r, row.accent.g, row.accent.b, 0.6)
                          : Qt.rgba(1, 1, 1, 0.12)
            border.width: 1

            MediaGlyph {
                anchors.centerIn: parent
                width: parent.width * 0.54
                height: width
                kind: row.kind
                tint: row.active ? row.accent : "#8899bb"
                accent: row.active ? row.accent : "#8899bb"
            }
        }

        LevelMeter {
            id: meter
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            width: parent.height * 0.26
            height: width * 0.8
            tint: row.accent
            visible: row.playing
            running: visible
        }

        Column {
            anchors.left: tile.right
            anchors.leftMargin: parent.height * 0.22
            anchors.right: meter.visible ? meter.left : parent.right
            anchors.rightMargin: parent.height * 0.20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                id: titleText
                width: parent.width
                color: row.active ? row.accent : "#ffffff"
                font { pixelSize: row.height * 0.29; family: "Arial"; bold: row.active }
                elide: Text.ElideRight
                // Pinned left: an RTL filename otherwise drifts to the far edge
                // and detaches from its tile.
                horizontalAlignment: Text.AlignLeft
            }

            Text {
                width: parent.width
                text: row.subtitle
                visible: text !== ""
                color: "#8899bb"
                font { pixelSize: row.height * 0.21; family: "Arial" }
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: row.clicked()
    }
}
