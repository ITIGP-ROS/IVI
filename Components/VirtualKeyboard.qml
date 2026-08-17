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
    property bool symbolActive: false

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
            property real w: (virtualKeyboard.width - 70) / 10

            // Row 1
            Row { spacing: 6; anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: symbolActive ? ["1","2","3","4","5","6","7","8","9","0"] : (shiftActive ? ["Q","W","E","R","T","Y","U","I","O","P"] : ["q","w","e","r","t","y","u","i","o","p"])
                    delegate: Rectangle {
                        width: keyGrid.w; height: 44; radius: 6
                        color: keyMouse1.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                        border.color: keyMouse1.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: modelData; color: virtualKeyboard.keyTextColor; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
                        MouseArea { id: keyMouse1; anchors.fill: parent; hoverEnabled: true; onClicked: appendChar(modelData) }
                    }
                }
            }

            // Row 2
            Row { spacing: 6; anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: symbolActive ? ["-","/",":",";","(",")","$","&","@","\""] : (shiftActive ? ["A","S","D","F","G","H","J","K","L"] : ["a","s","d","f","g","h","j","k","l"])
                    delegate: Rectangle {
                        width: keyGrid.w; height: 44; radius: 6
                        color: keyMouse2.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                        border.color: keyMouse2.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: modelData; color: virtualKeyboard.keyTextColor; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
                        MouseArea { id: keyMouse2; anchors.fill: parent; hoverEnabled: true; onClicked: appendChar(modelData) }
                    }
                }
            }

            // Row 3
            Row { spacing: 6; anchors.horizontalCenter: parent.horizontalCenter
                // Shift or Extra Symbol
                Rectangle {
                    width: keyGrid.w * 1.5 + 3; height: 44; radius: 6
                    color: shiftMouse.containsMouse ? virtualKeyboard.accent : (shiftActive ? virtualKeyboard.accent : virtualKeyboard.keyColor)
                    border.color: shiftMouse.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Image {
                        visible: !symbolActive
                        anchors.centerIn: parent; width: 23; height: 23;
                        source: shiftActive ? "qrc:/assets/icons/upper.png" : "qrc:/assets/icons/lower.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        visible: symbolActive
                        anchors.centerIn: parent; text: "_"; color: virtualKeyboard.keyTextColor; font.pixelSize: 16; font.bold: true; font.family: "Arial"
                    }
                    MouseArea {
                        id: shiftMouse; anchors.fill: parent; hoverEnabled: true;
                        onClicked: {
                            if (symbolActive) appendChar("_")
                            else shiftActive = !shiftActive
                        }
                    }
                }
                Repeater {
                    model: symbolActive ? [".", ",", "?", "!", "'", "+", "="] : (shiftActive ? ["Z","X","C","V","B","N","M"] : ["z","x","c","v","b","n","m"])
                    delegate: Rectangle {
                        width: keyGrid.w; height: 44; radius: 6
                        color: keyMouse3.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                        border.color: keyMouse3.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: modelData; color: virtualKeyboard.keyTextColor; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
                        MouseArea { id: keyMouse3; anchors.fill: parent; hoverEnabled: true; onClicked: appendChar(modelData) }
                    }
                }
                // Backspace
                Rectangle {
                    width: keyGrid.w * 1.5 + 3; height: 44; radius: 6
                    color: bsMouse.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                    border.color: bsMouse.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Image {
                        anchors.centerIn: parent; width: 23; height: 23;
                        source: "qrc:/assets/icons/back.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea { id: bsMouse; anchors.fill: parent; hoverEnabled: true; onClicked: backspace() }
                }
            }

            // Row 4
            Row { spacing: 6; anchors.horizontalCenter: parent.horizontalCenter
                // ?123 / ABC Toggle
                Rectangle {
                    width: keyGrid.w * 1.5 + 3; height: 44; radius: 6
                    color: symToggleMouse.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                    border.color: symToggleMouse.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: symbolActive ? "ABC" : "?123"; color: virtualKeyboard.keyTextColor; font.pixelSize: 14; font.bold: true; font.family: "Arial" }
                    MouseArea { id: symToggleMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { symbolActive = !symbolActive; shiftActive = false; } }
                }
                // Cancel
                Rectangle {
                    width: keyGrid.w * 2 + 6; height: 44; radius: 6
                    color: canMouse.containsMouse ? virtualKeyboard.danger : virtualKeyboard.dangerDim
                    border.color: canMouse.containsMouse ? virtualKeyboard.danger : virtualKeyboard.keyBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "Cancel"; color: virtualKeyboard.keyTextColor; font.pixelSize: 14; font.bold: true; font.family: "Arial" }
                    MouseArea { id: canMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { targetText = ""; if (targetItem) targetItem.text = ""; cancelled() } }
                }
                // Space
                Rectangle {
                    width: keyGrid.w * 4 + 18; height: 44; radius: 6
                    color: spaceMouse.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.keyColor
                    border.color: spaceMouse.containsMouse ? virtualKeyboard.accent : virtualKeyboard.keyBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "Space"; color: virtualKeyboard.keyTextColor; font.pixelSize: 14; font.bold: true; font.family: "Arial" }
                    MouseArea { id: spaceMouse; anchors.fill: parent; hoverEnabled: true; onClicked: appendChar(" ") }
                }
                // Dot
                Rectangle {
                    width: keyGrid.w; height: 44; radius: 6
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
                // Enter
                Rectangle {
                    width: keyGrid.w * 1.5 + 3; height: 44; radius: 6
                    color: entMouse.containsMouse ? virtualKeyboard.keyHoverColor : virtualKeyboard.enterColor
                    border.color: entMouse.containsMouse ? virtualKeyboard.accent : virtualKeyboard.accent; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "Enter"; color: virtualKeyboard.keyTextColor; font.pixelSize: 14; font.bold: true; font.family: "Arial" }
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