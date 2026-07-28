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

    width: parent ? parent.width : 0
    height: keyArea.height + previewArea.height + 16

    // Preview area
    Rectangle {
        id: previewArea
        width: parent.width
        height: 50
        color: "#082839"
        border.color: "#D08831"
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
                color: "#e7f1ef"
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
                color: eyeArea.containsMouse ? "#964405" : "#10475E"
                border.color: virtualKeyboard.revealText ? "#D08831" : "#3D717E"
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
                        ctx.strokeStyle = "#D08831"
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
                color: clearArea.containsMouse ? "#ff4444" : "#aa2222"
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 100 } }

                Text { text: "✕"; color: "#ffffff"; font.pixelSize: 18; font.bold: true; anchors.centerIn: parent }

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
        color: "#082839"
        border.color: "#3D717E"
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
                        color: keyMouse1.containsMouse ? "#964405" : "#10475E"
                        border.color: keyMouse1.containsMouse ? "#D08831" : "#3D717E"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: modelData; color: "#e7f1ef"; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
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
                        color: keyMouse2.containsMouse ? "#964405" : "#10475E"
                        border.color: keyMouse2.containsMouse ? "#D08831" : "#3D717E"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: modelData; color: "#e7f1ef"; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
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
                        color: keyMouse3.containsMouse ? "#964405" : "#10475E"
                        border.color: keyMouse3.containsMouse ? "#D08831" : "#3D717E"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: modelData; color: "#e7f1ef"; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
                        MouseArea { id: keyMouse3; anchors.fill: parent; hoverEnabled: true; onClicked: appendChar(modelData) }
                    }
                }
            }

            // Row 4: ZXCV + Shift + Backspace
            Row { spacing: 6; anchors.horizontalCenter: parent.horizontalCenter
                // Shift
                Rectangle {
                    width: (virtualKeyboard.width - 66) / 9; height: 44; radius: 6
                    color: shiftMouse.containsMouse ? "#D08831" : (shiftActive ? "#D08831" : "#10475E")
                    border.color: shiftMouse.containsMouse ? "#D08831" : "#3D717E"; border.width: 1
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
                        width: (virtualKeyboard.width - 66) / 9; height: 44; radius: 6
                        color: keyMouse4.containsMouse ? "#964405" : "#10475E"
                        border.color: keyMouse4.containsMouse ? "#D08831" : "#3D717E"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: modelData; color: "#e7f1ef"; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
                        MouseArea { id: keyMouse4; anchors.fill: parent; hoverEnabled: true; onClicked: appendChar(modelData) }
                    }
                }
                // Backspace
                Rectangle {
                    width: (virtualKeyboard.width - 66) / 9; height: 44; radius: 6
                    color: bsMouse.containsMouse ? "#964405" : "#10475E"
                    border.color: bsMouse.containsMouse ? "#D08831" : "#3D717E"; border.width: 1
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
                    color: canMouse.containsMouse ? "#ff4444" : "#aa2222"
                    border.color: canMouse.containsMouse ? "#ff4444" : "#3D717E"; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "Cancel"; color: "#ffffff"; font.pixelSize: 14; font.bold: true; font.family: "Arial" }
                    MouseArea { id: canMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { targetText = ""; if (targetItem) targetItem.text = ""; cancelled() } }
                }
                // Space
                Rectangle {
                    width: (virtualKeyboard.width - 35) / 5 * 3; height: 44; radius: 6
                    color: spaceMouse.containsMouse ? "#964405" : "#10475E"
                    border.color: spaceMouse.containsMouse ? "#D08831" : "#3D717E"; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "Space"; color: "#e7f1ef"; font.pixelSize: 14; font.bold: true; font.family: "Arial" }
                    MouseArea { id: spaceMouse; anchors.fill: parent; hoverEnabled: true; onClicked: appendChar(" ") }
                }
                // Enter
                Rectangle {
                    width: (virtualKeyboard.width - 35) / 5; height: 44; radius: 6
                    color: entMouse.containsMouse ? "#964405" : "#5A3211"
                    border.color: entMouse.containsMouse ? "#D08831" : "#D08831"; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "Enter"; color: "#e7f1ef"; font.pixelSize: 16; font.bold: true; font.family: "Arial" }
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