pragma ComponentBehavior: Bound
import QtQuick

/*
 * Three bouncing bars, marking the one row that is actually playing.
 *
 * Not a real level meter — nothing here is reading the audio. It is a "this is
 * the live one" mark, which at row size is what it needs to be; a highlight
 * colour alone does not survive a glance from the driver's seat.
 *
 * Cheap because only one row ever has it running, and it stops dead with
 * playback.
 */
Item {
    id: meter

    property color tint: "#ffffff"
    property bool  running: true
    property int   bars: 3

    implicitWidth: 16
    implicitHeight: 12

    Repeater {
        model: meter.bars

        Rectangle {
            id: bar
            required property int index

            readonly property real slot: meter.width / (meter.bars * 1.75 - 0.75)

            x: bar.index * bar.slot * 1.75
            width: bar.slot
            // Sat on the baseline by arithmetic rather than
            // `anchors.bottom: parent.bottom`: the anchor re-evaluates while a
            // list row is being torn down, when `parent` is already null, and
            // clearing a list is a routine event on these pages.
            y: meter.height - height
            height: meter.height * 0.35
            radius: width / 2
            color: meter.tint

            /*
             * The stagger sits in a PauseAnimation *outside* the looping part.
             * Inside, it replays every cycle and the bars stutter instead of
             * running.
             */
            SequentialAnimation on height {
                running: meter.running
                PauseAnimation { duration: bar.index * 130 }
                SequentialAnimation {
                    loops: Animation.Infinite
                    NumberAnimation { to: meter.height;        duration: 340; easing.type: Easing.InOutSine }
                    NumberAnimation { to: meter.height * 0.28; duration: 340; easing.type: Easing.InOutSine }
                }
            }
        }
    }
}
