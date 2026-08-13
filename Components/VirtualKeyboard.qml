import QtQuick
import QtQuick.Controls

Rectangle {
    id: virtualKeyboard
    color: "transparent"

    property string targetText: ""
    property bool targetActive: false
    property int maxLength: 64
    property bool passwordMode: false
    property var targetItem: null

    // Password visibility toggle (the eye button); only meaningful in passwordMode
    property bool revealText: false
    onRevealTextChanged: eyeCanvas.requestPaint()

    signal accepted()
    signal cancelled()

    property bool shiftActive: false

    /*
     * Palette. Defaults are the amber-on-teal the keyboard shipped with, so
     * every page that does not set them keeps exactly the keyboard it had —
     * only Settings, which has moved to the glass theme, overrides them.
     */
    property color accent:        Theme.accentAmber   // outlines, Enter, active shift
    property color panelColor:    Theme.glassFill     // key area backing
    property color fieldColor:    Theme.glassFill     // preview field backing
    property color keyColor:      Theme.glassFill     // key at rest
    property color keyHoverColor: Theme.tint(accent, 0.25) // key under the finger
    property color keyBorder:     Theme.glassBorder
    property color keyTextColor:  Theme.textPrimary
    property color enterColor:    Theme.tint(accent, 0.15)
    property color danger:        Theme.danger
    property color dangerDim:     Theme.tint(Theme.danger, 0.25)

    width: parent ? parent.width : 0
    height: keyArea.height + previewArea.height + 16

    // Preview area
    Rectangle {
        id: previewArea
        width: parent.width
        height: 50
        color: virtualKeyboard.fieldColor
        border.color: virtualKeyboard.accent
        border.width: 2
        radius: 8
        anchors.top: parent.top

        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Text {
                text: (passwordMode && !revealText)
                      ? targetText.split('').map(function() { return "•"; }).join('')
                      : targetText
                color: virtualKeyboard.keyTextColor
                font.pixelSize: 22
                font.family: "Arial"
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - clearBtn.width - parent.spacing
                       - (eyeBtn.visible ? eyeBtn.width + parent.spacing : 0)
                elide: Text.ElideLeft
            }

            // Show / hide the password
            Rectangle {
                id: eyeBtn
                visible: passwordMode
                width: 36; height: 36; radius: 6
                color: eyeArea.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                border.color: virtualKeyboard.revealText ? virtualKeyboard.accent : virtualKeyboard.keyBorder
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 100 } }

                Canvas {
                    id: eyeCanvas
                    anchors.centerIn: parent
                    width: 22; height: 22
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = virtualKeyboard.accent
                        ctx.lineWidth = 1.6
                        ctx.lineCap = "round"

                        // eye outline: two mirrored curves
                        ctx.beginPath()
                        ctx.moveTo(2, 11)
                        ctx.quadraticCurveTo(11, 3.5, 20, 11)
                        ctx.quadraticCurveTo(11, 18.5, 2, 11)
                        ctx.stroke()

                        // pupil
                        ctx.beginPath()
                        ctx.arc(11, 11, 3.2, 0, Math.PI * 2)
                        ctx.stroke()

                        // struck through while the password is masked
                        if (!virtualKeyboard.revealText) {
                            ctx.beginPath()
                            ctx.moveTo(3.5, 18.5)
                            ctx.lineTo(18.5, 3.5)
                            ctx.stroke()
                        }
                    }
                }

                MouseArea {
                    id: eyeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: virtualKeyboard.revealText = !virtualKeyboard.revealText
                }
            }

            Rectangle {
                id: clearBtn
                width: 36; height: 36; radius: 6
                color: clearArea.containsMouse ? virtualKeyboard.danger : virtualKeyboard.dangerDim
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 100 } }

                // × (U+00D7) rather than ✕ (U+2715): the latter is a Dingbats
                // glyph that no font on the target image covers — it is not an
                // emoji either, so the emoji font that carries the rest of the
                // symbols here does not rescue it, and the button came up blank
                // on the head unit. U+00D7 is in Latin-1 and is what the other
                // close buttons in this app already use.
                Text { text: "×"; color: virtualKeyboard.keyTextColor; font.pixelSize: 24; font.bold: true; font.family: "Arial"; anchors.centerIn: parent }

                MouseArea {
                    id: clearArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { targetText = ""; if (targetItem) targetItem.text = "" }
                }
            }
        }
    }

    // Key Area
    Rectangle {
        id: keyArea
        width: parent.width
        height: keyGrid.height + 20
        color: virtualKeyboard.panelColor
        border.color: virtualKeyboard.keyBorder
        border.width: 1
        radius: 12
        anchors.top: previewArea.bottom
        anchors.topMargin: 8

        Column {
            id: keyGrid
            anchors.centerIn: parent
            spacing: 6

            // Row 1: Numbers
            Row { spacing: 6; anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
                    delegate: Rectangle {
                        width: (virtualKeyboard.width - 70) / 10; height: 44; radius: 6
                        color: keyMouse1.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                        border.color: keyMouse1.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: modelData; color: virtualKeyboard.keyTextColor; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
                        MouseArea { id: keyMouse1; anchors.fill: parent; hoverEnabled: true; onClicked: appendChar(modelData) }
                    }
                }
            }

            // Row 2: QWERTY
            Row { spacing: 6; anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: shiftActive ? ["Q","W","E","R","T","Y","U","I","O","P"] : ["q","w","e","r","t","y","u","i","o","p"]
                    delegate: Rectangle {
                        width: (virtualKeyboard.width - 70) / 10; height: 44; radius: 6
                        color: keyMouse2.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                        border.color: keyMouse2.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: modelData; color: virtualKeyboard.keyTextColor; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
                        MouseArea { id: keyMouse2; anchors.fill: parent; hoverEnabled: true; onClicked: appendChar(modelData) }
                    }
                }
            }

            // Row 3: ASDF
            Row { spacing: 6; anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: shiftActive ? ["A","S","D","F","G","H","J","K","L"] : ["a","s","d","f","g","h","j","k","l"]
                    delegate: Rectangle {
                        width: (virtualKeyboard.width - 66) / 9; height: 44; radius: 6
                        color: keyMouse3.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                        border.color: keyMouse3.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: modelData; color: virtualKeyboard.keyTextColor; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
                        MouseArea { id: keyMouse3; anchors.fill: parent; hoverEnabled: true; onClicked: appendChar(modelData) }
                    }
                }
            }

            // Row 4: ZXCV + Shift + Dot + Backspace
            // Ten keys, so this row uses the number row's width formula rather
            // than the nine-key one the rows above it share.
            Row { spacing: 6; anchors.horizontalCenter: parent.horizontalCenter
                // Shift
                Rectangle {
                    width: (virtualKeyboard.width - 70) / 10; height: 44; radius: 6
                    color: shiftMouse.containsMouse ? virtualKeyboard.accent : (shiftActive ? virtualKeyboard.accent : virtualKeyboard.keyColor)
                    border.color: shiftMouse.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Image {
                        anchors.centerIn: parent;
                        width: 23; height: 23;
                        source: shiftActive ? "qrc:/assets/icons/upper.png" : "qrc:/assets/icons/lower.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea { id: shiftMouse; anchors.fill: parent; hoverEnabled: true; onClicked: shiftActive = !shiftActive }
                }
                Repeater {
                    model: shiftActive ? ["Z","X","C","V","B","N","M"] : ["z","x","c","v","b","n","m"]
                    delegate: Rectangle {
                        width: (virtualKeyboard.width - 70) / 10; height: 44; radius: 6
                        color: keyMouse4.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                        border.color: keyMouse4.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: modelData; color: virtualKeyboard.keyTextColor; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
                        MouseArea { id: keyMouse4; anchors.fill: parent; hoverEnabled: true; onClicked: appendChar(modelData) }
                    }
                }
                // Dot. Its own key rather than a Repeater entry: shift must not
                // turn it into anything else, and appendChar's auto-unshift
                // would drop the caps the user just armed for the next letter.
                Rectangle {
                    width: (virtualKeyboard.width - 70) / 10; height: 44; radius: 6
                    color: dotMouse.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                    border.color: dotMouse.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "."; color: virtualKeyboard.keyTextColor; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
                    MouseArea {
                        id: dotMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (targetText.length < maxLength) {
                                targetText = targetText + "."
                                if (targetItem) targetItem.text = targetText
                            }
                        }
                    }
                }
                // Backspace
                Rectangle {
                    width: (virtualKeyboard.width - 70) / 10; height: 44; radius: 6
                    color: bsMouse.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                    border.color: bsMouse.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Image {
                        anchors.centerIn: parent;
                        width: 23; height: 23;
                        source: "qrc:/assets/icons/back.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea { id: bsMouse; anchors.fill: parent; hoverEnabled: true; onClicked: backspace() }
                }
            }

            // Row 5: Space, Cancel, Enter
            Row { spacing: 6; anchors.horizontalCenter: parent.horizontalCenter
                // Cancel
                Rectangle {
                    width: (virtualKeyboard.width - 35) / 5; height: 44; radius: 6
                    color: canMouse.containsMouse ? virtualKeyboard.danger : virtualKeyboard.dangerDim
                    border.color: canMouse.containsMouse ? virtualKeyboard.danger : virtualKeyboard.keyBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "Cancel"; color: virtualKeyboard.keyTextColor; font.pixelSize: 14; font.bold: true; font.family: "Arial" }
                    MouseArea { id: canMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { targetText = ""; if (targetItem) targetItem.text = ""; cancelled() } }
                }
                // Space
                Rectangle {
                    width: (virtualKeyboard.width - 35) / 5 * 3; height: 44; radius: 6
                    color: spaceMouse.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                    border.color: spaceMouse.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "Space"; color: virtualKeyboard.keyTextColor; font.pixelSize: 14; font.bold: true; font.family: "Arial" }
                    MouseArea { id: spaceMouse; anchors.fill: parent; hoverEnabled: true; onClicked: appendChar(" ") }
                }
                // Enter
                Rectangle {
                    width: (virtualKeyboard.width - 35) / 5; height: 44; radius: 6
                    color: entMouse.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.enterColor
                    border.color: entMouse.containsMouse ? virtualKeyboard.accent : virtualKeyboard.accent; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "Enter"; color: virtualKeyboard.keyTextColor; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
                    MouseArea { id: entMouse; anchors.fill: parent; hoverEnabled: true; onClicked: accepted() }
                }
            }
        }
    }

    function appendChar(newChar) {
        if (targetText.length < maxLength) {
            targetText = targetText + newChar
            if (targetItem) targetItem.text = targetText
            if (shiftActive) shiftActive = false
        }
    }

    function backspace() {
        if (targetText.length > 0) {
            targetText = targetText.slice(0, -1)
            if (targetItem) targetItem.text = targetText
        }
    }

    function clear() {
        targetText = ""
        revealText = false      // never leave a password revealed for the next entry
        if (targetItem) targetItem.text = ""
    }
}