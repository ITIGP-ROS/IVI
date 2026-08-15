import QtQuick
import QtQuick.Controls

/*
 * The app's slider: a sunk groove, an accent-gradient fill and a white knob.
 *
 * Sunk rather than glass on purpose — a groove you drag a handle along is one
 * of the few things on these pages that *should* look like a hole rather than
 * like a pane you can see through.
 *
 * The caller still owns behaviour (`from`, `to`, `value`, `onMoved`); this only
 * carries the look, which the media and settings pages had six copies of.
 */
Slider {
    id: control

    property color accent: "#4a9eff"
    property real  handleSize: 12
    property real  grooveHeight: 6

    // For a progress bar with nothing loaded: the groove still reads as a
    // scale, but there is no knob to grab.
    property bool  showHandle: true

    /*
     * Hit area, which is not the same thing as the drawing.
     *
     * A Control derives its implicit size from `implicitBackgroundHeight` and
     * `implicitHandleHeight` — and those come from the *implicit* size of
     * whatever is assigned to `background` and `handle`. Assign plain
     * Rectangles that set width/height and both read zero, so the slider ends
     * up 0 px tall. It still draws, because a zero-height Item does not clip
     * its children, but it has no area to press: every volume and speed slider
     * in the media pages looked fine and could not be dragged at all.
     *
     * So the control is deliberately taller than it looks. The groove and knob
     * stay centred inside it, and 44 px is a target a finger can find in a
     * moving car.
     */
    property real touchHeight: 44

    implicitWidth: 140
    implicitHeight: Math.max(touchHeight, handleSize, grooveHeight)

    background: Rectangle {
        // Only a fallback for a caller that sizes nothing; the explicit
        // width/height below still drive what is painted.
        implicitWidth: 140
        implicitHeight: control.grooveHeight
        x: control.leftPadding
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: control.availableWidth
        height: control.grooveHeight
        radius: height / 2
        color: "#0a1220"
        border.color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1

        Rectangle {
            width: control.visualPosition * parent.width
            height: parent.height
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(control.accent.r, control.accent.g, control.accent.b, 0.45)
                }
                GradientStop { position: 1.0; color: control.accent }
            }
        }
    }

    handle: Rectangle {
        implicitWidth: control.handleSize
        implicitHeight: control.handleSize
        x: control.leftPadding
           + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: control.handleSize
        height: control.handleSize
        radius: width / 2
        visible: control.showHandle
        color: control.pressed ? control.accent : "#ffffff"
        border.color: control.accent
        border.width: 2
    }
}
