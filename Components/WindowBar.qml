import QtQuick
import QtQuick.Window
import QtQuick.Controls

Rectangle {
    id: titleBar
    width: parent.width - 20
    height: 30
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: titleBar.color0 }
        GradientStop { position: 0.5; color: titleBar.color1 }
        GradientStop { position: 1.0; color: titleBar.color2 }
    }
    opacity: 0.9
    anchors.topMargin: 10
    anchors.rightMargin: 10
    anchors.leftMargin: 10
    topLeftRadius: 10
    topRightRadius: 10
    bottomLeftRadius: 10
    bottomRightRadius: 10

    required property var window
    required property string titleName
    required property bool showBackButton
    required property string color0
    required property string color1
    required property string color2

    property real brightnessValue: 1.0
    property real volumeValue: 0.7
    property real volumeMax: 100      // >100 enables software boost past 0 dB
    property bool volumeMuted: false

    signal backRequested()
    signal brightnessChanged(real value)
    signal volumeChanged(real value)
    signal volumeMuteToggled()

    Behavior on opacity { NumberAnimation { duration: 120 } }

    MouseArea {
        anchors.fill: parent
        onPressed: {
            brightnessPopup.visible = false
            volumePopup.visible = false
            titleBar.window.startSystemMove()
        }
        hoverEnabled: true
        onEntered: titleBar.opacity = 1.0
        onExited: titleBar.opacity = 0.9
    }

    // BACK BUTTON
    Rectangle {
        id: backBtn
        width: 22; height: 22; radius: 8
        color: backMouse.pressed ? "#D08831" : "transparent"
        border.color: "#D08831"
        border.width: 1
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        visible: showBackButton

        Image {
            anchors.centerIn: parent
            source: "qrc:/assets/icons/home.png"
            width: 13; height: 13
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: titleBar.backRequested()
            hoverEnabled: true
            onEntered: parent.scale = 1.03
            onExited: parent.scale = 1.0
        }
    }

    // TITLE
    Text {
        anchors.centerIn: parent
        text: titleName
        color: "#D08831"
        font.bold: true
        font.family: "Arial"
        font.pointSize: 14
    }

    // SYSTEM CONTROLS
    Row {
        id: controlsRow
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        z: 10

        // BRIGHTNESS
        Rectangle {
            id: brightnessBtn
            width: 22; height: 22; radius: 8
            color: brightnessMouse.pressed ? "#D08831" : "transparent"
            border.color: "#D08831"
            border.width: 1

            Image {
                anchors.centerIn: parent
                source: "qrc:/assets/icons/brightness.png"
                width: 17; height: 17
                fillMode: Image.PreserveAspectFit
            }

            MouseArea {
                id: brightnessMouse
                anchors.fill: parent
                onClicked: {
                    brightnessPopup.visible = !brightnessPopup.visible
                    if (brightnessPopup.visible) volumePopup.visible = false
                }
                hoverEnabled: true
                onEntered: parent.scale = 1.03
                onExited: parent.scale = 1.0
            }

            Rectangle {
                id: brightnessPopup
                visible: false
                width: 180
                height: 56
                anchors.top: parent.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                color: Qt.rgba(0.02, 0.04, 0.08, 0.96)
                border.color: Qt.rgba(0.82, 0.53, 0.19, 0.5)
                border.width: 1
                radius: 14
                z: 999

                MouseArea { anchors.fill: parent }

                Row {
                    anchors.centerIn: parent
                    spacing: 10

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "qrc:/assets/icons/brightness.png"
                        width: 17; height: 17
                        fillMode: Image.PreserveAspectFit
                    }

                    Slider {
                        id: brightnessSlider
                        width: 90
                        height: 28
                        from: 0.1
                        to: 1.0
                        stepSize: 0.01
                        live: true
                        value: titleBar.brightnessValue

                        onValueChanged: {
                            if (pressed) {
                                titleBar.brightnessValue = value
                                titleBar.brightnessChanged(value)
                            }
                        }

                        background: Rectangle {
                            x: brightnessSlider.leftPadding
                            y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                            width: brightnessSlider.availableWidth
                            height: 4
                            radius: 2
                            color: "#082839"

                            Rectangle {
                                x: 0
                                y: 0
                                width: brightnessSlider.visualPosition * parent.width
                                height: parent.height
                                color: "#D08831"
                                radius: 2
                            }
                        }

                        handle: Rectangle {
                            x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                            y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                            width: 14
                            height: 14
                            radius: 7
                            color: brightnessSlider.pressed ? "#ffffff" : "#D08831"
                            border.color: "#ffffff"
                            border.width: 1.5
                        }
                    }

                    Text {
                        text: Math.round(titleBar.brightnessValue * 100) + "%"
                        width: 25
                        color: "#D08831"
                        font { pixelSize: 11; bold: true; family: "Arial" }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // VOLUME
        Rectangle {
            id: volumeBtn
            width: 22; height: 22; radius: 8
            color: volumeMouse.pressed ? "#D08831" : "transparent"
            border.color: "#D08831"
            border.width: 1

            Image {
                anchors.centerIn: parent
                source: titleBar.volumeMuted ? "qrc:/assets/icons/volumedown.png" : "qrc:/assets/icons/volumeup.png"
                width: 16; height: 16; fillMode: Image.PreserveAspectFit
            }

            MouseArea {
                id: volumeMouse
                anchors.fill: parent
                onClicked: {
                    volumePopup.visible = !volumePopup.visible
                    if (volumePopup.visible) brightnessPopup.visible = false
                }
                hoverEnabled: true
                onEntered: parent.scale = 1.03
                onExited: parent.scale = 1.0
            }

            Rectangle {
                id: volumePopup
                visible: false
                width: 180
                height: 56
                anchors.top: parent.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                color: Qt.rgba(0.02, 0.04, 0.08, 0.96)
                border.color: Qt.rgba(0.82, 0.53, 0.19, 0.5)
                border.width: 1
                radius: 14
                z: 999

                MouseArea { anchors.fill: parent }

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    // Mute toggle
                    Rectangle {
                        width: 24; height: 24; radius: 6
                        color: muteArea.containsMouse ? Qt.rgba(0.82, 0.53, 0.19, 0.3) : "transparent"
                        border.color: "#D08831"
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                            anchors.centerIn: parent
                            source: titleBar.volumeMuted ? "qrc:/assets/icons/volumedown.png" : "qrc:/assets/icons/volumeup.png"
                            width: 16; height: 16; fillMode: Image.PreserveAspectFit
                        }

                        MouseArea {
                            id: muteArea
                            anchors.fill: parent
                            onClicked: titleBar.volumeMuteToggled()
                            hoverEnabled: true
                        }
                    }

                    Slider {
                        id: volumeSlider
                        width: 90
                        height: 28
                        from: 0
                        to: titleBar.volumeMax
                        stepSize: 1
                        live: true
                        value: titleBar.volumeValue

                        onValueChanged: {
                            if (pressed) {
                                titleBar.volumeValue = value
                                titleBar.volumeChanged(value)
                            }
                        }

                        background: Rectangle {
                            x: volumeSlider.leftPadding
                            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                            width: volumeSlider.availableWidth
                            height: 4
                            radius: 2
                            color: "#082839"

                            Rectangle {
                                x: 0
                                y: 0
                                width: volumeSlider.visualPosition * parent.width
                                height: parent.height
                                color: "#D08831"
                                radius: 2
                            }
                        }

                        handle: Rectangle {
                            x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                            width: 14
                            height: 14
                            radius: 7
                            color: volumeSlider.pressed ? "#ffffff" : "#D08831"
                            border.color: "#ffffff"
                            border.width: 1.5
                        }
                    }

                }
            }
        }

        // Separator
        Rectangle {
            width: 1; height: 16
            color: Qt.rgba(0.82, 0.53, 0.19, 0.3)
            anchors.verticalCenter: parent.verticalCenter
        }

        // Minimize
        Rectangle {
            width: 22; height: 22; radius: 8
            color: minMouse.pressed ? "#D08831" : "transparent"
            border.color: "#D08831"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "−"
                color: "#FFFFFF"
                font.bold: true
                font.family: "Arial"
                font.pointSize: 16
            }

            MouseArea {
                id: minMouse
                anchors.fill: parent
                onClicked: titleBar.window.showMinimized()
                hoverEnabled: true
                onEntered: parent.scale = 1.03
                onExited: parent.scale = 1.0
            }
        }

        // Maximize / Restore
        Rectangle {
            width: 22; height: 22; radius: 8
            color: maxMouse.pressed ? "#D08831" : "transparent"
            border.color: "#D08831"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: titleBar.window.visibility === Window.Maximized ? "❐" : "□"
                color: "#FFFFFF"
                font.bold: true
                font.family: "Arial"
                font.pixelSize: 12
            }

            MouseArea {
                id: maxMouse
                anchors.fill: parent
                onClicked: {
                    if (titleBar.window.visibility === Window.Maximized)
                        titleBar.window.showNormal()
                    else
                        titleBar.window.showMaximized()
                }
                hoverEnabled: true
                onEntered: parent.scale = 1.03
                onExited: parent.scale = 1.0
            }
        }

        // Close
        Rectangle {
            width: 22; height: 22; radius: 8
            color: closeMouse.pressed ? "#964405" : "transparent"
            border.color: "#964405"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "×"
                color: "#FFFFFF"
                font.bold: true
                font.family: "Arial"
                font.pixelSize: 16
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                onClicked: titleBar.window.close()
                hoverEnabled: true
                onEntered: parent.scale = 1.03
                onExited: parent.scale = 1.0
            }
        }
    }
}