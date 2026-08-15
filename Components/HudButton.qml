import QtQuick

/*
 * Drive View's HUD buttons — SETTINGS, RESET VIEW, TOP VIEW.
 *
 * A HudPanel that reacts: the accent halo comes up under the finger and the
 * border takes the accent, which is the same feedback the settings cards give.
 * Before this the buttons only nudged their own opacity, which on a moving
 * background is not a signal at all — the panel appears to change because the
 * road behind it did.
 */
HudPanel {
    id: button

    property alias text: label.text
    property real  fontSize: 12
    property color textColor: "#f2f5f8"

    interactive: true
    inkAlpha: 0.78

    Text {
        id: label
        anchors.centerIn: parent
        width: parent.width * 0.9
        height: implicitHeight
        color: button.hovered ? button.accent : button.textColor
        font.pixelSize: button.fontSize
        font.letterSpacing: 1.2
        font.bold: true
        font.family: "monospace"
        horizontalAlignment: Text.AlignHCenter
        // The HUD scales with the window and these labels are fixed strings;
        // shrinking beats eliding, which would leave "RESET VIE…".
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 8
        Behavior on color { ColorAnimation { duration: 150 } }
    }
}
