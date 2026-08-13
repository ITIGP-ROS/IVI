// OtaPopup.qml
//
// The approval prompt for an over-the-air update. Something on the vehicle is
// asking permission to install firmware; this is where a human answers.
//
// Deliberately bare: a title and two buttons. The offer carries a version, a
// slot, a size and a queue depth (see OTA_APPROVAL_PROTOCOL.md) and none of it
// is shown — a driver glancing at this needs to decide, not to audit.
//
// It ACCEPTS ITSELF after ota.autoAcceptMs (5 s) if nobody touches it. Deny is
// the deliberate act; ignoring it is consent. The top stripe drains away as the
// window closes so the decision is not taken silently.
//
// The card DROPS IN FROM ABOVE the screen and rests near the top edge for the
// whole window, rather than sitting in the middle. It arrives the way a banner
// arrives, and it leaves the centre of the display — where the drive view and
// the media art live — uncovered while the driver decides.
//
// No close button and no tap-outside-to-dismiss. Every other popup in this app
// is informational and dismissing it costs nothing. This one puts a verdict on
// the CAN bus, so a stray tap on the scrim must not become an answer — the only
// ways out are Accept, Deny, and letting the timer run.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // `ota` is the OtaManager context property from main.cpp.
    required property var ota

    // Set for ~1.2 s after an answer so the card can confirm what was sent
    // before it disappears. "" | "approved" | "denied"
    property string result: ""

    // Non-empty when a verdict could not be written. The offer stays on screen
    // because the tap genuinely did nothing.
    property string errorText: ""

    // 1 → 0 over the auto-accept window, drawn as the top stripe draining away.
    // Reuses the accent bar that was already there rather than adding a
    // progress widget, so the card gains a countdown without gaining clutter.
    property real countdown: 1.0

    // How far the resting card sits below the top edge.
    property real topInset: 24

    // Single source of truth for "the card belongs on screen". Drives the scrim
    // fade and the card's drop, so the two cannot disagree about which way the
    // prompt is currently going.
    readonly property bool showing: (ota && ota.requestPending) || result !== ""

    visible: opacity > 0
    opacity: showing ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    // Inline components have to sit at the top level of the document, so the
    // button lives here rather than next to the row that uses it.
    component ActionButton: Rectangle {
        id: btn
        property string label: ""
        property color  tint: "#8899bb"
        signal activated()

        radius: 12
        color: ma.pressed       ? Qt.rgba(btn.tint.r, btn.tint.g, btn.tint.b, 0.30)
             : ma.containsMouse ? Qt.rgba(btn.tint.r, btn.tint.g, btn.tint.b, 0.20)
                                : Qt.rgba(btn.tint.r, btn.tint.g, btn.tint.b, 0.12)
        border.color: btn.tint
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: btn.label
            color: btn.tint
            font { pixelSize: 17; bold: true; family: "Arial" }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            onClicked: btn.activated()
        }
    }

    // Swallow everything underneath. Without this the launcher keeps taking
    // taps through the scrim.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        // No onClicked — see the header. Present only to absorb input.
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.04, 0.08, 0.88)
    }

    Connections {
        target: root.ota

        function onVerdictSent(target, approved) {
            root.errorText = ""
            root.result = approved ? "approved" : "denied"
            resultTimer.restart()
        }

        function onVerdictFailed(reason) {
            root.errorText = reason
            root.countdown = 1.0
        }

        // A queued offer surfacing behind the current one must get its own full
        // window, not inherit whatever was left of the previous one.
        function onNewOffer() {
            if (autoTimer.running) autoTimer.restart()
            if (drain.running)     drain.restart()
        }
    }

    Timer {
        id: resultTimer
        interval: 1200
        onTriggered: root.result = ""
    }

    // Auto-accept. Deliberately driven from QML rather than C++: `root.visible`
    // is in the condition, and that already accounts for the splash gate in
    // Main.qml — so an offer that arrives during boot is not approved before
    // anyone could possibly have seen it.
    Timer {
        id: autoTimer
        interval: (root.ota && root.ota.autoAcceptMs > 0) ? root.ota.autoAcceptMs : 5000
        running: root.visible
                 && root.ota && root.ota.autoAcceptMs > 0
                 && root.ota.requestPending
                 && root.result === ""
                 && root.errorText === ""
        onTriggered: if (root.ota) root.ota.approve()
    }

    NumberAnimation {
        id: drain
        target: root
        property: "countdown"
        from: 1.0
        to: 0.0
        duration: autoTimer.interval
        running: autoTimer.running
    }

    // ---- CARD ---------------------------------------------------------------
    Rectangle {
        id: card
        width: 460
        height: 216
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 24
        color: "#0d1117"
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1

        // Parked above the top edge; the "shown" state is what brings it down.
        // Far enough up that the shadow and the rounded corners clear the
        // screen too, so nothing peeks while the prompt is away.
        y: -(height + 48)

        // `root.visible` is in the condition as well as `showing`, because
        // Main.qml holds this popup back until the splash finishes. Without it,
        // an offer that arrived during boot would finish its drop behind the
        // splash and be sitting there, motionless, the instant the splash lifts.
        states: State {
            name: "shown"
            when: root.showing && root.visible
            PropertyChanges { card.y: root.topInset }
        }

        // Asymmetric on purpose. Coming in it overshoots and settles, which is
        // what makes it read as dropping rather than sliding. Going out it just
        // leaves — a bounce on the way up would draw the eye back to a card
        // whose decision has already been made.
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
                    duration: 180          // same as the scrim fade, so they end together
                    easing.type: Easing.InCubic
                }
            }
        ]

        // Accent stripe — amber while the decision is open, then it takes the
        // colour of the answer during the confirmation beat. Its width drains
        // to zero over the auto-accept window; full width means the countdown
        // is off, which is also what the confirmation beat wants.
        Rectangle {
            anchors { top: parent.top; left: parent.left }
            width: parent.width * (root.result === "" ? root.countdown : 1.0)
            height: 3
            radius: 2
            opacity: 0.85
            color: root.result === "approved" ? "#21cfa4"
                 : root.result === "denied"   ? "#ff6b6b"
                                              : "#f79b55"
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        // ---- CONFIRMATION BEAT ---------------------------------------------
        // Replaces the body entirely, so there is no moment where the buttons
        // are still visible under a "sent" message and invite a second tap at
        // an offer that is already answered.
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 10
            visible: root.result !== ""

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.result === "approved" ? "✓" : "✕"
                color: root.result === "approved" ? "#21cfa4" : "#ff6b6b"
                font { pixelSize: 54; bold: true; family: "Arial" }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.result === "approved" ? qsTr("Update approved")
                                                 : qsTr("Update denied")
                color: "#ffffff"
                font { pixelSize: 19; bold: true; family: "Arial" }
            }
        }

        // ---- THE ASK --------------------------------------------------------
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 0
            visible: root.result === ""

            // Equal spacers above and below centre the title in whatever room
            // the buttons leave, instead of pinning it to the top and opening
            // a dead gap in the middle of the card.
            Item { Layout.fillHeight: true }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Software Update Request")
                color: "#ffffff"
                font { pixelSize: 22; bold: true; family: "Arial" }
            }

            Item { Layout.fillHeight: true }

            // Only ever shown when the verdict could not be written. There is
            // no other subtitle: a failed tap must not look like a successful
            // one, and that is the single thing worth interrupting for.
            Text {
                Layout.fillWidth: true
                Layout.bottomMargin: 14
                visible: root.errorText !== ""
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Could not send the answer — ") + root.errorText
                color: "#ff8f8f"
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font { pixelSize: 12; family: "Arial" }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                ActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    label: qsTr("Deny")
                    tint: "#ff5c5c"
                    onActivated: if (root.ota) root.ota.deny()
                }

                ActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    label: qsTr("Accept")
                    tint: "#2ecc8f"
                    onActivated: if (root.ota) root.ota.approve()
                }
            }
        }
    }
}
