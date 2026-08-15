import QtQuick

/*
 * Round accent button for the media transport bars.
 *
 * The radio, audio and video pages had grown four near-identical versions of
 * this between them, and they had already drifted — different hover alphas,
 * different hover scales, one with no pressed state at all. One component with
 * a diameter keeps the three bars looking like the same bar.
 *
 * Carries either a bitmap glyph (`iconSource`, for the shipped play/pause/next
 * PNGs) or a short label (`label`, for the speed readout). An icon wins where
 * both are given.
 */
Rectangle {
    id: button

    property color accent: "#4a9eff"
    property real  diameter: 32
    property real  ringWidth: 1
    property real  iconScale: 0.5
    property url   iconSource
    // A MediaGlyph kind, for the buttons with no shipped PNG (the close cross).
    property string glyph: ""
    property alias label: labelText.text
    property real  labelSize: 13

    // Dims and stops responding, for a control with nothing to act on.
    property bool  enabledLook: true

    // Backing at rest. Glass by default, which works on a glass bar; a button
    // that sits over video has to bring its own contrast, because 5% white over
    // a bright frame is nothing at all.
    property color baseColor: Qt.rgba(1, 1, 1, 0.05)

    signal clicked()

    width: diameter
    height: diameter
    radius: diameter / 2
    opacity: enabledLook ? 1.0 : 0.4

    color: !enabledLook          ? baseColor
         : area.pressed          ? Qt.rgba(accent.r, accent.g, accent.b, 0.50)
         : area.containsMouse    ? Qt.rgba(accent.r, accent.g, accent.b, 0.35)
                                 : baseColor
    border.color: accent
    border.width: ringWidth
    scale: (area.containsMouse && enabledLook) ? 1.06 : 1

    Behavior on color   { ColorAnimation  { duration: 150 } }
    Behavior on scale   { NumberAnimation { duration: 150 } }
    Behavior on opacity { NumberAnimation { duration: 150 } }

    Image {
        anchors.centerIn: parent
        width: button.diameter * button.iconScale
        height: width
        source: button.iconSource
        visible: String(button.iconSource) !== ""
        fillMode: Image.PreserveAspectFit
        // The PNGs are larger than they are drawn at; without this they alias
        // badly on the 1024×600 panel.
        mipmap: true
    }

    MediaGlyph {
        anchors.centerIn: parent
        width: button.diameter * button.iconScale
        height: width
        kind: button.glyph
        tint: "#ffffff"
        visible: button.glyph !== ""
    }

    Text {
        id: labelText
        anchors.centerIn: parent
        visible: String(button.iconSource) === "" && button.glyph === "" && text !== ""
        color: "#ffffff"
        font { pixelSize: button.labelSize; family: "Arial"; bold: true }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabledLook
        onClicked: button.clicked()
    }
}
