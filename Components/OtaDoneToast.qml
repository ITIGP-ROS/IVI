// OtaDoneToast.qml
//
// "OTA update done." The other half of the OTA conversation: OtaPopup asks,
// this one reports. It appears when OtaManager sees a completion notice in the
// spool (see the COMPLETION NOTICES block in OtaManager.hpp) and takes itself
// away after five seconds.
//
// Everything OtaPopup does to make a decision unavoidable, this deliberately
// does NOT do. No scrim, no dimming, no MouseArea anywhere — the driver is
// being told something, not asked something, so it must not cover the drive
// view and it must not eat a tap meant for whatever is underneath it.
//
// It keeps the prompt's motion, though: the same drop from above the top edge
// to the same inset, so the two read as one family arriving the same way.
import QtQuick

Item {
    id: root

    // `ota` is the OtaManager context property from main.cpp.
    required property var ota

    // False while the splash is up. A notice landing during boot waits rather
    // than spending its five seconds behind the splash clip — same reasoning as
    // the prompt's own splash gate, and the same reason the dwell timer below
    // is started by `showing` rather than by the signal.
    property bool armed: true

    // How far the resting card sits below the top edge. Matches OtaPopup.
    property real topInset: 24

    // Set on a notice, cleared when the dwell runs out.
    property bool pending: false

    // 1 -> 0 across the dwell, drawn as the top stripe draining away. Same
    // device as the prompt's countdown, so a stripe on a card always means the
    // same thing: this is going away by itself.
    property real countdown: 1.0

    readonly property bool showing: root.pending && root.armed

    visible: opacity > 0
    opacity: showing ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    Connections {
        target: root.ota

        function onUpdateCompleted() {
            root.pending = true
            // A second notice arriving while the first is still up gets its own
            // full five seconds instead of inheriting what is left of the
            // previous one. (When `pending` was already false, onShowingChanged
            // below does this; restarting twice is harmless.)
            if (root.showing) dwell.restart()
        }
    }

    // Started by visibility, not by the signal, so the five seconds are five
    // seconds ON SCREEN.
    onShowingChanged: if (root.showing) dwell.restart()

    Timer {
        id: dwell
        interval: 5000
        onTriggered: root.pending = false
    }

    NumberAnimation {
        target: root
        property: "countdown"
        from: 1.0
        to: 0.0
        duration: dwell.interval
        running: dwell.running
    }

    Rectangle {
        id: card
        width: 380
        height: 86
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 24
        color: "#0d1117"
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1

        // Parked above the top edge, far enough that the rounded corners clear
        // the screen too. The "shown" state is what brings it down.
        y: -(height + 48)

        states: State {
            name: "shown"
            when: root.showing && root.visible
            PropertyChanges { card.y: root.topInset }
        }

        // Same asymmetry as the prompt: it overshoots on the way in so it reads
        // as dropping, and simply leaves on the way out.
        transitions: [
            Transition {
                to: "shown"
                NumberAnimation {
                    property: "y"
                    duration: 420
                    easing { type: Easing.OutBack; overshoot: 1.1 }
                }
            },
            Transition {
                from: "shown"
                NumberAnimation {
                    property: "y"
                    duration: 180          // same as the fade, so they end together
                    easing.type: Easing.InCubic
                }
            }
        ]

        Rectangle {
            anchors { top: parent.top; left: parent.left }
            width: parent.width * root.countdown
            height: 3
            radius: 2
            opacity: 0.85
            color: "#21cfa4"
        }

        // Drawn rather than typed, for the reason spelled out in OtaPopup: there
        // is no Arial on the dev laptop or the Yocto image, and the Liberation
        // Sans it falls back to has no U+2713. A tick that renders as a tofu box
        // in the one element saying "this worked" is worse than no tick at all.
        Canvas {
            width: 34
            height: 34
            anchors { left: parent.left; leftMargin: 26; verticalCenter: parent.verticalCenter }
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = "#21cfa4"
                ctx.lineWidth = Math.max(3, width * 0.12)
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(width * 0.20, height * 0.53)
                ctx.lineTo(width * 0.41, height * 0.74)
                ctx.lineTo(width * 0.80, height * 0.28)
                ctx.stroke()
            }
        }

        // One line, deliberately. It used to carry the module name underneath
        // ("Body Control ECU"), which is an audit detail: the driver is being
        // told the car is done updating, and which ECU it was does not change
        // anything they might do about it. The target is still in the journal.
        Text {
            anchors {
                left: parent.left; leftMargin: 74
                right: parent.right; rightMargin: 22
                verticalCenter: parent.verticalCenter
            }
            text: qsTr("OTA update done")
            color: "#ffffff"
            elide: Text.ElideRight
            font { pixelSize: 19; bold: true; family: "Arial" }
        }
    }
}
