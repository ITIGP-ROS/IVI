import QtQuick
import QtQuick.Controls
import QtMultimedia
pragma ComponentBehavior: Bound

/*
 * Video player: local library and USB.
 *
 * Same skeleton as the radio and audio pages — narrow left rail, bordered
 * content panel, glass transport pill along the bottom of it — with one extra
 * mode: fullscreen folds the rail, the panel chrome, the transport bar and the
 * window title bar away, leaving the picture and a single minimise button.
 */
Rectangle {
    id: videoPage
    required property StackView stackView
    anchors.fill: parent
    color: "transparent"

    readonly property color accent: Theme.accentBlue

    // ---- geometry ----------------------------------------------------------
    // Shared with RadioPage and AudioPage. Fullscreen collapses the insets to
    // zero rather than re-targeting anchors, so the change can be animated.
    readonly property real railW:  videoPage.width / 5
    readonly property real topPad: videoPage.height / 10
    readonly property real panelH: videoPage.height - videoPage.height / 6

    readonly property int srcLocal: 0
    readonly property int srcUsb:   1
    property int source: srcLocal

    /*
     * MediaPlayerPage watches this to hide its WindowBar, which is drawn over
     * this page and would otherwise sit on top of the picture.
     */
    property bool fullScreen: false

    /*
     * Fullscreen chrome.
     *
     * The minimise button used to be dim until hovered, which on a touch panel
     * means dim forever — there is no pointer to hover with, so the one control
     * left on screen was permanently at 45% over a picture that could be any
     * colour. It is shown outright now and only settles back after a few idle
     * seconds, never to nothing: a control you cannot see is a control that is
     * not there. A tap anywhere on the picture brings it straight back.
     */
    property bool chromeShown: true

    function revealChrome() {
        videoPage.chromeShown = true
        chromeTimer.restart()
    }

    // A Connections rather than an `onFullScreenChanged` handler on the root:
    // MediaPlayerPage assigns that same handler at the instantiation site to
    // fold its title bar away, and the outer assignment would replace this one.
    Connections {
        target: videoPage
        function onFullScreenChanged() { videoPage.revealChrome() }
    }

    Timer {
        id: chromeTimer
        interval: 4000
        running: videoPage.fullScreen && videoPage.chromeShown
        onTriggered: videoPage.chromeShown = false
    }

    // Stop playback and show the library list again. The Local tab has no file
    // picker, so this is how you get back to choosing a video.
    function showLocalLibrary() {
        videoPlayer.stop()
        videoPlayer.source = ""
        videoPlayer.videoSelected = false
        videoPlayer.currentFileIndex = -1
        videoPage.fullScreen = false
    }

    function stripExtension(name) { return name.replace(/\.[^.]+$/, "") }

    // "MP4", "MKV". Used as the row subtitle: repeating "Local library" or the
    // drive name down every row of a list that is entirely one or the other
    // says nothing, where the format is the one thing that differs.
    function fileFormat(name) {
        var m = String(name).match(/\.([^.]+)$/)
        return m ? m[1].toUpperCase() : ""
    }

    function isCurrent(path) {
        return videoPlayer.source.toString() === ("file://" + path)
    }

    function playFile(path, index) {
        videoPlayer.source = "file://" + path
        videoPlayer.videoSelected = true
        videoPlayer.currentFileIndex = index
        videoPlayer.play()
    }

    // Step through the USB list in either direction, wrapping. Both transport
    // buttons did this inline with the sign flipped and the bounds check
    // written out twice.
    function stepUsb(delta) {
        if (!usbManager.connected || usbManager.videoFiles.length === 0) return
        var n = usbManager.videoFiles.length
        var i = (videoPlayer.currentFileIndex + delta + n) % n
        videoPage.playFile(usbManager.videoFiles[i], i)
    }

    function formatTime(ms) {
        if (ms <= 0) return "0:00"
        var totalSec = Math.floor(ms / 1000)
        var min = Math.floor(totalSec / 60)
        var sec = totalSec % 60
        return min + ":" + (sec < 10 ? "0" + sec : sec)
    }

    // Escape and a double tap on the picture are alternatives to the button —
    // worth having when the only control on screen is one small icon.
    Shortcut {
        sequence: "Escape"
        enabled: videoPage.fullScreen
        onActivated: videoPage.fullScreen = false
    }

    MediaPlayer {
        id: videoPlayer
        audioOutput: AudioOutput { id: audioOut; volume: 0.7 }
        videoOutput: videoOut

        property bool   videoSelected: false
        property string errorMessage: ""
        property int    currentFileIndex: -1

        onErrorOccurred: function (error, errorString) {
            videoSelected = false
            // Both sources are local files, so the wording is about files, not
            // servers. Anything else falls through to the player's own string
            // rather than being dressed up in a guess.
            switch (error) {
            case MediaPlayer.FormatError:
                errorMessage = "Unsupported video format"
                break
            case MediaPlayer.AccessDeniedError:
                errorMessage = "Cannot read the file — permission denied"
                break
            case MediaPlayer.ResourceError:
                errorMessage = "File not found or unreadable"
                break
            default:
                errorMessage = errorString
            }
        }

        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.PlayingState)
                errorMessage = ""
        }
    }

    // ========================================== Left rail =========================================
    Item {
        id: leftRail
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: videoPage.topPad
        width: videoPage.railW
        height: videoPage.panelH
        visible: !videoPage.fullScreen

        Column {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.8
            spacing: videoPage.height / 40

            SourceTab {
                width: parent.width
                height: videoPage.height / 14
                accent: videoPage.accent
                kind: "folder"
                label: "Local"
                fontSize: videoPage.width / 60
                selected: videoPage.source === videoPage.srcLocal
                onClicked: videoPage.source = videoPage.srcLocal
            }

            SourceTab {
                width: parent.width
                height: videoPage.height / 14
                accent: videoPage.accent
                kind: "usb"
                label: "USB"
                fontSize: videoPage.width / 60
                selected: videoPage.source === videoPage.srcUsb
                onClicked: {
                    videoPage.source = videoPage.srcUsb
                    if (usbManager.connected && usbManager.videoFiles.length === 0
                            && !usbManager.scanning)
                        usbManager.scanFiles()
                }
            }
        }

        // Level with the transport bar across the panel. The version this
        // replaces padded a spacer column by a row height plus a spacing to get
        // here, which had to be re-derived whenever a source was added.
        BackButton {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: videoPage.height / 30
                                  + (videoController.height - height) / 2
            accent: Theme.danger
            fontSize: videoPage.width / 55
            onClicked: videoPage.stackView.pop()
        }
    }

    // ========================================== Content panel =========================================
    Rectangle {
        id: rightPanel

        // Anchored to the page rather than to the rail, so going fullscreen
        // only changes margins — animatable numbers — instead of re-targeting
        // an anchor, which would snap.
        readonly property real insetLeft:   videoPage.fullScreen
                                            ? 0 : videoPage.railW + videoPage.width / 20
        readonly property real insetRight:  videoPage.fullScreen ? 0 : videoPage.width / 20
        readonly property real insetTop:    videoPage.fullScreen ? 0 : videoPage.topPad
        readonly property real insetBottom: videoPage.fullScreen ? 0 : videoPage.height / 15

        readonly property real inset: rightPanel.width / 26

        width: videoPage.width - insetLeft - insetRight
        height: videoPage.height - insetTop - insetBottom
        anchors.top: parent.top
        anchors.topMargin: insetTop
        anchors.left: parent.left
        anchors.leftMargin: insetLeft

        // Black behind the picture in fullscreen: a video whose aspect ratio
        // does not match the screen is letterboxed, and the page gradient
        // showing through those bars looks like a rendering fault.
        color: videoPage.fullScreen ? "#000000" : "transparent"
        border.color: Theme.glassBorder
        border.width: videoPage.fullScreen ? 0 : 1
        radius: videoPage.fullScreen ? 0 : height / 20

        Behavior on width  { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }
        Behavior on anchors.topMargin  { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }
        Behavior on anchors.leftMargin { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

        // ---- picture ----
        VideoOutput {
            id: videoOut
            z: 1
            anchors.fill: parent
            /*
             * Windowed, the picture sits above the controls. Fullscreen, it
             * takes the whole panel and the controls are gone.
             *
             * The inset here is roughly half the panel's: the picture is
             * letterboxed inside whatever box it is given, so every pixel of
             * padding comes straight off the picture. A full inset all round
             * plus another one above the now bar was costing about 15% of the
             * frame to margin nobody was looking at.
             */
            anchors.margins: videoPage.fullScreen ? 0 : rightPanel.inset * 0.45
            // Clears the now bar and everything under it. Arithmetic rather
            // than `anchors.bottom: videoNowBar.top`, because fullscreen has to
            // change a number the Behavior can animate, not an anchor target.
            anchors.bottomMargin: videoPage.fullScreen
                                  ? 0
                                  : rightPanel.height - videoNowBar.y
                                    + rightPanel.inset * 0.4
        }

        // Black behind the picture windowed, for the same reason fullscreen
        // paints the panel black: a frame whose aspect ratio does not match its
        // box is letterboxed, and the drifting page gradient showing through
        // those bars reads as a rendering fault. It matters more now that the
        // box reaches the panel edges and the bars are correspondingly wider.
        Rectangle {
            z: 0
            anchors.fill: videoOut
            color: "#000000"
            visible: videoPlayer.videoSelected && !videoPage.fullScreen
        }

        // A double tap on the picture leaves fullscreen. Below the minimise
        // button (z 10) so it never steals its clicks.
        MouseArea {
            id: videoSurfaceArea
            z: 1
            anchors.fill: parent
            enabled: videoPage.fullScreen && videoPlayer.videoSelected
            // A single tap brings the minimise button back to full strength;
            // the double tap still leaves fullscreen outright.
            onClicked: videoPage.revealChrome()
            onDoubleClicked: videoPage.fullScreen = false
        }

        // The only chrome left in fullscreen, so it has to be findable and it
        // has to be hittable: a finger target, not the 27 px this used to be.
        ScreenBtn {
            id: minimiseBtn
            expanded: true
            btnSize: videoPage.height / 12
            visible: videoPage.fullScreen
            opacity: videoPage.chromeShown ? 1.0 : 0.55
            Behavior on opacity { NumberAnimation { duration: 250 } }
            // A dark disc, where the copy in the transport bar is glass. Glass
            // is 5% white: it works over the page backdrop and disappears
            // entirely over a bright frame, which is exactly where this one
            // lives.
            baseColor: Qt.rgba(0, 0, 0, 0.55)
            ringColor: Qt.rgba(1, 1, 1, 0.55)
            z: 10
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.topMargin: videoPage.height / 28
            anchors.leftMargin: videoPage.height / 28
            onClicked: videoPage.fullScreen = false

            // Still useful on a desk with a mouse; it is no longer the only way
            // to make the button visible.
            HoverHandler {
                onHoveredChanged: if (hovered) videoPage.revealChrome()
            }
        }

        // Closes the video and returns to the library. Fullscreen keeps only
        // the minimise button, so this goes with the rest of the chrome.
        TransportButton {
            id: closeBtn
            z: 10
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: videoPage.height / 35
            anchors.rightMargin: videoPage.height / 32
            accent: Theme.danger
            diameter: videoPage.width / 32
            iconScale: 0.42
            glyph: "close"
            // Now that the picture reaches the panel edges this sits on top of
            // it, so it needs the same dark disc as the fullscreen minimise
            // button rather than glass.
            baseColor: Qt.rgba(0, 0, 0, 0.55)
            visible: videoPlayer.videoSelected && !videoPage.fullScreen
            onClicked: videoPage.showLocalLibrary()
        }

        // ---- browser ----
        // Hidden once a video is playing so the picture underneath is clear.
        Item {
            id: browser
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: rightPanel.inset
            anchors.bottom: videoNowBar.top
            anchors.bottomMargin: videoPage.height / 40
            z: 2
            visible: !videoPage.fullScreen && !videoPlayer.videoSelected

            // ------------------------------------------------ Local
            Item {
                anchors.fill: parent
                visible: videoPage.source === videoPage.srcLocal

                Text {
                    id: localHeader
                    anchors.top: parent.top
                    anchors.right: parent.right
                    text: videoLibrary.count + (videoLibrary.count === 1 ? " video" : " videos")
                    color: Theme.textSecondary
                    font { pixelSize: videoPage.width / 90; family: "Arial" }
                    visible: videoLibrary.count > 0
                }

                EmptyState {
                    glyphSize: videoPage.height / 8
                    titleSize: videoPage.width / 55
                    hintSize: videoPage.width / 90
                    anchors.centerIn: parent
                    visible: videoLibrary.count === 0
                    kind: "film"
                    tint: Theme.tint(videoPage.accent, 0.75)
                    title: "No video files"
                    hint: "Add videos to the library folder and they will appear here."
                }

                ListView {
                    id: localList
                    anchors.fill: parent
                    anchors.topMargin: localHeader.visible
                                       ? localHeader.height + videoPage.height / 60 : 0
                    clip: true
                    visible: videoLibrary.count > 0
                    model: videoLibrary
                    spacing: 6

                    ScrollBar.vertical: GlassScrollBar {
                        id: localBar
                        accent: videoPage.accent
                        view: localList
                        thickness: videoPage.width / 110
                    }

                    delegate: TrackRow {
                        required property string fileName
                        required property string filePath
                        required property int    index

                        width: localList.width - localBar.width * 2
                        height: videoPage.height / 11
                        accent: videoPage.accent
                        kind: "film"
                        title: videoPage.stripExtension(fileName)
                        subtitle: videoPage.fileFormat(fileName)
                        active: videoPage.isCurrent(filePath)
                        playing: active
                                 && videoPlayer.playbackState === MediaPlayer.PlayingState
                        onClicked: videoPage.playFile(filePath, index)
                    }
                }
            }

            // ------------------------------------------------ USB
            Item {
                anchors.fill: parent
                visible: videoPage.source === videoPage.srcUsb

                EmptyState {
                    glyphSize: videoPage.height / 8
                    titleSize: videoPage.width / 55
                    hintSize: videoPage.width / 90
                    anchors.centerIn: parent
                    visible: !usbManager.connected && !usbManager.scanning
                    kind: "usb"
                    tint: Theme.textSecondary
                    title: "No USB device"
                    hint: "Plug in a stick or a phone and its videos will be listed here."
                }

                // ---- scanning ----
                Item {
                    anchors.fill: parent
                    visible: usbManager.scanning
                    z: 5

                    Column {
                        anchors.centerIn: parent
                        spacing: videoPage.height / 40

                        Spinner {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: videoPage.height / 12
                            height: width
                            tint: videoPage.accent
                            running: usbManager.scanning
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Scanning " + usbManager.driveName + "…"
                            color: Theme.textPrimary
                            font { pixelSize: videoPage.width / 62; family: "Arial"; bold: true }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: usbManager.videoFiles.length > 0
                                  ? usbManager.videoFiles.length + " video files so far"
                                  : "This can take a moment for phones (MTP)"
                            color: Theme.textSecondary
                            font { pixelSize: videoPage.width / 95; family: "Arial" }
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
                                font { pixelSize: videoPage.width / 75; family: "Arial"; bold: true }
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
                        spacing: videoPage.width / 90

                        MediaGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            width: videoPage.width / 52
                            height: width
                            kind: "usb"
                            tint: videoPage.accent
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: usbManager.driveName
                            color: videoPage.accent
                            font { pixelSize: videoPage.width / 60; family: "Arial"; bold: true }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: usbManager.videoFiles.length
                                  + (usbManager.videoFiles.length === 1 ? " file" : " files")
                            color: Theme.textSecondary
                            font { pixelSize: videoPage.width / 90; family: "Arial" }
                        }
                    }

                    EmptyState {
                        glyphSize: videoPage.height / 8
                        titleSize: videoPage.width / 55
                        hintSize: videoPage.width / 90
                        anchors.centerIn: parent
                        visible: usbManager.videoFiles.length === 0
                        kind: "film"
                        tint: Theme.textSecondary
                        title: "No video on this device"
                        hint: "The drive was read, but nothing playable turned up."
                    }

                    ListView {
                        id: usbList
                        anchors.fill: parent
                        anchors.topMargin: driveHeader.height + videoPage.height / 40
                        clip: true
                        visible: usbManager.videoFiles.length > 0
                        model: usbManager.videoFiles
                        spacing: 6

                        ScrollBar.vertical: GlassScrollBar {
                            id: usbBar
                            accent: videoPage.accent
                            view: usbList
                            thickness: videoPage.width / 110
                        }

                        delegate: TrackRow {
                            required property string modelData
                            required property int    index

                            width: usbList.width - usbBar.width * 2
                            height: videoPage.height / 11
                            accent: videoPage.accent
                            kind: "film"
                            title: videoPage.stripExtension(usbManager.fileName(modelData))
                            subtitle: videoPage.fileFormat(modelData)
                            active: videoPage.isCurrent(modelData)
                            playing: active
                                     && videoPlayer.playbackState === MediaPlayer.PlayingState
                            onClicked: videoPage.playFile(modelData, index)
                        }
                    }
                }
            }
        }

        // ---- now playing + progress ----
        Item {
            id: videoNowBar
            z: 2
            anchors.bottom: videoController.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: rightPanel.inset
            anchors.rightMargin: rightPanel.inset
            anchors.bottomMargin: videoPage.height / 50
            // Just the title row, a small gap and the scrubber. It was height/9,
            // which left a dead band between the two that did nothing but push
            // the picture up and shrink it.
            height: videoPage.height / 12
            visible: !videoPage.fullScreen

            MediaGlyph {
                id: errIcon
                anchors.left: parent.left
                anchors.verticalCenter: nowTitle.verticalCenter
                width: videoPage.width / 72
                height: width
                kind: "warning"
                tint: Theme.danger
                accent: Theme.danger
                visible: videoPlayer.errorMessage !== ""
            }

            Text {
                id: nowTitle
                anchors.top: parent.top
                anchors.left: errIcon.visible ? errIcon.right : parent.left
                anchors.leftMargin: errIcon.visible ? videoPage.width / 140 : 0
                anchors.right: nowTime.left
                anchors.rightMargin: videoPage.width / 60
                text: videoPlayer.errorMessage !== "" ? videoPlayer.errorMessage
                    : videoPlayer.videoSelected
                      ? videoPage.stripExtension(videoPlayer.source.toString().split("/").pop())
                      : "Nothing playing"
                color: videoPlayer.errorMessage !== "" ? Theme.danger
                     : videoPlayer.videoSelected ? Theme.textPrimary : Theme.textSecondary
                font {
                    pixelSize: videoPage.width / 68
                    family: "Arial"
                    bold: videoPlayer.videoSelected
                }
                elide: Text.ElideMiddle
            }

            Text {
                id: nowTime
                anchors.top: parent.top
                anchors.right: parent.right
                text: videoPage.formatTime(videoPlayer.position) + "  /  "
                      + videoPage.formatTime(videoPlayer.duration)
                color: Theme.textSecondary
                font { pixelSize: videoPage.width / 90; family: "Arial" }
            }

            GlassSlider {
                id: progressSlider
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: videoPage.height / 26
                accent: videoPage.accent
                handleSize: 14
                from: 0
                to: videoPlayer.duration > 0 ? videoPlayer.duration : 1
                value: videoPlayer.position
                enabled: videoPlayer.duration > 0
                showHandle: videoPlayer.duration > 0

                onMoved: videoPlayer.position = value
            }
        }

        // ---- transport ----
        Rectangle {
            id: videoController
            z: 2
            visible: !videoPage.fullScreen
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: videoPage.height / 30
            height: videoPage.height / 11
            radius: height / 2
            color: Theme.glassFill
            border.color: Theme.glassBorder
            border.width: 1

            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: parent.radius + 2
                z: -1
                color: videoPage.accent
                opacity: 0.07
            }

            // ---- volume, left ----
            TransportButton {
                id: muteBtn
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: videoController.height * 0.6
                accent: videoPage.accent
                diameter: videoController.height * 0.6
                iconSource: audioOut.muted ? "qrc:/assets/icons/volumedown.png"
                                           : "qrc:/assets/icons/volumeup.png"
                onClicked: audioOut.muted = !audioOut.muted
            }

            GlassSlider {
                id: volumeSlider
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: muteBtn.right
                anchors.leftMargin: videoController.width / 60
                width: videoController.width / 7
                accent: videoPage.accent
                from: 0
                to: 1
                value: 0.6

                onValueChanged: {
                    audioOut.volume = value
                    audioOut.muted = false
                }
            }

            // ---- transport, centre ----
            Row {
                anchors.centerIn: parent
                spacing: videoController.width / 34

                TransportButton {
                    anchors.verticalCenter: parent.verticalCenter
                    accent: videoPage.accent
                    diameter: videoController.height * 0.6
                    iconSource: "qrc:/assets/icons/prev.png"
                    onClicked: {
                        if (videoPage.source === videoPage.srcUsb) videoPage.stepUsb(-1)
                        else videoPlayer.position = 0
                    }
                }

                TransportButton {
                    anchors.verticalCenter: parent.verticalCenter
                    accent: videoPage.accent
                    diameter: videoController.height * 0.78
                    ringWidth: 2
                    iconScale: 0.44
                    iconSource: videoPlayer.playbackState === MediaPlayer.PlayingState
                                ? "qrc:/assets/icons/pause.png"
                                : "qrc:/assets/icons/play.png"
                    onClicked: videoPlayer.playbackState === MediaPlayer.PlayingState
                               ? videoPlayer.pause() : videoPlayer.play()
                }

                TransportButton {
                    anchors.verticalCenter: parent.verticalCenter
                    accent: videoPage.accent
                    diameter: videoController.height * 0.6
                    iconSource: "qrc:/assets/icons/next.png"
                    onClicked: {
                        if (videoPage.source === videoPage.srcUsb) videoPage.stepUsb(1)
                        else videoPlayer.position = videoPlayer.duration
                    }
                }
            }

            // ---- speed + fullscreen, right ----
            TransportButton {
                id: speedBtn
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: speedSlider.left
                anchors.rightMargin: videoController.width / 60
                accent: videoPage.accent
                diameter: videoController.height * 0.6
                label: videoPlayer.playbackRate.toFixed(1) + "x"
                labelSize: videoController.height * 0.24
                onClicked: speedSlider.value = 1
            }

            GlassSlider {
                id: speedSlider
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: screenToggle.left
                anchors.rightMargin: videoController.width / 60
                width: videoController.width / 9
                accent: videoPage.accent
                // 0.5–2.0, where this used to run to 8x. Nothing is watchable
                // above 2x, and with that range 93% of the travel sat above it —
                // which made 1.0x impossible to hit on a touch panel.
                from: 0.5
                to: 2.0
                value: 1

                onValueChanged: videoPlayer.playbackRate = value
            }

            ScreenBtn {
                id: screenToggle
                expanded: videoPage.fullScreen
                // Nothing to maximise until a video is playing.
                visible: videoPlayer.videoSelected
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: videoController.height * 0.6
                onClicked: videoPage.fullScreen = !videoPage.fullScreen
            }
        }
    }

    // ========================================== Parts =========================================


    /*
     * Full screen toggle.
     *
     * The glyph is drawn rather than set as text: the usual characters for this
     * (⛶, ⤢) are outside the shipped font's coverage, and render as empty boxes
     * on the target image. Canvas has no such dependency.
     */
    component ScreenBtn: Rectangle {
        id: screenBtn
        property bool expanded: false
        // Set by the caller: used both inside the control bar and as a
        // standalone overlay, so it cannot size itself from one parent.
        property real btnSize: videoController.height * 0.6
        // Backing and ring at rest. The copy in the transport bar sits on glass
        // and can be glass itself; the fullscreen one sits on the picture and
        // has to bring its own contrast.
        property color baseColor: Theme.glassFill
        property color ringColor: videoPage.accent
        signal clicked()

        width: btnSize
        height: btnSize
        radius: width / 2

        color: screenBtnArea.pressed       ? Theme.tint(videoPage.accent, 0.5)
             : screenBtnArea.containsMouse ? Theme.tint(videoPage.accent, 0.35)
                                           : screenBtn.baseColor
        border.color: screenBtn.ringColor
        border.width: 1
        scale: screenBtnArea.containsMouse ? 1.06 : 1
        Behavior on color { ColorAnimation  { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 150 } }

        Canvas {
            id: screenBtnCanvas
            anchors.centerIn: parent
            width: parent.width * 0.56
            height: width
            onWidthChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = Theme.textPrimary
                // Heavier than the width/9 it was drawn at: on the small
                // overlay button that worked out to a 1.5 px hairline.
                ctx.lineWidth = Math.max(2, width / 9)
                // Butt, not square. A square cap runs on by half the stroke at
                // both ends — 1.5 px here — which is more than the gap between
                // the facing brackets, so they met and the mark sealed itself
                // into a plain box.
                ctx.lineCap = "butt"

                /*
                 * Four corner brackets: on the corners to enter fullscreen,
                 * pulled inward to leave it.
                 *
                 * The arm shortens in the expanded state as well as the elbow
                 * moving in. At the old pad of 0.28 with the arm left at 0.32,
                 * the pair on each side reached past each other and the four
                 * brackets closed into a plain square — which is most of why
                 * the mark could not be read.
                 */
                var edge = ctx.lineWidth / 2   // half the stroke sits outside the path
                var pad = screenBtn.expanded ? width * 0.22 : 0
                var arm = screenBtn.expanded ? width * 0.16 : width * 0.32
                var lo = edge + pad
                var hi = width - edge - pad
                var corners = [
                    [lo, lo,  1,  1],
                    [hi, lo, -1,  1],
                    [lo, hi,  1, -1],
                    [hi, hi, -1, -1]
                ]
                for (var i = 0; i < corners.length; ++i) {
                    var x = corners[i][0], y = corners[i][1]
                    var dx = corners[i][2], dy = corners[i][3]
                    ctx.beginPath()
                    ctx.moveTo(x + dx * arm, y)
                    ctx.lineTo(x, y)
                    ctx.lineTo(x, y + dy * arm)
                    ctx.stroke()
                }
            }
        }

        onExpandedChanged: screenBtnCanvas.requestPaint()

        MouseArea {
            id: screenBtnArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: screenBtn.clicked()
        }
    }
}
