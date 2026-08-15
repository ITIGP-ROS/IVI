import QtQuick
import QtQuick.Controls
import QtMultimedia
pragma ComponentBehavior: Bound

/*
 * Audio player: local library, Bluetooth (A2DP/AVRCP from the phone) and USB.
 *
 * Same skeleton as the radio and video pages — a narrow left rail over the full
 * height, a bordered content panel beside it, and a glass transport pill along
 * the bottom of that panel. The rail here holds the three sources.
 *
 * Bluetooth is the odd one: the audio is on the phone, not in our MediaPlayer,
 * so that view has no progress bar and its transport talks to btManager rather
 * than to the player.
 */
Rectangle {
    id: audioPage
    required property StackView stackView
    required property MediaPlayer mediaPlayer
    required property var        mediaPage
    anchors.fill: parent
    color: "transparent"

    readonly property color accent: Theme.accentMint

    // ---- geometry ----------------------------------------------------------
    // Shared with RadioPage and VideoPage; the three panels land on the same
    // rectangle, which is what makes them read as one screen.
    readonly property real railW:  audioPage.width / 5
    readonly property real topPad: audioPage.height / 10
    readonly property real panelH: audioPage.height - audioPage.height / 6

    // ---- sources -----------------------------------------------------------
    // Values kept from the version this replaces (0 local, 2 bluetooth, 3 usb)
    // so nothing that reads `source` outside this file has to change.
    readonly property int srcLocal: 0
    readonly property int srcBt:    2
    readonly property int srcUsb:   3
    property int source: srcLocal

    readonly property bool btView: audioPage.source === audioPage.srcBt
    readonly property bool btConnected: btManager && btManager.connected
    readonly property bool btPlaying: audioPage.btConnected
                                      && btManager.playerStatus === "playing"

    // This page owns the shared player only while it is the audio source
    // (currentMediaType 2) — the radio page uses the same MediaPlayer.
    readonly property bool audioActive: mediaPage.currentMediaType === 2
    readonly property bool audioPlaying: audioActive
                                         && mediaPlayer.playbackState === MediaPlayer.PlayingState

    // Whichever transport is in charge of this view.
    readonly property bool nowPlaying: audioPage.btView ? audioPage.btPlaying
                                                        : audioPage.audioPlaying

    property string errorMessage: ""
    property int    currentFileIndex: -1

    Connections {
        target: audioPage.mediaPlayer

        function onErrorOccurred(error, errorString) {
            if (audioPage.mediaPage.currentMediaType !== 2) return
            switch (error) {
            case MediaPlayer.NetworkError:
                audioPage.errorMessage = "Cannot reach the server — check your connection"
                break
            case MediaPlayer.FormatError:
                audioPage.errorMessage = "Unsupported audio format"
                break
            case MediaPlayer.AccessDeniedError:
                audioPage.errorMessage = "Access denied — the server rejected the request"
                break
            case MediaPlayer.ResourceError:
                audioPage.errorMessage = "Invalid URL or resource not found"
                break
            default:
                audioPage.errorMessage = errorString
            }
        }

        function onPlaybackStateChanged() {
            if (audioPage.mediaPlayer.playbackState === MediaPlayer.PlayingState
                    && audioPage.mediaPage.currentMediaType === 2)
                audioPage.errorMessage = ""
        }
    }

    function playFile(path, name, origin, index) {
        audioPage.errorMessage = ""
        audioPage.mediaPlayer.source = "file://" + path
        audioPage.mediaPage.currentMediaType = 2
        audioPage.mediaPage.currentMediaTitle = name
        audioPage.mediaPage.currentMediaSubtitle = origin
        audioPage.currentFileIndex = index
        audioPage.mediaPlayer.play()
    }

    function stripExtension(name) { return name.replace(/\.[^.]+$/, "") }

    // "MP3", "FLAC". Used as the row subtitle: repeating "Local library" or the
    // drive name down every row of a list that is entirely one or the other
    // says nothing, where the format is the one thing that differs.
    function fileFormat(name) {
        var m = String(name).match(/\.([^.]+)$/)
        return m ? m[1].toUpperCase() : ""
    }

    function isCurrent(path) {
        return audioPage.mediaPlayer.source.toString() === ("file://" + path)
    }

    function formatTime(ms) {
        if (ms <= 0) return "0:00"
        var totalSec = Math.floor(ms / 1000)
        var min = Math.floor(totalSec / 60)
        var sec = totalSec % 60
        return min + ":" + (sec < 10 ? "0" + sec : sec)
    }

    // Step through the USB list in either direction, wrapping. Both transport
    // buttons did this inline with the sign flipped and the bounds check
    // written twice.
    function stepUsb(delta) {
        if (!usbManager.connected || usbManager.audioFiles.length === 0) return
        var n = usbManager.audioFiles.length
        var i = (audioPage.currentFileIndex + delta + n) % n
        var path = usbManager.audioFiles[i]
        audioPage.playFile(path, audioPage.stripExtension(usbManager.fileName(path)),
                           "USB", i)
    }

    // ========================================== Left rail =========================================
    Item {
        id: leftRail
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: audioPage.topPad
        width: audioPage.railW
        height: audioPage.panelH

        Column {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.8
            spacing: audioPage.height / 40

            SourceTab {
                width: parent.width
                height: audioPage.height / 14
                accent: audioPage.accent
                kind: "folder"
                label: "Local"
                fontSize: audioPage.width / 60
                selected: audioPage.source === audioPage.srcLocal
                onClicked: audioPage.source = audioPage.srcLocal
            }

            SourceTab {
                width: parent.width
                height: audioPage.height / 14
                accent: audioPage.accent
                // The Bluetooth mark already ships as a PNG that matches the
                // rest of the app, so it stays a bitmap where the others are
                // drawn.
                iconSource: "qrc:/assets/icons/bt.png"
                label: "Bluetooth"
                fontSize: audioPage.width / 60
                selected: audioPage.source === audioPage.srcBt
                onClicked: audioPage.source = audioPage.srcBt
            }

            SourceTab {
                width: parent.width
                height: audioPage.height / 14
                accent: audioPage.accent
                kind: "usb"
                label: "USB"
                fontSize: audioPage.width / 60
                selected: audioPage.source === audioPage.srcUsb
                onClicked: audioPage.source = audioPage.srcUsb
            }
        }

        // Level with the transport bar across the panel. They sit in different
        // parents, so the alignment has to be arithmetic rather than an anchor.
        BackButton {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: audioPage.height / 30
                                  + (controller.height - height) / 2
            accent: Theme.danger
            fontSize: audioPage.width / 55
            onClicked: audioPage.stackView.pop()
        }
    }

    // ========================================== Content panel =========================================
    Rectangle {
        id: rightPanel
        width: audioPage.width - leftRail.width - audioPage.width / 10
        height: audioPage.panelH
        anchors.top: parent.top
        anchors.topMargin: audioPage.topPad
        anchors.left: leftRail.right
        anchors.leftMargin: audioPage.width / 20
        color: "transparent"
        border.color: Theme.glassBorder
        border.width: 1
        radius: height / 20

        readonly property real inset: rightPanel.width / 26

        // ---- content ----
        // Bottom is anchored to the now bar whether or not it is showing: an
        // invisible item still has a position, and switching the anchor target
        // on a state change makes the panel jump.
        Item {
            id: content
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: rightPanel.inset
            anchors.bottom: nowBar.top
            // Reclaims the now bar's band in the Bluetooth view, where it is
            // hidden. A negative margin rather than re-anchoring to the
            // transport bar: switching an anchor target on a state change makes
            // the panel jump instead of settling.
            anchors.bottomMargin: audioPage.btView
                                  ? -(nowBar.height + audioPage.height / 50)
                                  : audioPage.height / 40

            // ------------------------------------------------ Local
            Item {
                anchors.fill: parent
                visible: audioPage.source === audioPage.srcLocal

                Text {
                    id: localHeader
                    anchors.top: parent.top
                    anchors.right: parent.right
                    text: musicLibrary.count + (musicLibrary.count === 1 ? " track" : " tracks")
                    color: Theme.textSecondary
                    font { pixelSize: audioPage.width / 90; family: "Arial" }
                    visible: musicLibrary.count > 0
                }

                EmptyState {
                    glyphSize: audioPage.height / 8
                    titleSize: audioPage.width / 55
                    hintSize: audioPage.width / 90
                    anchors.centerIn: parent
                    visible: musicLibrary.count === 0
                    kind: "music"
                    tint: Theme.tint(audioPage.accent, 0.75)
                    title: "No audio files"
                    hint: "Add music to the library folder and it will appear here."
                }

                ListView {
                    id: localList
                    anchors.fill: parent
                    anchors.topMargin: localHeader.visible
                                       ? localHeader.height + audioPage.height / 60 : 0
                    clip: true
                    visible: musicLibrary.count > 0
                    model: musicLibrary
                    spacing: 6

                    ScrollBar.vertical: GlassScrollBar {
                        id: localBar
                        accent: audioPage.accent
                        view: localList
                        thickness: audioPage.width / 110
                    }

                    delegate: TrackRow {
                        required property string fileName
                        required property string filePath
                        required property int    index

                        width: localList.width - localBar.width * 2
                        height: audioPage.height / 11
                        accent: audioPage.accent
                        kind: "music"
                        title: audioPage.stripExtension(fileName)
                        subtitle: audioPage.fileFormat(fileName)
                        active: audioPage.isCurrent(filePath)
                        playing: active && audioPage.audioPlaying
                        onClicked: audioPage.playFile(filePath,
                                                      audioPage.stripExtension(fileName),
                                                      "Local Audio", index)
                    }
                }
            }

            // ------------------------------------------------ Bluetooth
            Item {
                anchors.fill: parent
                visible: audioPage.btView

                Connections {
                    target: btManager
                    function onTrackInfoChanged()    { console.log("Track changed:", btManager.trackTitle) }
                    function onPlayerStatusChanged() { console.log("Status:", btManager.playerStatus) }
                    function onConnectedChanged()    { console.log("Connected:", btManager.connected) }
                }

                EmptyState {
                    glyphSize: audioPage.height / 8
                    titleSize: audioPage.width / 55
                    hintSize: audioPage.width / 90
                    anchors.centerIn: parent
                    visible: !audioPage.btConnected
                    kind: "bluetooth"
                    tint: Theme.textSecondary
                    title: "No device connected"
                    hint: "Pair a phone from Settings, then play something on it."
                }

                GlassCard {
                    anchors.centerIn: parent
                    width: Math.min(parent.width * 0.86, parent.height * 1.7)
                    height: Math.min(parent.height * 0.88, parent.width * 0.52)
                    accent: audioPage.accent
                    interactive: false
                    visible: audioPage.btConnected

                    Row {
                        anchors.centerIn: parent
                        width: parent.width * 0.86
                        spacing: parent.width * 0.06

                        Item {
                            id: discFrame
                            width: Math.min(parent.width * 0.32, parent.parent.height * 0.62)
                            height: width
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                id: btPulse
                                anchors.centerIn: parent
                                width: parent.width + 16
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: audioPage.accent
                                border.width: 2
                                opacity: 0
                                SequentialAnimation on opacity {
                                    running: audioPage.btPlaying
                                    loops: Animation.Infinite
                                    // Without this the ring keeps whatever
                                    // opacity it stopped at and stays lit around
                                    // a paused phone.
                                    onStopped: btPulse.opacity = 0
                                    NumberAnimation { to: 0.45; duration: 1100; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 0.0;  duration: 1100; easing.type: Easing.InOutSine }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: Theme.tint(audioPage.accent, audioPage.btPlaying ? 0.16 : 0.07)
                                border.color: Theme.tint(audioPage.accent,
                                                         audioPage.btPlaying ? 0.55 : 0.25)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 250 } }

                                Image {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.42
                                    height: width
                                    source: "qrc:/assets/icons/bt.png"
                                    fillMode: Image.PreserveAspectFit
                                    mipmap: true
                                }
                            }
                        }

                        Column {
                            width: parent.width - discFrame.width - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: audioPage.height / 44

                            // Device chip
                            Rectangle {
                                width: Math.min(deviceName.implicitWidth + parent.width * 0.14,
                                                parent.width)
                                height: deviceName.implicitHeight + audioPage.height / 46
                                radius: height / 2
                                color: Theme.tint(audioPage.accent, 0.16)
                                border.color: Theme.tint(audioPage.accent, 0.5)
                                border.width: 1

                                MediaGlyph {
                                    id: btChipGlyph
                                    anchors.left: parent.left
                                    anchors.leftMargin: parent.height * 0.34
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.height * 0.46
                                    height: width
                                    kind: "bluetooth"
                                    tint: audioPage.accent
                                }

                                Text {
                                    id: deviceName
                                    anchors.left: btChipGlyph.right
                                    anchors.leftMargin: parent.height * 0.28
                                    anchors.right: parent.right
                                    anchors.rightMargin: parent.height * 0.34
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: btManager ? btManager.deviceName : ""
                                    color: audioPage.accent
                                    font { pixelSize: audioPage.width / 90; family: "Arial"; bold: true }
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                width: parent.width
                                text: btManager && btManager.trackTitle !== ""
                                      ? btManager.trackTitle : "Play something on your phone"
                                color: btManager && btManager.trackTitle !== ""
                                       ? Theme.textPrimary : Theme.textSecondary
                                font {
                                    pixelSize: audioPage.width / 52
                                    family: "Arial"
                                    bold: btManager && btManager.trackTitle !== ""
                                }
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: {
                                    if (!btManager) return ""
                                    if (btManager.trackArtist !== "" && btManager.trackAlbum !== "")
                                        return btManager.trackArtist + "   ·   " + btManager.trackAlbum
                                    return btManager.trackArtist
                                }
                                color: Theme.textSecondary
                                font { pixelSize: audioPage.width / 80; family: "Arial" }
                                wrapMode: Text.WordWrap
                                maximumLineCount: 1
                                elide: Text.ElideRight
                            }

                            // Status chip, matching the radio page's stream dot.
                            Row {
                                spacing: 10
                                visible: btManager && btManager.playerStatus !== ""

                                Rectangle {
                                    id: btDot
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    color: audioPage.btPlaying ? Theme.success : Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: 200 } }

                                    SequentialAnimation on opacity {
                                        running: audioPage.btPlaying
                                        loops: Animation.Infinite
                                        onStopped: btDot.opacity = 1
                                        NumberAnimation { to: 0.3; duration: 620; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutSine }
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: btManager
                                          ? btManager.playerStatus.charAt(0).toUpperCase()
                                            + btManager.playerStatus.slice(1) : ""
                                    color: audioPage.btPlaying ? Theme.success : Theme.textSecondary
                                    font { pixelSize: audioPage.width / 95; family: "Arial"; bold: true }
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------ USB
            Item {
                anchors.fill: parent
                visible: audioPage.source === audioPage.srcUsb

                EmptyState {
                    glyphSize: audioPage.height / 8
                    titleSize: audioPage.width / 55
                    hintSize: audioPage.width / 90
                    anchors.centerIn: parent
                    visible: !usbManager.connected && !usbManager.scanning
                    kind: "usb"
                    tint: Theme.textSecondary
                    title: "No USB device"
                    hint: "Plug in a stick or a phone and its audio will be listed here."
                }

                // ---- scanning ----
                Item {
                    anchors.fill: parent
                    visible: usbManager.scanning
                    z: 5

                    Column {
                        anchors.centerIn: parent
                        spacing: audioPage.height / 40

                        Spinner {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: audioPage.height / 12
                            height: width
                            tint: audioPage.accent
                            running: usbManager.scanning
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Scanning " + usbManager.driveName + "…"
                            color: Theme.textPrimary
                            font { pixelSize: audioPage.width / 62; family: "Arial"; bold: true }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: usbManager.audioFiles.length > 0
                                  ? usbManager.audioFiles.length + " audio files so far"
                                  : "This can take a moment for phones (MTP)"
                            color: Theme.textSecondary
                            font { pixelSize: audioPage.width / 95; family: "Arial" }
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: cancelText.width * 2.4
                            height: cancelText.height + cancelText.height * 0.7
                            radius: height / 2
                            color: cancelArea.containsMouse ? Theme.tint(Theme.danger, 0.4)
                                                            : Theme.glassFill
                            border.color: Theme.danger
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                id: cancelText
                                anchors.centerIn: parent
                                text: "Cancel scan"
                                color: Theme.textPrimary
                                font { pixelSize: audioPage.width / 75; family: "Arial"; bold: true }
                            }

                            MouseArea {
                                id: cancelArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: usbManager.disconnectDevice()
                            }
                        }
                    }
                }

                // ---- files ----
                Item {
                    anchors.fill: parent
                    visible: usbManager.connected && !usbManager.scanning

                    Row {
                        id: driveHeader
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: audioPage.width / 90

                        MediaGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            width: audioPage.width / 52
                            height: width
                            kind: "usb"
                            tint: audioPage.accent
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: usbManager.driveName
                            color: audioPage.accent
                            font { pixelSize: audioPage.width / 60; family: "Arial"; bold: true }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: usbManager.audioFiles.length
                                  + (usbManager.audioFiles.length === 1 ? " file" : " files")
                            color: Theme.textSecondary
                            font { pixelSize: audioPage.width / 90; family: "Arial" }
                        }
                    }

                    EmptyState {
                        glyphSize: audioPage.height / 8
                        titleSize: audioPage.width / 55
                        hintSize: audioPage.width / 90
                        anchors.centerIn: parent
                        visible: usbManager.audioFiles.length === 0
                        kind: "music"
                        tint: Theme.textSecondary
                        title: "No audio on this device"
                        hint: "The drive was read, but nothing playable turned up."
                    }

                    ListView {
                        id: usbList
                        anchors.fill: parent
                        anchors.topMargin: driveHeader.height + audioPage.height / 40
                        clip: true
                        visible: usbManager.audioFiles.length > 0
                        model: usbManager.audioFiles
                        spacing: 6

                        ScrollBar.vertical: GlassScrollBar {
                            id: usbBar
                            accent: audioPage.accent
                            view: usbList
                            thickness: audioPage.width / 110
                        }

                        delegate: TrackRow {
                            required property string modelData
                            required property int    index

                            width: usbList.width - usbBar.width * 2
                            height: audioPage.height / 11
                            accent: audioPage.accent
                            kind: "music"
                            title: audioPage.stripExtension(usbManager.fileName(modelData))
                            subtitle: audioPage.fileFormat(modelData)
                            active: audioPage.isCurrent(modelData)
                            playing: active && audioPage.audioPlaying
                            onClicked: audioPage.playFile(
                                             modelData,
                                             audioPage.stripExtension(usbManager.fileName(modelData)),
                                             "USB", index)
                        }
                    }
                }
            }
        }

        // ---- now playing + progress ----
        Item {
            id: nowBar
            anchors.bottom: controller.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: rightPanel.inset
            anchors.rightMargin: rightPanel.inset
            anchors.bottomMargin: audioPage.height / 50
            // Just the title row, a small gap and the scrubber — the same
            // height the video page's bar uses. It was height/9, which left a
            // dead band between the two that pushed the list up for nothing.
            height: audioPage.height / 12
            // Bluetooth playback is driven by the phone, so there is no
            // position to scrub and nothing here to show.
            visible: !audioPage.btView

            MediaGlyph {
                id: errIcon
                anchors.left: parent.left
                anchors.verticalCenter: nowTitle.verticalCenter
                width: audioPage.width / 72
                height: width
                kind: "warning"
                tint: Theme.danger
                accent: Theme.danger
                visible: audioPage.errorMessage !== ""
            }

            Text {
                id: nowTitle
                anchors.top: parent.top
                anchors.left: errIcon.visible ? errIcon.right : parent.left
                anchors.leftMargin: errIcon.visible ? audioPage.width / 140 : 0
                anchors.right: nowTime.left
                anchors.rightMargin: audioPage.width / 60
                text: audioPage.errorMessage !== "" ? audioPage.errorMessage
                    : audioPage.mediaPage.currentMediaTitle !== ""
                      ? audioPage.mediaPage.currentMediaTitle
                      : "Nothing playing"
                color: audioPage.errorMessage !== "" ? Theme.danger
                     : audioPage.mediaPage.currentMediaTitle !== "" ? Theme.textPrimary
                                                                    : Theme.textSecondary
                font {
                    pixelSize: audioPage.width / 68
                    family: "Arial"
                    bold: audioPage.mediaPage.currentMediaTitle !== ""
                }
                elide: Text.ElideRight
            }

            Text {
                id: nowTime
                anchors.top: parent.top
                anchors.right: parent.right
                text: audioPage.formatTime(audioPage.mediaPlayer.position) + "  /  "
                      + audioPage.formatTime(audioPage.mediaPlayer.duration)
                color: Theme.textSecondary
                font { pixelSize: audioPage.width / 90; family: "Arial" }
            }

            GlassSlider {
                id: progressSlider
                // Fills everything under the title rather than taking a fixed
                // 23 px: the gap between the two was dead area, and a scrubber
                // is the control on this page most worth being able to hit.
                anchors.top: nowTitle.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                accent: audioPage.accent
                handleSize: 14
                from: 0
                to: audioPage.mediaPlayer.duration > 0 ? audioPage.mediaPlayer.duration : 1
                value: audioPage.mediaPlayer.position
                enabled: audioPage.mediaPlayer.duration > 0
                showHandle: audioPage.mediaPlayer.duration > 0

                onMoved: audioPage.mediaPlayer.position = value
            }
        }

        // ---- transport ----
        Rectangle {
            id: controller
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: audioPage.height / 30
            height: audioPage.height / 11
            radius: height / 2
            color: Theme.glassFill
            border.color: Theme.glassBorder
            border.width: 1

            // Accent halo, the same trick GlassCard uses — it lifts the bar off
            // the backdrop without painting the bar itself.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: parent.radius + 2
                z: -1
                color: audioPage.accent
                opacity: 0.07
            }

            // ---- volume, left ----
            TransportButton {
                id: muteBtn
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: controller.height * 0.6
                accent: audioPage.accent
                diameter: controller.height * 0.6
                visible: !audioPage.btView
                iconSource: audioPage.mediaPlayer.audioOutput.muted
                            ? "qrc:/assets/icons/volumedown.png"
                            : "qrc:/assets/icons/volumeup.png"
                onClicked: audioPage.mediaPlayer.audioOutput.muted =
                           !audioPage.mediaPlayer.audioOutput.muted
            }

            GlassSlider {
                id: volumeSlider
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: muteBtn.right
                anchors.leftMargin: controller.width / 60
                width: controller.width / 7
                visible: !audioPage.btView
                accent: audioPage.accent
                from: 0
                to: 1
                value: 0.6

                onValueChanged: {
                    audioPage.mediaPlayer.audioOutput.volume = value
                    audioPage.mediaPlayer.audioOutput.muted = false
                }
            }

            // ---- transport, centre ----
            Row {
                anchors.centerIn: parent
                spacing: controller.width / 34

                TransportButton {
                    anchors.verticalCenter: parent.verticalCenter
                    accent: audioPage.accent
                    diameter: controller.height * 0.6
                    iconSource: "qrc:/assets/icons/prev.png"
                    onClicked: {
                        if (audioPage.btView && audioPage.btConnected) btManager.previous()
                        else if (audioPage.source === audioPage.srcUsb) audioPage.stepUsb(-1)
                        else audioPage.mediaPlayer.position = 0
                    }
                }

                TransportButton {
                    anchors.verticalCenter: parent.verticalCenter
                    accent: audioPage.accent
                    diameter: controller.height * 0.78
                    ringWidth: 2
                    iconScale: 0.44
                    iconSource: audioPage.nowPlaying ? "qrc:/assets/icons/pause.png"
                                                     : "qrc:/assets/icons/play.png"
                    onClicked: {
                        if (audioPage.btView) {
                            if (!audioPage.btConnected) return
                            if (audioPage.btPlaying) btManager.pause()
                            else                     btManager.play()
                        } else if (audioPage.audioPlaying) {
                            audioPage.mediaPlayer.pause()
                        } else {
                            audioPage.mediaPlayer.play()
                        }
                    }
                }

                TransportButton {
                    anchors.verticalCenter: parent.verticalCenter
                    accent: audioPage.accent
                    diameter: controller.height * 0.6
                    iconSource: "qrc:/assets/icons/next.png"
                    onClicked: {
                        if (audioPage.btView && audioPage.btConnected) btManager.next()
                        else if (audioPage.source === audioPage.srcUsb) audioPage.stepUsb(1)
                        else audioPage.mediaPlayer.position = audioPage.mediaPlayer.duration
                    }
                }
            }

            // ---- speed, right ----
            TransportButton {
                id: speedBtn
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: speedSlider.left
                anchors.rightMargin: controller.width / 60
                accent: audioPage.accent
                diameter: controller.height * 0.6
                visible: !audioPage.btView
                label: audioPage.mediaPlayer.playbackRate.toFixed(1) + "x"
                labelSize: controller.height * 0.24
                onClicked: speedSlider.value = 1
            }

            GlassSlider {
                id: speedSlider
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: controller.height * 0.6
                width: controller.width / 8
                visible: !audioPage.btView
                accent: audioPage.accent
                // 0.5–2.0, where this used to run to 8x. Nothing is listenable
                // above 2x, and with that range 93% of the travel sat above it —
                // which made 1.0x impossible to hit on a touch panel.
                from: 0.5
                to: 2.0
                value: 1

                onValueChanged: audioPage.mediaPlayer.playbackRate = value
            }
        }
    }
}
