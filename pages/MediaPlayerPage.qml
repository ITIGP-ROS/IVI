import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtMultimedia
pragma ComponentBehavior: Bound

Item {
    id: root
    signal goBack()

    property real fontSize: (width + height) / 60

    /*
     * Page-level accent — used by the window bar and the status bar.
     * Mint = media/audio in the Theme palette.
     */
    property color accentColor: Theme.accentMint

    // ── Injected shared player & state owner (e.g. mainWindow) ──
    required property MediaPlayer mediaPlayer
    required property var        mediaPage

    /*
     * Jump straight to one sub-page (radio / audio / video).
     *
     * Set as an initial property when the page is pushed from a voice command
     * or another page, or called directly when MediaPlayer is already on
     * screen.
     */
    property string pendingSection: ""

    function showSection(section) {
        if (stackView.currentItem && stackView.currentItem.objectName === section) return
        stackView.pop(null)
        if (section === "radio")
            stackView.push(radioPageComponent)
        else if (section === "audio")
            stackView.push(audioPageComponent)
        else if (section === "video")
            stackView.push(videoPageComponent)
    }

    Component.onCompleted: {
        if (pendingSection !== "")
            showSection(pendingSection)
    }

    property bool btActive: mediaPage.currentMediaType === 4
    // Bluetooth is driven by the phone over AVRCP, not by mediaPlayer.
    property bool mediaPlaying: btActive
                                ? (btManager && btManager.playerStatus === "playing")
                                : mediaPlayer.playbackState === MediaPlayer.PlayingState

    // Set by VideoPage while it is showing fullscreen, so the title bar can
    // get out of the way — it is drawn over the page, not above it.
    property bool videoFullScreen: false

    // Cards are sized from how many there are, mirroring the settings page
    // layout so a future fourth card cannot silently overflow.
    readonly property int  cardCount:   3
    readonly property real cardSpacing: root.width / 32
    readonly property real cardWidth:
        (root.width * 0.675 - cardSpacing * (cardCount - 1)) / cardCount
    readonly property real cardHeight: root.height / 2.3

    WindowBar {
        id: titleBar
        z: 2
        visible: !root.videoFullScreen
        window: mainWindow
        titleName: "Media Player"
        showBackButton: true
        onBackRequested: root.goBack()

        // Gradient ends follow the glass backdrop rather than the old teal.
        color0: Theme.gradientTop
        color1: Theme.gradientMid
        color2: Theme.gradientBot
        accent: root.accentColor
        titleColor: Theme.textPrimary
        surface: Theme.surface

        brightnessValue: mainWindow.appBrightness
        volumeValue: systemVolume.volume
        volumeMax: systemVolume.maxVolume
        volumeMuted: systemVolume.muted

        onBrightnessChanged: (value) => mainWindow.appBrightness = value
        onVolumeChanged: (value) => systemVolume.volume = value
        onVolumeMuteToggled: systemVolume.toggleMute()

        onWifiRequested:      mainWindow.openSettingsSection("wifi")
        onBluetoothRequested: mainWindow.openSettingsSection("bluetooth")
    }

    // ============================================ Background ================================================
    GlassBackground {
        id: background
        anchors.fill: parent

        StackView {
            id: stackView
            initialItem: mainPageComponent
            anchors.fill: parent

            // =========================================== Main Page ============================================
            Component {
                id: mainPageComponent
                Item {
                    id: app
                    anchors.fill: parent
                    // Clears the window bar.
                    anchors.topMargin: 48

                    Row {
                        id: cardRow
                        spacing: root.cardSpacing
                        anchors.centerIn: parent

                        // RADIO
                        GlassCard {
                            width: root.cardWidth
                            height: root.cardHeight
                            accent: Theme.accentAmber
                            floatAmplitude: 4
                            floatPhase: 0
                            onClicked: stackView.push(radioPageComponent)

                            Column {
                                anchors.centerIn: parent
                                spacing: parent.height * 0.06

                                IconWell {
                                    accent: Theme.accentAmber
                                    diameter: root.cardHeight * 0.32
                                    source: "qrc:/assets/icons/radio.png"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: qsTr("Radio")
                                    color: Theme.textPrimary
                                    font { bold: true; family: "Arial"; pixelSize: root.fontSize }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: qsTr("FM stations")
                                    color: Theme.textSecondary
                                    font { family: "Arial"; pixelSize: root.fontSize * 0.55 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }

                        // AUDIO
                        GlassCard {
                            width: root.cardWidth
                            height: root.cardHeight
                            accent: Theme.accentMint
                            floatAmplitude: 4
                            floatPhase: 700
                            onClicked: stackView.push(audioPageComponent)

                            Column {
                                anchors.centerIn: parent
                                spacing: parent.height * 0.06

                                IconWell {
                                    accent: Theme.accentMint
                                    diameter: root.cardHeight * 0.32
                                    source: "qrc:/assets/icons/audio.png"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: qsTr("Audio")
                                    color: Theme.textPrimary
                                    font { bold: true; family: "Arial"; pixelSize: root.fontSize }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: qsTr("Music files")
                                    color: Theme.textSecondary
                                    font { family: "Arial"; pixelSize: root.fontSize * 0.55 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }

                        // VIDEO
                        GlassCard {
                            width: root.cardWidth
                            height: root.cardHeight
                            accent: Theme.accentBlue
                            floatAmplitude: 4
                            floatPhase: 1400
                            onClicked: stackView.push(videoPageComponent)

                            Column {
                                anchors.centerIn: parent
                                spacing: parent.height * 0.06

                                IconWell {
                                    accent: Theme.accentBlue
                                    diameter: root.cardHeight * 0.32
                                    source: "qrc:/assets/icons/video.png"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: qsTr("Video")
                                    color: Theme.textPrimary
                                    font { bold: true; family: "Arial"; pixelSize: root.fontSize }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: qsTr("Video player")
                                    color: Theme.textSecondary
                                    font { family: "Arial"; pixelSize: root.fontSize * 0.55 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }
                    }
                }
            }
        }

        // Status bar inside MediaPlayerPage (visible when on media home and something is playing)
        // Re-skinned as a glass pill to match the new backdrop.
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
            color: Theme.glassFill
            border.color: Theme.glassBorder
            border.width: 1
            visible: stackView.depth === 1 && mediaPage.currentMediaType !== 0
            z: 2

            // Accent halo behind the pill, same idea as GlassCard's halo.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: parent.radius + 2
                z: -1
                color: root.accentColor
                opacity: 0.07
            }

            Row {
                anchors.fill: parent
                anchors.margins: parent.height * 0.2
                anchors.leftMargin: parent.height * 0.5
                anchors.rightMargin: parent.height * 0.5
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
                    color: root.accentColor
                    visible: !root.btActive
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.55

                    Text {
                        text: mediaPage.currentMediaTitle || "Unknown"
                        color: Theme.textPrimary
                        font.pixelSize: statusBar.height * 0.3
                        font.bold: true
                        font.family: "Arial"
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: mediaPage.currentMediaSubtitle
                        color: Theme.textSecondary
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
                    color: Theme.textPrimary
                    opacity: 0.6
                    font.pixelSize: statusBar.height * 0.25
                    font.family: "Arial"
                    font.bold: true
                }

                // Previous
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: statusBar.height * 0.65; height: width; radius: width / 2
                    color: statusPrevArea.containsMouse
                           ? Theme.tint(root.accentColor, 0.25)
                           : Theme.glassFill
                    border.color: Theme.tint(root.accentColor, 0.6)
                    border.width: 1
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
                    color: statusPlayArea.containsMouse
                           ? Theme.tint(root.accentColor, 0.25)
                           : Theme.glassFill
                    border.color: Theme.tint(root.accentColor, 0.6)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Image{
                        anchors.centerIn: parent
                        width: 18; height: 18
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
                    color: statusStopArea.containsMouse
                           ? Theme.tint(root.accentColor, 0.25)
                           : Theme.glassFill
                    border.color: Theme.tint(root.accentColor, 0.6)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Image{
                        anchors.centerIn: parent
                        width: 18; height: 18
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
                    color: statusNextArea.containsMouse
                           ? Theme.tint(root.accentColor, 0.25)
                           : Theme.glassFill
                    border.color: Theme.tint(root.accentColor, 0.6)
                    border.width: 1
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
            objectName: "radio"
            stackView: stackView
            mediaPlayer: root.mediaPlayer
            mediaPage: root.mediaPage
        }
    }

    Component {
        id: audioPageComponent
        AudioPage {
            objectName: "audio"
            stackView: stackView
            mediaPlayer: root.mediaPlayer
            mediaPage: root.mediaPage
        }
    }

    Component {
        id: videoPageComponent
        VideoPage {
            objectName: "video"
            stackView: stackView
            // The title bar is drawn over this page, so the video page cannot
            // hide it itself — it reports the state and we hide it here.
            onFullScreenChanged: root.videoFullScreen = fullScreen
            Component.onDestruction: root.videoFullScreen = false
        }
    }
}