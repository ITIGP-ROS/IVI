import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtMultimedia
pragma ComponentBehavior: Bound

Item {
    id: root
    signal goBack()

    property real fontSize: (width + height) / 60
    property color accentColor: "#D08831"

    // ── Injected shared player & state owner (e.g. mainWindow) ──
    required property MediaPlayer mediaPlayer
    required property var        mediaPage

    property bool btActive: mediaPage.currentMediaType === 4
    // Bluetooth is driven by the phone over AVRCP, not by mediaPlayer.
    property bool mediaPlaying: btActive
                                ? (btManager && btManager.playerStatus === "playing")
                                : mediaPlayer.playbackState === MediaPlayer.PlayingState

    // Set by VideoPage while it is showing fullscreen, so the title bar can
    // get out of the way — it is drawn over the page, not above it.
    property bool videoFullScreen: false

    WindowBar {
        id: titleBar
        z: 1
        visible: !root.videoFullScreen
        window: mainWindow
        titleName: "Media Player"
        showBackButton: true
        onBackRequested: root.goBack()
        color0: '#082839'
        color1: '#10475E'
        color2: '#3D717E'

        brightnessValue: mainWindow.appBrightness
        volumeValue: systemVolume.volume
        volumeMax: systemVolume.maxVolume
        volumeMuted: systemVolume.muted

        onBrightnessChanged: (value) => mainWindow.appBrightness = value
        onVolumeChanged: (value) => systemVolume.volume = value
        onVolumeMuteToggled: systemVolume.toggleMute()
    }

    // ============================================ Background ================================================
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: '#082839' }
            GradientStop { position: 0.5; color: '#10475E' }
            GradientStop { position: 1.0; color: '#082839' }
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

        StackView {
            id: stackView
            initialItem: mainPageComponent
            anchors.fill: parent

            // =========================================== Main Page ============================================
            Component {
                id: mainPageComponent
                Item {
                    anchors.fill: parent

                    Row {
                        id: mainRow
                        anchors.centerIn: parent
                        spacing: root.width / 20

                        MediaCard {
                            cardWidth: root.width / 5
                            cardHeight: root.height / 2.2
                            cardColSpacing: cardHeight / 12
                            accentColor: root.accentColor
                            cardRadius: mainRow.spacing / 3
                            cardBorderColor: '#50FFFFFF'
                            cardBorderWidth: 1
                            cardOpacity: 0.85
                            cardText: qsTr("Radio")
                            cardIcon: "qrc:/assets/icons/radio.png"
                            cardTextFontSize: root.fontSize * 1.1
                            cardTextFontFamily: "Arial"
                            cardTextColor: '#f8ffff'
                            cardIconWidth: cardWidth / 1.5
                            cardIconHeight: cardHeight / 1.5

                            onCardClicked: stackView.push(radioPageComponent)
                        }

                        MediaCard {
                            cardWidth: root.width / 5
                            cardHeight: root.height / 2.2
                            cardColSpacing: cardHeight / 12
                            accentColor: root.accentColor
                            cardRadius: mainRow.spacing / 3
                            cardBorderColor: '#50FFFFFF'
                            cardBorderWidth: 1
                            cardOpacity: 0.85
                            cardText: qsTr("Audio")
                            cardIcon: "qrc:/assets/icons/audio.png"
                            cardTextFontSize: root.fontSize * 1.1
                            cardTextFontFamily: "Arial"
                            cardTextColor: '#f8ffff'
                            cardIconWidth: cardWidth / 1.5
                            cardIconHeight: cardHeight / 1.5

                            onCardClicked: stackView.push(audioPageComponent)
                        }

                        MediaCard {
                            cardWidth: root.width / 5
                            cardHeight: root.height / 2.2
                            cardColSpacing: cardHeight / 12
                            accentColor: root.accentColor
                            cardRadius: mainRow.spacing / 3
                            cardBorderColor: '#50FFFFFF'
                            cardBorderWidth: 1
                            cardOpacity: 0.85
                            cardText: qsTr("Video")
                            cardIcon: "qrc:/assets/icons/video.png"
                            cardTextFontSize: root.fontSize * 1.1
                            cardTextFontFamily: "Arial"
                            cardTextColor: '#f8ffff'
                            cardIconWidth: cardWidth / 1.5
                            cardIconHeight: cardHeight / 1.5

                            onCardClicked: stackView.push(videoPageComponent)
                        }

                    }
                }
            }
        }

        // Status bar inside MediaPlayerPage (visible when on media home and something is playing)
        Rectangle {
            id: statusBar
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottomMargin: root.height / 30
            anchors.leftMargin: root.width / 15
            anchors.rightMargin: root.width / 15
            height: root.height / 12
            radius: height / 2
            color: "#5A3211"
            border.color: "#D08831"
            border.width: 1
            visible: stackView.depth === 1 && mediaPage.currentMediaType !== 0
            z: 2

            Row {
                anchors.fill: parent
                anchors.margins: height * 0.2
                anchors.leftMargin: height * 0.5
                anchors.rightMargin: height * 0.5
                spacing: root.width / 60

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.height * 0.6; height: width
                    source: "qrc:/assets/icons/bt.png"
                    fillMode: Image.PreserveAspectFit
                    visible: root.btActive
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: mediaPage.currentMediaType === 1 ? " 📻" : mediaPage.currentMediaType === 2 ? " 🎵" : " 🎬"
                    font.pixelSize: parent.height * 0.7
                    color: "#D08831"
                    visible: !root.btActive
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.55

                    Text {
                        text: mediaPage.currentMediaTitle || "Unknown"
                        color: "#e7f1ef"
                        font.pixelSize: statusBar.height * 0.3
                        font.bold: true
                        font.family: "Arial"
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: mediaPage.currentMediaSubtitle
                        color: '#518693'
                        font.pixelSize: statusBar.height * 0.21
                        font.family: "Arial"
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                Item { width: parent.width * 0.04; height: 1 }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mediaPlaying ? "Playing" : "Paused"
                    color: '#ffffff'
                    opacity: 0.6
                    font.pixelSize: statusBar.height * 0.25
                    font.family: "Arial"
                    font.bold: true
                }

                // Previous
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: statusBar.height * 0.65; height: width; radius: width / 2
                    color: statusPrevArea.containsMouse ? "#082839" : "#964405"
                    border.color: "#D08831"; border.width: 1
                    visible: mediaPage.currentMediaType === 1 || root.btActive
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Image{
                        anchors.centerIn: parent
                        width: 18; height: 18
                        source: "qrc:/assets/icons/prev.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea {
                        id: statusPrevArea; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            if (root.btActive) btManager.previous()
                            else mediaPage.globalRadioAPI.playPrevious()
                        }
                    }
                }

                // Play / Pause
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: statusBar.height * 0.65
                    height: width
                    radius: width / 2
                    color: statusPlayArea.containsMouse ? "#082839" : "#964405"
                    border.color: "#D08831"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Image{
                        anchors.centerIn: parent
                        width: 25; height: 25
                        source: mainWindow.mediaPlaying? "qrc:/assets/icons/pause.png" : "qrc:/assets/icons/play.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea {
                        id: statusPlayArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (root.btActive) {
                                if (root.mediaPlaying) btManager.pause()
                                else                   btManager.play()
                            } else if (root.mediaPlaying) mediaPlayer.pause()
                            else mediaPlayer.play()
                        }
                    }
                }

                // Stop
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: statusBar.height * 0.65
                    height: width
                    radius: width / 2
                    color: statusStopArea.containsMouse ? "#082839" : "#964405"
                    border.color: "#D08831"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Image{
                        anchors.centerIn: parent
                        width: 16; height: 16
                        source: "qrc:/assets/icons/stop.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea {
                        id: statusStopArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            // The stream lives on the phone — stop it over AVRCP
                            // and let the backend clear the state.
                            if (root.btActive) { btManager.stop(); return }
                            mediaPlayer.stop()
                            mediaPage.currentMediaType = 0
                            mediaPage.currentMediaTitle = ""
                            mediaPage.currentMediaSubtitle = ""
                            mediaPage.currentRadioStation = null
                        }
                    }
                }

                // Next
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: statusBar.height * 0.65; height: width; radius: width / 2
                    color: statusNextArea.containsMouse ? "#082839" : "#964405"
                    border.color: "#D08831"; border.width: 1
                    visible: mediaPage.currentMediaType === 1 || root.btActive
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Image{
                        anchors.centerIn: parent
                        width: 18; height: 18
                        source: "qrc:/assets/icons/next.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea {
                        id: statusNextArea; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            if (root.btActive) btManager.next()
                            else mediaPage.globalRadioAPI.playNext()
                        }
                    }
                }
            }
        }
    }

    // ============================================ Pages ===============================================
    Component {
        id: radioPageComponent
        RadioPage {
            stackView: stackView
            mediaPlayer: root.mediaPlayer
            mediaPage: root.mediaPage
        }
    }

    Component {
        id: audioPageComponent
        AudioPage {
            stackView: stackView
            mediaPlayer: root.mediaPlayer
            mediaPage: root.mediaPage
        }
    }

    Component {
        id: videoPageComponent
        VideoPage {
            stackView: stackView
            // The title bar is drawn over this page, so the video page cannot
            // hide it itself — it reports the state and we hide it here.
            onFullScreenChanged: root.videoFullScreen = fullScreen
            Component.onDestruction: root.videoFullScreen = false
        }
    }
}