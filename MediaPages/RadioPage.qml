import QtQuick
import QtQuick.Controls
import QtMultimedia
import Qt5Compat.GraphicalEffects

Rectangle {
    id: radioPage
    required property StackView stackView
    required property MediaPlayer mediaPlayer
    required property var        mediaPage
    anchors.fill: parent
    color: "transparent"

    // ── Listen to shared player status ──
    Connections {
        target: mediaPlayer
        function onMediaStatusChanged() {
            if (mediaPlayer.mediaStatus === MediaPlayer.BufferingMedia) statusDot.color = "#D08831"
            else if (mediaPlayer.mediaStatus === MediaPlayer.BufferedMedia) statusDot.color = "#00ffaa"
            else if (mediaPlayer.mediaStatus === MediaPlayer.StalledMedia) statusDot.color = "#964405"
            else if (mediaPlayer.mediaStatus === MediaPlayer.NoMedia) statusDot.color = "#5A3211"
        }
    }

    // BACKGROUND
    Rectangle {
        z: -1
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#082839" }
            GradientStop { position: 0.5; color: "#10475E" }
            GradientStop { position: 1.0; color: "#082839" }
        }

        Canvas {
            anchors.fill: parent
            opacity: 0.04
            onPaint: {
                var ctx = getContext("2d")
                ctx.fillStyle = "#D08831"
                var step = 40
                for (var x = 0; x < width; x += step) {
                    for (var y = 0; y < height; y += step) {
                        ctx.beginPath()
                        ctx.arc(x, y, 1.5, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
            }
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
                color: "#082839"
                border.color: searchMouse.containsMouse ? "#D08831" : "#3D717E"
                border.width: 1

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
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    text: searchField.text
                    color: "#e7f1ef"
                    font.pixelSize: radioPage.width / 60
                    font.family: "Arial"
                    elide: Text.ElideRight
                    visible: searchField.text !== ""
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    text: "🔍 Search station name..."
                    color: "#3D717E"
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
                color: searchBtnArea.containsMouse ? "#964405" : "#5A3211"
                border.color: "#D08831"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "Search"
                    color: "#e7f1ef"
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
                    id: titleGlass
                    anchors.fill: parent
                    radius: height / 5
                    color: mediaPage.currentRadioStation ? "#964405" : "#3D717E"
                    border.width: 1
                    border.color: "#50FFFFFF"
                    visible: false
                }

                InnerShadow {
                    id: titleInner
                    anchors.fill: titleGlass
                    source: titleGlass
                    horizontalOffset: -2
                    verticalOffset: -2
                    radius: 8
                    samples: 16
                    color: "#80FFFFFF"
                    visible: false
                }

                DropShadow {
                    anchors.fill: titleGlass
                    source: titleInner
                    horizontalOffset: 4
                    verticalOffset: 4
                    radius: 10
                    samples: 20
                    color: "#50000000"
                }

                Text {
                    anchors.centerIn: parent
                    text: mediaPage.currentRadioStation ? "▶ " + mediaPage.currentRadioStation.name : "📻  Radio Browser"
                    color: "#e7f1ef"
                    font.pixelSize: radioPage.width / 70
                    font.family: "Arial"
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width - 20
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    id: statusDot
                    width: 8; height: 8; radius: 4
                    color: "#5A3211"
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Station list
        Item {
            width: parent.width
            height: radioPage.height * 0.62

            Rectangle {
                id: listGlass
                anchors.fill: parent
                radius: radioPage.height / 50
                color: "#3D717E"
                border.width: 1
                border.color: "#50FFFFFF"
                visible: false
            }

            InnerShadow {
                id: listInner
                anchors.fill: listGlass
                source: listGlass
                horizontalOffset: -3
                verticalOffset: -3
                radius: 10
                samples: 20
                color: "#80FFFFFF"
                visible: false
            }

            DropShadow {
                anchors.fill: listGlass
                source: listInner
                horizontalOffset: 6
                verticalOffset: 6
                radius: 14
                samples: 28
                color: "#50000000"
            }

            // Loading spinner overlay
            Rectangle {
                anchors.fill: parent
                color: "#082839"
                opacity: 0.85
                visible: mediaPage.radioIsLoading
                radius: radioPage.height / 50
                z: 10

                Column {
                    anchors.centerIn: parent
                    spacing: 12

                    Canvas {
                        id: spinner
                        width: 48; height: 48
                        anchors.horizontalCenter: parent.horizontalCenter
                        onPaint: {
                            var ctx = getContext("2d")
                            var cx = width / 2, cy = height / 2, r = 18
                            ctx.clearRect(0, 0, width, height)
                            ctx.lineWidth = 4
                            ctx.lineCap = "round"
                            ctx.strokeStyle = "#D08831"
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 1.5)
                            ctx.stroke()
                        }

                        RotationAnimation on rotation {
                            from: 0; to: 360
                            duration: 800
                            loops: Animation.Infinite
                        }
                    }

                    Text {
                        text: "Searching stations..."
                        color: "#D08831"
                        font { pixelSize: radioPage.width / 55; family: "Arial"; bold: true }
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            ListView {
                id: stationList
                anchors { fill: parent; margins: 6; rightMargin: 16 }
                model: mediaPage.globalStationsModel
                clip: true
                spacing: 4
                visible: !mediaPage.radioIsLoading

                ScrollBar.vertical: ScrollBar {
                    width: 8
                    policy: ScrollBar.AsNeeded
                    interactive: true

                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: width / 2
                        color: parent.pressed ? "#964405" : "#D08831"
                        opacity: parent.pressed ? 1.0 : 0.85
                        anchors.horizontalCenter: parent.horizontalCenter
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    background: Rectangle {
                        implicitWidth: 8
                        color: "#082839"
                        radius: width / 2
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

                    width: stationList.width - 14
                    height: radioPage.height / 12
                    radius: height / 8
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    color: delegateArea.containsMouse ? "#964405" : (mediaPage.currentRadioStation && mediaPage.currentRadioStation.name === stationDelegate.name ? "#5A3211" : "#082839")
                    border.color: mediaPage.currentRadioStation && mediaPage.currentRadioStation.name === stationDelegate.name ? "#D08831" : "#3D717E"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12

                        Rectangle {
                            width: parent.height * 0.7
                            height: parent.height * 0.7
                            anchors.verticalCenter: parent.verticalCenter
                            radius: width / 5
                            color: "#3D717E"

                            Image {
                                anchors.fill: parent
                                anchors.margins: 3
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
                            width: parent.width * 0.6
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.children[0].right
                            anchors.leftMargin: 8
                            spacing: 1

                            Text {
                                text: stationDelegate.name
                                color: "#e7f1ef"
                                font { pixelSize: radioPage.width / 80; bold: true; family: "Arial" }
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: stationDelegate.country + " • " + stationDelegate.codec
                                color: "#D08831"
                                font { pixelSize: radioPage.width / 90; family: "Arial" }
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: stationDelegate.tags
                                color: "#3D717E"
                                font { pixelSize: radioPage.width / 95; family: "Arial" }
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        Rectangle {
                            width: parent.height * 0.6
                            height: parent.height * 0.6
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            radius: height / 5
                            color: playBtnArea.containsMouse ? "#082839" : "#5A3211"
                            border.color: "#D08831"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Image{
                                anchors.centerIn: parent
                                width: 20; height: 20
                                source:  mediaPage.currentRadioStation && mediaPage.currentRadioStation.name === stationDelegate.name
                                    && mediaPlayer.playbackState === MediaPlayer.PlayingState ? "qrc:/assets/icons/pause.png" : "qrc:/assets/icons/play.png"
                                fillMode: Image.PreserveAspectFit
                            }

                            MouseArea {
                                id: playBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (mediaPage.currentRadioStation && mediaPage.currentRadioStation.name === stationDelegate.name)
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

            // EMPTY STATE — sibling of ListView, not a child inside it
            Column {
                anchors.centerIn: parent
                spacing: 8
                visible: mediaPage.globalStationsModel.count === 0 && !mediaPage.radioIsLoading
                z: 5

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: mediaPage.radioSearchAttempted ? "⚠" : "📻"
                    color: "#D08831"
                    font { pixelSize: radioPage.width / 30; family: "Arial" }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: mediaPage.radioSearchAttempted
                        ? "No station found with that name."
                        : "No stations.\nSearch or filter above."
                    color: "#e7f1ef"
                    horizontalAlignment: Text.AlignHCenter
                    font { pixelSize: radioPage.width / 55; family: "Arial"; bold: true }
                }
            }
        }

        // Spacer
        Rectangle {width: parent.width; height: 3; color: "transparent" }

        // CONTROLS ROW — Back | centered Prev/Play/Next | Volume
        Row {
            id: audioContRow
            width: parent.width
            height: radioPage.height / 15
            spacing: 0

            // Back button (left) — does NOT stop playback
            Rectangle {
                id: backBtnRect
                anchors.verticalCenter: parent.verticalCenter
                width: backText.width + 40
                height: backText.height + 14
                radius: height / 3
                color: backArea.containsMouse ? "#964405" : "#5A3211"
                border.color: "#D08831"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    id: backText
                    anchors.centerIn: parent
                    text: "Back"
                    color: "#e7f1ef"
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
                    color: prevArea.containsMouse ? "#082839" : "#5A3211"
                    border.color: "#D08831"
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
                    color: playArea.containsMouse ? "#082839" : "#5A3211"
                    border.color: "#D08831"
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
                    color: nextArea.containsMouse ? "#082839" : "#5A3211"
                    border.color: "#D08831"
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
                spacing: radioPage.width / 80

                // Mute
                Rectangle {
                    id: volumeBtn
                    property bool muted: false
                    width: radioPage.width / 25
                    height: width
                    radius: width / 2
                    color: muteArea.containsMouse ? "#082839" : "#5A3211"
                    border.color: "#D08831"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: volumeBtn.muted ? "🔈" : volumeSlider.value < 0.5 ? "🔉" : "🔊"
                        font.pixelSize: (parent.width + parent.height) / 4
                        font.family: "Arial"
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
                        color: "#082839"
                        Rectangle {
                            width: volumeSlider.visualPosition * parent.width
                            height: parent.height; radius: parent.radius
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#D08831" }
                                GradientStop { position: 1.0; color: '#964405' }
                            }
                        }
                    }
                }
            }
        }
    }

    // Virtual Keyboard Popup — parented to Overlay so it isn't clipped
    Popup {
        id: keyboardPopup
        parent: Overlay.overlay
        width: radioPage.width * 0.6
        height: radioPage.height * 0.7
        anchors.centerIn: Overlay.overlay
        modal: true
        // Dim the page behind the dialog
        Overlay.modal: Rectangle {
            color: "#000000"
            opacity: 0.6
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: "#082839"
            radius: 16
            border.color: "#D08831"
            border.width: 2
        }

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            Text {
                text: "Search Station"
                font.pixelSize: radioPage.height * 0.04
                color: "#D08831"
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