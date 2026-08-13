import QtQuick
import QtQuick.Controls
import QtMultimedia

Rectangle {
    id: radioPage
    required property StackView stackView
    required property MediaPlayer mediaPlayer
    required property var        mediaPage
    anchors.fill: parent
    color: "transparent"

    readonly property color accent: Theme.accentAmber

    // ── Listen to shared player status ──
    Connections {
        target: mediaPlayer
        function onMediaStatusChanged() {
            if (mediaPlayer.mediaStatus === MediaPlayer.BufferingMedia) statusDot.color = Theme.tint(radioPage.accent, 0.5)
            else if (mediaPlayer.mediaStatus === MediaPlayer.BufferedMedia) statusDot.color = Theme.accentMint
            else if (mediaPlayer.mediaStatus === MediaPlayer.StalledMedia) statusDot.color = Theme.danger
            else if (mediaPlayer.mediaStatus === MediaPlayer.NoMedia) statusDot.color = Theme.textMuted
        }
    }

    // Layout
    Column {
        anchors.fill: parent
        anchors.margins: radioPage.width / 20
        anchors.topMargin: radioPage.height / 10
        spacing: radioPage.height / 40

        // Search bar
        Row {
            width: parent.width
            spacing: radioPage.width / 60
            height: radioPage.height / 18

            // Visual display (replaces TextInput)
            Rectangle {
                width: parent.width * 0.35
                height: parent.height
                radius: height / 2
                color: Theme.glassFill
                border.color: searchMouse.containsMouse ? radioPage.accent : Theme.glassBorder
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 150 } }

                // Hidden input — syncs with VirtualKeyboard
                TextInput {
                    id: searchField
                    visible: false
                    text: mediaPage.radioSearchQuery
                    onTextChanged: {
                        mediaPage.radioSearchQuery = text
                        if (text === "") mediaPage.radioSearchAttempted = false
                    }
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    verticalAlignment: Text.AlignVCenter
                    text: searchField.text
                    color: Theme.textPrimary
                    font.pixelSize: radioPage.width / 60
                    font.family: "Arial"
                    elide: Text.ElideRight
                    visible: searchField.text !== ""
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    verticalAlignment: Text.AlignVCenter
                    text: "🔍 Search station name..."
                    color: Theme.textSecondary
                    font.pixelSize: radioPage.width / 65
                    font.family: "Arial"
                    visible: searchField.text === ""
                }

                MouseArea {
                    id: searchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: keyboardPopup.open()
                }
            }

            // Search button
            Rectangle {
                width: parent.width * 0.15
                height: parent.height
                radius: height / 2
                color: searchBtnArea.containsMouse ? Theme.tint(radioPage.accent, 0.3) : Theme.tint(radioPage.accent, 0.15)
                border.color: radioPage.accent
                border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "Search"
                    color: Theme.textPrimary
                    font.pixelSize: radioPage.width / 60
                    font.family: "Arial"
                    font.bold: true
                }
                MouseArea {
                    id: searchBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        mediaPage.radioSearchAttempted = true
                        mediaPage.globalStationsModel.clear()
                        mediaPage.globalRadioAPI.fetchStations()
                    }
                }
            }

            Rectangle { width: 40; height: 1; color: "transparent" }

            // NOW PLAYING
            Item {
                width: parent.width / 4
                height: parent.height

                Rectangle {
                    anchors.fill: parent
                    radius: height / 5
                    color: mediaPage.currentRadioStation ? Theme.tint(radioPage.accent, 0.2) : Theme.glassFill
                    border.width: mediaPage.currentRadioStation ? 2 : 1
                    border.color: mediaPage.currentRadioStation ? radioPage.accent : Theme.glassBorder
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                }

                Text {
                    anchors.centerIn: parent
                    text: mediaPage.currentRadioStation ? "▶ " + mediaPage.currentRadioStation.name : "📻  Radio Browser"
                    color: mediaPage.currentRadioStation ? radioPage.accent : Theme.textSecondary
                    font.pixelSize: radioPage.width / 70
                    font.family: "Arial"
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width - 30
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    id: statusDot
                    width: 8; height: 8; radius: 4
                    color: Theme.textMuted
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }

        // Station list
        Item {
            width: parent.width
            height: radioPage.height * 0.62

            Rectangle {
                anchors.fill: parent
                radius: radioPage.height / 50
                color: Theme.glassFill
                border.width: 1
                border.color: Theme.glassBorder
            }

            // Loading spinner overlay
            Rectangle {
                anchors.fill: parent
                color: Theme.surface
                opacity: 0.85
                visible: mediaPage.radioIsLoading
                radius: radioPage.height / 50
                z: 10

                Column {
                    anchors.centerIn: parent
                    spacing: 12

                    Rectangle {
                        width: 40; height: 40
                        color: "transparent"
                        border.color: radioPage.accent
                        border.width: 3
                        radius: width / 2
                        anchors.horizontalCenter: parent.horizontalCenter

                        Rectangle {
                            width: 6; height: 6
                            color: Theme.surface
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        RotationAnimation on rotation {
                            running: parent.parent.parent.visible
                            loops: Animation.Infinite
                            duration: 800
                            from: 0; to: 360
                        }
                    }

                    Text {
                        text: "Searching stations..."
                        color: radioPage.accent
                        font { pixelSize: radioPage.width / 55; family: "Arial"; bold: true }
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            ListView {
                id: stationList
                anchors { fill: parent; margins: 8; rightMargin: 16 }
                model: mediaPage.globalStationsModel
                clip: true
                spacing: 6
                visible: !mediaPage.radioIsLoading

                ScrollBar.vertical: ScrollBar {
                    width: 6
                    policy: ScrollBar.AsNeeded
                    interactive: true

                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: parent.pressed ? Theme.tint(radioPage.accent, 0.5) : radioPage.accent
                        opacity: parent.pressed ? 1.0 : 0.6
                        anchors.horizontalCenter: parent.horizontalCenter
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    background: Rectangle {
                        implicitWidth: 6
                        color: Theme.glassFill
                        radius: 3
                        opacity: 0.5
                        anchors.fill: parent
                    }
                }

                delegate: Rectangle {
                    id: stationDelegate
                    required property string stationuuid
                    required property string name
                    required property string url
                    required property string favicon
                    required property string codec
                    required property string tags
                    required property string country
                    required property int index

                    width: stationList.width - 12
                    height: radioPage.height / 12
                    radius: height / 4
                    anchors.right: parent.right
                    anchors.rightMargin: 12

                    property bool isActive: mediaPage.currentRadioStation && mediaPage.currentRadioStation.name === stationDelegate.name

                    color: delegateArea.containsMouse ? Theme.tint(radioPage.accent, 0.25) : (isActive ? Theme.tint(radioPage.accent, 0.15) : Theme.glassFill)
                    border.color: isActive ? radioPage.accent : Theme.glassBorder
                    border.width: isActive ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Item {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }

                        Rectangle {
                            id: stationIconRect
                            width: parent.height * 0.7
                            height: parent.height * 0.7
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            radius: width / 5
                            color: Theme.glassFill
                            border.color: Theme.glassBorder
                            border.width: 1

                            Image {
                                anchors.fill: parent
                                anchors.margins: 4
                                source: stationDelegate.favicon || ""
                                fillMode: Image.PreserveAspectFit
                                visible: status === Image.Ready
                                asynchronous: true
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "📻"
                                font.pixelSize: parent.width * 0.5
                                visible: parent.children[0].status !== Image.Ready
                            }
                        }

                        Column {
                            anchors.left: stationIconRect.right
                            anchors.leftMargin: 16
                            anchors.right: playBtnRect.left
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: stationDelegate.name
                                color: stationDelegate.isActive ? radioPage.accent : Theme.textPrimary
                                font { pixelSize: radioPage.width / 80; bold: true; family: "Arial" }
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: stationDelegate.country + " • " + stationDelegate.codec
                                color: Theme.textSecondary
                                font { pixelSize: radioPage.width / 90; family: "Arial" }
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: stationDelegate.tags
                                color: Theme.textMuted
                                font { pixelSize: radioPage.width / 95; family: "Arial" }
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        Rectangle {
                            id: playBtnRect
                            width: parent.height * 0.6
                            height: parent.height * 0.6
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            radius: width / 2
                            color: playBtnArea.containsMouse ? Theme.tint(radioPage.accent, 0.4) : Theme.tint(radioPage.accent, 0.1)
                            border.color: radioPage.accent
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Image{
                                anchors.centerIn: parent
                                width: 20; height: 20
                                source:  stationDelegate.isActive
                                    && mediaPlayer.playbackState === MediaPlayer.PlayingState ? "qrc:/assets/icons/pause.png" : "qrc:/assets/icons/play.png"
                                fillMode: Image.PreserveAspectFit
                            }

                            MouseArea {
                                id: playBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (stationDelegate.isActive)
                                        mediaPage.globalRadioAPI.togglePlayPause()
                                    else
                                        mediaPage.globalRadioAPI.playStation({ stationuuid: stationDelegate.stationuuid, name: stationDelegate.name,
                                                    url: stationDelegate.url, favicon: stationDelegate.favicon,
                                                    country: stationDelegate.country, codec: stationDelegate.codec,
                                                    tags: stationDelegate.tags })
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: delegateArea
                        anchors.fill: parent
                        hoverEnabled: true
                        z: -1
                        onDoubleClicked: mediaPage.globalRadioAPI.playStation({ stationuuid: stationDelegate.stationuuid, name: stationDelegate.name,
                                                    url: stationDelegate.url, favicon: stationDelegate.favicon,
                                                    country: stationDelegate.country, codec: stationDelegate.codec,
                                                    tags: stationDelegate.tags })
                    }
                }
            }

            // EMPTY STATE
            Column {
                anchors.centerIn: parent
                spacing: 8
                visible: mediaPage.globalStationsModel.count === 0 && !mediaPage.radioIsLoading
                z: 5

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: mediaPage.radioSearchAttempted ? "⚠" : "📻"
                    color: Theme.textSecondary
                    font { pixelSize: radioPage.width / 30; family: "Arial" }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: mediaPage.radioSearchAttempted
                        ? "No station found with that name."
                        : "No stations.\nSearch or filter above."
                    color: Theme.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    font { pixelSize: radioPage.width / 55; family: "Arial"; bold: true }
                }
            }
        }

        // Spacer
        Rectangle {width: parent.width; height: 3; color: "transparent" }

        // CONTROLS ROW
        Row {
            id: audioContRow
            width: parent.width
            height: radioPage.height / 15
            spacing: 0

            // Back button
            Rectangle {
                id: backBtnRect
                anchors.verticalCenter: parent.verticalCenter
                width: backText.width + 40
                height: backText.height + 14
                radius: height / 2
                color: backArea.containsMouse ? Theme.tint(radioPage.accent, 0.25) : Theme.glassFill
                border.color: radioPage.accent
                border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    id: backText
                    anchors.centerIn: parent
                    text: "Back"
                    color: Theme.textPrimary
                    font { pixelSize: radioPage.width / 55; family: "Arial"; bold: true }
                }
                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { stackView.pop() }
                }
            }

            // Centered playback controls
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: radioPage.width / 60

                // Previous
                Rectangle {
                    id: prevBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: radioPage.width / 25
                    height: width
                    radius: width / 2
                    color: prevArea.containsMouse ? Theme.tint(radioPage.accent, 0.2) : Theme.glassFill
                    border.color: radioPage.accent
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Image{
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: "qrc:/assets/icons/prev.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea {
                        id: prevArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: mediaPage.globalRadioAPI.playPrevious()
                    }
                }

                // Play/Pause
                Rectangle {
                    id: playBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: radioPage.width / 20
                    height: width
                    radius: width / 2
                    color: playArea.containsMouse ? Theme.tint(radioPage.accent, 0.25) : Theme.glassFill
                    border.color: radioPage.accent
                    border.width: 2
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Image{
                        anchors.centerIn: parent
                        width: 28; height: 28
                        source:  mediaPlayer.playbackState === MediaPlayer.PlayingState ? "qrc:/assets/icons/pause.png" : "qrc:/assets/icons/play.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: if (mediaPage.currentRadioStation) {
                            mediaPlayer.playbackState === MediaPlayer.PlayingState ? mediaPlayer.pause() : mediaPlayer.play()
                        }
                    }
                }

                // Next
                Rectangle {
                    id: nextBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: radioPage.width / 25
                    height: width
                    radius: width / 2
                    color: nextArea.containsMouse ? Theme.tint(radioPage.accent, 0.2) : Theme.glassFill
                    border.color: radioPage.accent
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Image{
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: "qrc:/assets/icons/next.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea {
                        id: nextArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: mediaPage.globalRadioAPI.playNext()
                    }
                }
            }

            // Volume controls (right)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: radioPage.width / 50
                spacing: radioPage.width / 60

                // Mute
                Rectangle {
                    id: volumeBtn
                    property bool muted: false
                    width: radioPage.width / 25
                    height: width
                    radius: width / 2
                    color: muteArea.containsMouse ? Theme.tint(radioPage.accent, 0.2) : Theme.glassFill
                    border.color: radioPage.accent
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Image {
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: volumeBtn.muted ? "qrc:/assets/icons/volumedown.png"
                                                : "qrc:/assets/icons/volumeup.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea {
                        id: muteArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            volumeBtn.muted = !volumeBtn.muted
                            mediaPlayer.audioOutput.muted  = volumeBtn.muted
                        }
                    }
                }

                // Volume slider
                Slider {
                    id: volumeSlider
                    width: radioPage.width / 7
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0; to: 1; value: 0.6
                    onValueChanged: {
                        mediaPlayer.audioOutput.volume = value
                        volumeBtn.muted = false
                        mediaPlayer.audioOutput.muted = false
                    }

                    background: Rectangle {
                        x: volumeSlider.leftPadding
                        y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                        width: volumeSlider.availableWidth; height: 6; radius: 3
                        color: Theme.glassBorder
                        Rectangle {
                            width: volumeSlider.visualPosition * parent.width
                            height: parent.height; radius: parent.radius
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Theme.tint(radioPage.accent, 0.4) }
                                GradientStop { position: 1.0; color: radioPage.accent }
                            }
                        }
                    }
                }
            }
        }
    }

    // Virtual Keyboard Popup
    Popup {
        id: keyboardPopup
        parent: Overlay.overlay
        width: radioPage.width * 0.6
        height: radioPage.height * 0.7
        anchors.centerIn: Overlay.overlay
        modal: true
        Overlay.modal: Rectangle {
            color: Theme.scrim
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Theme.surface
            radius: 16
            border.color: radioPage.accent
            border.width: 2
        }

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            Text {
                text: "Search Station"
                font.pixelSize: radioPage.height * 0.04
                color: radioPage.accent
                font.bold: true
                font.family: "Arial"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            VirtualKeyboard {
                id: keyboard
                width: parent.width
                targetItem: searchField
                passwordMode: false
                maxLength: 64

                onAccepted: {
                    mediaPage.radioSearchAttempted = true
                    mediaPage.globalStationsModel.clear()
                    mediaPage.globalRadioAPI.fetchStations()
                    keyboard.clear()
                    keyboardPopup.close()
                }

                onCancelled: {
                    keyboard.clear()
                    keyboardPopup.close()
                }
            }
        }

        onOpened: {
            keyboard.targetText = searchField.text
        }
    }
}