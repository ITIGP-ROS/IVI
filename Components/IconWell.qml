import QtQuick

/*
 * Round tinted disc behind a card's icon.
 *
 * The icons are flat white PNGs; dropped straight onto glass they float with
 * nothing holding them, and at 24 px they lose against a background that is
 * itself moving. The well gives each one a fixed, accent-tinted seat.
 */
Item {
    id: well

    property color  accent: "#4a9eff"
    property real   diameter: 64
    property url    source
    property real   iconScale: 0.55

    width: diameter
    height: diameter

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(well.accent.r, well.accent.g, well.accent.b, 0.15)
        border.color: Qt.rgba(well.accent.r, well.accent.g, well.accent.b, 0.5)
        border.width: 1
    }

    Image {
        anchors.centerIn: parent
        source: well.source
        width: parent.width * well.iconScale
        height: parent.height * well.iconScale
        fillMode: Image.PreserveAspectFit
        // Bitmap assets scaled down from their native size alias badly on the
        // 1024×600 panel without this.
        mipmap: true
    }
}
