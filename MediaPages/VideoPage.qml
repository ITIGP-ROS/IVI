import QtQuick
import QtQuick.Controls
pragma ComponentBehavior: Bound
import QtMultimedia

Rectangle {
    id: videoPage
    required property StackView stackView
    anchors.fill: parent
    color: "transparent"

    // Stop playback and show the local library list again. The Local tab has
    // no file picker, so this is how you get back to choosing a video.
    function showLocalLibrary() {
        videoPlayer.stop()
        videoPlayer.source = ""
        videoPlayer.videoSelected = false
        videoPlayer.currentFileIndex = -1
        videoPage.fullScreen = false
    }

    // ── Full screen ──
    // The video takes the entire screen: source list, panel chrome, transport
    // controls and the title bar all fold away, leaving only a small minimise
    // button in the top-left corner.
    //
    // MediaPlayerPage watches this to hide its WindowBar, which is drawn over
    // this page and would otherwise sit on top of the picture.
    property bool fullScreen: false

    // Escape and a double tap on the picture are alternatives to the button —
    // worth having when the only control on screen is one small icon.
    Shortcut {
        sequence: "Escape"
        enabled: videoPage.fullScreen
        onActivated: videoPage.fullScreen = false
    }

    MediaPlayer {
        id: videoPlayer
        audioOutput: AudioOutput { id: audioOut; volume: 0.7; }
        videoOutput: videoOut
        property bool videoSelected: false
        property string errorMessage: ""
        property int currentFileIndex: -1

        onErrorOccurred: function(error, errorString) {
            videoSelected = false
            switch(error) {
                case MediaPlayer.NetworkError:
                    errorMessage = "⚠  Cannot reach the server — check your internet connection"
                    break
                case MediaPlayer.FormatError:
                    errorMessage = "⚠  Unsupported video format"
                    break
                case MediaPlayer.AccessDeniedError:
                    errorMessage = "⚠  Access denied — the server rejected the request"
                    break
                case MediaPlayer.ResourceError:
                    errorMessage = "⚠  Invalid URL or resource not found"
                    break
                default:
                    errorMessage = "⚠  " + errorString
            }
        }

        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.PlayingState)
                errorMessage = ""
        }
    }

    // ========================================== BACKGROUND =========================================
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

    // ========================================== Left Panel (Source Selection) =========================================
    Rectangle {
        id: leftPanel
        width: videoPage.width / 5
        height: parent.height
        color: '#082839'
        visible: !videoPage.fullScreen

        Column {
            anchors.top: parent.top
            anchors.topMargin: videoPage.height / 10
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: videoPage.height / 40

            Repeater {
                model: [
                    { label: "🗂️  Local",    idx: 0 },
                    { label: "🌐  Internet", idx: 1 },
                    { label: "💾  USB",      idx: 2 }
                ]

                delegate: Rectangle {
                    id: optionRect
                    required property var modelData
                    width: leftPanel.width * 0.8
                    height: videoPage.height / 14
                    radius: height / 5
                    color: rightPanel.currentIndex === modelData.idx ? '#5A3211'
                            : (srcArea.containsMouse ? '#10475E' : 'transparent')
                    border.color: rightPanel.currentIndex === modelData.idx ? '#D08831' : 'transparent'
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        text: optionRect.modelData.label
                        color: rightPanel.currentIndex === optionRect.modelData.idx ? '#D08831' : '#3D717E'
                        font.pixelSize: videoPage.width / 60
                        font.family: "Arial"
                        font.bold: rightPanel.currentIndex === optionRect.modelData.idx
                        horizontalAlignment: Text.AlignLeft
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: optionRect.left
                        anchors.leftMargin: optionRect.width / 8
                    }

                    MouseArea {
                        id: srcArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: rightPanel.currentIndex = optionRect.modelData.idx
                    }
                }
            }

            Rectangle { width: 1; height: videoPage.height / 2.3; color: "transparent" }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: backText.width * 2.5
                height: backText.height + backText.height * 0.6
                radius: height / 1.5
                color: backArea.containsMouse ? "#964405" : '#5A3211'
                border.color: "#D08831"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    id: backText
                    anchors.centerIn: parent
                    text: "Back"
                    color: '#e7f1ef'
                    font.pixelSize: videoPage.width / 55
                    font.family: "Arial"
                    font.bold: true
                }

                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: videoPage.stackView.pop()
                }
            }
        }
    }

    // ========================================== Right Panel (Content & Controls) =========================================
    Rectangle {
        id: rightPanel

        // Anchored to the page rather than to leftPanel so that going
        // fullscreen only changes margins — an animatable number — instead of
        // re-targeting the anchor, which would snap.
        readonly property real insetLeft: videoPage.fullScreen
                                          ? 0 : leftPanel.width + videoPage.width / 20
        readonly property real insetRight: videoPage.fullScreen ? 0 : videoPage.width / 20
        readonly property real insetTop: videoPage.fullScreen ? 0 : videoPage.height / 10
        readonly property real insetBottom: videoPage.fullScreen ? 0 : videoPage.height / 15

        width: videoPage.width - insetLeft - insetRight
        height: videoPage.height - insetTop - insetBottom
        anchors.top: parent.top
        anchors.topMargin: insetTop
        anchors.left: parent.left
        anchors.leftMargin: insetLeft
        // Black behind the picture in fullscreen: a video whose aspect ratio
        // does not match the screen is letterboxed, and the page gradient
        // showing through those bars looks like a rendering fault.
        color: videoPage.fullScreen ? '#000000' : 'transparent'
        border.color: '#D08831'
        border.width: videoPage.fullScreen ? 0 : 2
        radius: videoPage.fullScreen ? 0 : height / 20

        Behavior on width  { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }
        Behavior on anchors.topMargin  { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }
        Behavior on anchors.leftMargin { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

        property int currentIndex: 0
        property var browseIcon: "📂"

        VideoOutput {
            id: videoOut
            z: 1
            anchors.fill: parent
            // Windowed, the controls sit below the picture. Fullscreen, the
            // picture takes the whole panel and the controls float over it.
            anchors.margins: videoPage.fullScreen ? 0 : videoPage.height / 50
            anchors.bottomMargin: videoPage.fullScreen
                                  ? 0
                                  : videoController.height + videoProgress.height + videoPage.height / 16
        }

        // A double tap on the picture leaves fullscreen. Sits below the
        // minimise button (z 10) so it never steals its clicks.
        MouseArea {
            id: videoSurfaceArea
            z: 1
            anchors.fill: parent
            enabled: videoPage.fullScreen && videoPlayer.videoSelected
            onDoubleClicked: videoPage.fullScreen = false
        }

        // The only chrome left in fullscreen. Deliberately small and dim until
        // hovered so it does not intrude on the picture.
        ScreenBtn {
            id: minimiseBtn
            expanded: true
            btnSize: videoPage.height / 22
            visible: videoPage.fullScreen
            opacity: minimiseHover.hovered ? 1.0 : 0.45
            Behavior on opacity { NumberAnimation { duration: 150 } }
            z: 10
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.topMargin: videoPage.height / 35
            anchors.leftMargin: videoPage.height / 32
            onClicked: videoPage.fullScreen = false

            HoverHandler { id: minimiseHover }
        }

        // ================================================ Local video ===============================================
        Rectangle {
            anchors.fill: parent
            visible: rightPanel.currentIndex === 0 && !videoPage.fullScreen
            color: 'transparent'

            onVisibleChanged: {
                if (visible) rightPanel.browseIcon = "📂"
            }

            Rectangle {
                anchors.fill: parent
                anchors.bottomMargin: videoController.height + videoProgress.height + videoPage.height / 16
                anchors.margins: videoPage.height / 50
                color: videoPlayer.videoSelected ? "#082839" : 'transparent'
                radius: height / 50

                // The library is a fixed on-disk location, so it loads itself —
                // there is no file picker to drive from a head unit. Hidden once
                // playback starts so the VideoOutput underneath is unobstructed.
                Column {
                    anchors.fill: parent
                    anchors.margins: videoPage.width / 40
                    spacing: videoPage.height / 40
                    visible: !videoPlayer.videoSelected

                    Item {
                        id: localHeader
                        width: parent.width
                        height: localCount.height

                        Text {
                            id: localCount
                            text: videoLibrary.count + (videoLibrary.count === 1 ? " video" : " videos")
                            color: '#3D717E'
                            font.pixelSize: videoPage.width / 85
                            font.family: "Arial"
                            anchors.right: parent.right
                        }
                    }

                    // Empty state — a missing or empty folder must say so,
                    // otherwise a blank panel looks like the player is broken.
                    Column {
                        width: parent.width
                        spacing: videoPage.height / 60
                        visible: videoLibrary.count === 0

                        Text {
                            text: "No video files found"
                            color: '#3D717E'
                            font.pixelSize: videoPage.width / 45
                            font.family: "Arial"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "Add videos to the library folder"
                            color: '#3D717E'
                            font.pixelSize: videoPage.width / 80
                            font.family: "Arial"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    ListView {
                        width: parent.width
                        height: parent.height - localHeader.height - parent.spacing
                        clip: true
                        visible: videoLibrary.count > 0
                        model: videoLibrary
                        spacing: 4

                        ScrollBar.vertical: ScrollBar {
                            id: localScrollBar
                            width: videoPage.width / 100
                            anchors.right: parent.right
                            anchors.rightMargin: 4

                            contentItem: Rectangle {
                                implicitWidth: parent.width
                                radius: width / 2
                                color: localScrollBar.pressed ? '#964405' : localScrollBar.hovered ? '#D08831' : '#5A3211'
                                opacity: localScrollBar.hovered || localScrollBar.pressed ? 1.0 : 0.6
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                            background: Rectangle {
                                implicitWidth: parent.width
                                color: '#082839'
                                radius: width / 2
                                opacity: 0.3
                            }
                            minimumSize: 0.1
                        }

                        delegate: Rectangle {
                            id: localRow
                            required property string fileName
                            required property string filePath
                            required property int index

                            readonly property bool isCurrent:
                                videoPlayer.source.toString() === ("file://" + localRow.filePath)

                            width: ListView.view.width - localScrollBar.width * 2
                            height: videoPage.height / 14
                            radius: height / 5
                            color: isCurrent ? '#5A3211'
                                             : localRowArea.containsMouse ? '#10475E' : 'transparent'
                            border.color: isCurrent ? '#D08831' : 'transparent'
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: parent.width / 20
                                spacing: parent.width / 30

                                Text {
                                    text: "🎬"
                                    font.pixelSize: videoPage.width / 70
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: localRow.fileName.replace(/\.[^.]+$/, "")
                                    color: localRow.isCurrent ? '#D08831' : '#e7f1ef'
                                    font.pixelSize: videoPage.width / 70
                                    font.family: "Arial"
                                    elide: Text.ElideRight
                                    width: parent.parent.width * 0.7
                                    // Pin left, otherwise an RTL filename (Arabic)
                                    // drifts to the far edge and detaches from its icon.
                                    horizontalAlignment: Text.AlignLeft
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: localRowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    videoPlayer.source = "file://" + localRow.filePath
                                    videoPlayer.videoSelected = true
                                    videoPlayer.currentFileIndex = localRow.index
                                    videoPlayer.play()
                                }
                            }
                        }
                    }
                }
            }
        }

        // ================================================ Internet video ============================================
        Rectangle {
            anchors.fill: parent
            visible: rightPanel.currentIndex === 1 && !videoPage.fullScreen
            color: 'transparent'

            onVisibleChanged: {
                if (visible) rightPanel.browseIcon = "🌐"
            }

            // Hidden input — syncs with VirtualKeyboard
            TextInput {
                id: urlField
                visible: false
                text: ""
            }

            Rectangle {
                anchors.fill: parent
                anchors.bottomMargin: videoController.height + videoProgress.height + videoPage.height / 16
                anchors.margins: videoPage.height / 50
                color: videoPlayer.videoSelected ? "#082839" : 'transparent'
                radius: height / 50

                Text {
                    anchors.centerIn: parent
                    visible: !videoPlayer.videoSelected
                    text: "Enter a video URL to stream"
                    color: '#3D717E'
                    font.pixelSize: videoPage.width / 35
                    font.family: "Arial"
                }

                Rectangle {
                    id: loadingOverlay
                    anchors.fill: parent
                    color: '#80000000'
                    visible: videoPlayer.mediaStatus === MediaPlayer.BufferingMedia ||
                            videoPlayer.mediaStatus === MediaPlayer.LoadingMedia   ||
                            videoPlayer.mediaStatus === MediaPlayer.StalledMedia
                    radius: parent.radius

                    Column {
                        anchors.centerIn: parent
                        spacing: videoPage.height / 30

                        Rectangle {
                            width: videoPage.width / 30
                            height: width
                            radius: width / 2
                            color: 'transparent'
                            border.color: '#D08831'
                            border.width: 3
                            anchors.horizontalCenter: parent.horizontalCenter

                            Rectangle {
                                width: parent.border.width + 2
                                height: parent.border.width + 2
                                color: '#80000000'
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            RotationAnimation on rotation {
                                running: loadingOverlay.visible
                                loops: Animation.Infinite
                                duration: 900
                                from: 0; to: 360
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: videoPlayer.mediaStatus === MediaPlayer.StalledMedia ? "⚠  Stream stalled" : "Loading..."
                            color: '#D08831'
                            font.pixelSize: videoPage.width / 70
                            font.family: "Arial"
                        }
                    }
                }
            }
        }

        // ================================================== USB video ==============================================
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: videoPage.width / 90
            anchors.rightMargin: videoPage.width / 90
            anchors.leftMargin: videoPage.width / 90
            anchors.bottomMargin: videoPage.height / 5.35
            radius: videoPage.width / 20
            visible: rightPanel.currentIndex === 2 && !videoPage.fullScreen
            color: 'transparent'

            onVisibleChanged: {
                if (visible) {
                    rightPanel.browseIcon = "💾"
                    if (usbManager.connected && usbManager.videoFiles.length === 0 && !usbManager.scanning)
                        usbManager.scanFiles()
                }
            }

            Text {
                anchors.top: parent.top
                anchors.topMargin: parent.height / 2.2
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !usbManager.connected
                text: "Plug in a USB device"
                color: '#3D717E'
                font.pixelSize: videoPage.width / 35
                font.family: "Arial"
            }

            Rectangle {
                anchors.fill: parent
                color: '#082839'
                visible: usbManager.scanning
                z: 5
                radius: videoPage.width / 60

                Column {
                    anchors.centerIn: parent
                    spacing: 20

                    Rectangle {
                        width: 40; height: 40; radius: 20
                        color: 'transparent'
                        border.color: '#D08831'
                        border.width: 3
                        anchors.horizontalCenter: parent.horizontalCenter

                        Rectangle {
                            width: 6; height: 6
                            color: '#082839'
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.topMargin: -2
                        }

                        RotationAnimation on rotation {
                            running: parent.visible
                            loops: Animation.Infinite
                            duration: 900
                            from: 0; to: 360
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Scanning " + usbManager.driveName + "..."
                        color: '#D08831'
                        font.pixelSize: videoPage.width / 60
                        font.family: "Arial"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "This may take a moment for phones (MTP)"
                        color: '#3D717E'
                        font.pixelSize: videoPage.width / 80
                        font.family: "Arial"
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: cancelText.width * 2.5
                        height: cancelText.height + 16
                        radius: height / 2
                        color: cancelArea.containsMouse ? "#ff4444" : "#aa2222"

                        Text {
                            id: cancelText
                            anchors.centerIn: parent
                            text: "Cancel Scan"
                            color: "#ffffff"
                            font.pixelSize: videoPage.width / 60
                            font.family: "Arial"
                            font.bold: true
                        }

                        MouseArea {
                            id: cancelArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: usbManager.disconnectDevice()
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Found: " + usbManager.videoFiles.length + " video files"
                        color: '#3D717E'
                        font.pixelSize: videoPage.width / 80
                        visible: usbManager.videoFiles.length > 0
                    }
                }
            }

            Column {
                anchors.fill: parent
                anchors.topMargin: parent.height / 20
                anchors.leftMargin: parent.width / 20
                anchors.rightMargin: parent.width / 20
                spacing: videoPage.height / 30
                visible: usbManager.connected && !usbManager.scanning && !videoPlayer.videoSelected

                Row {
                    id: videoDriveHeader
                    spacing: 10
                    Text {
                        text: "💾  " + usbManager.driveName
                        color: '#D08831'
                        font.pixelSize: videoPage.width / 55
                        font.bold: true
                        font.family: "Arial"
                    }
                    Text {
                        text: usbManager.videoFiles.length + " files"
                        color: '#3D717E'
                        font.pixelSize: videoPage.width / 75
                        font.family: "Arial"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    id: videoFileList
                    width: parent.width
                    height: parent.height - parent.spacing - videoDriveHeader.height
                    clip: true
                    model: usbManager.videoFiles
                    spacing: 4

                    ScrollBar.vertical: ScrollBar {
                        id: videoScrollBar
                        width: videoPage.width / 100
                        anchors.right: parent.right
                        anchors.rightMargin: 4

                        contentItem: Rectangle {
                            implicitWidth: parent.width
                            radius: width / 2
                            color: videoScrollBar.pressed ? '#964405' : videoScrollBar.hovered ? '#D08831' : '#5A3211'
                            opacity: videoScrollBar.hovered || videoScrollBar.pressed ? 1.0 : 0.6
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        background: Rectangle {
                            implicitWidth: parent.width
                            color: '#082839'
                            radius: width / 2
                            opacity: 0.3
                        }
                        minimumSize: 0.1
                    }

                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        width: ListView.view.width - videoScrollBar.width * 2
                        height: videoPage.height / 14
                        radius: height / 5
                        color: videoPlayer.source.toString() === ("file://" + modelData)
                            ? '#5A3211'
                            : videoRowArea.containsMouse ? '#10475E' : 'transparent'
                        border.color: videoPlayer.source.toString() === ("file://" + modelData)
                                    ? '#D08831' : 'transparent'
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: parent.width / 20
                            spacing: parent.width / 30

                            Text {
                                text: "🎬"
                                font.pixelSize: videoPage.width / 70
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: usbManager.fileName(modelData)
                                color: videoPlayer.source.toString() === ("file://" + modelData)
                                    ? '#D08831' : '#e7f1ef'
                                font.pixelSize: videoPage.width / 70
                                font.family: "Arial"
                                elide: Text.ElideRight
                                width: parent.parent.width * 0.7
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: videoRowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                videoPlayer.source = "file://" + modelData
                                videoPlayer.videoSelected = true
                                videoPlayer.currentFileIndex = index
                                videoPlayer.play()
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: '#082839'
                radius: height / 50
                visible: videoPlayer.videoSelected
            }
        }

        // ======================================== Video Controls (Shared) ==========================================
        Rectangle {
            id: videoProgress
            z: 2
            visible: !videoPage.fullScreen
            anchors.bottom: videoController.top
            anchors.left: videoController.left
            anchors.right: videoController.right
            anchors.bottomMargin: videoController.height / 100
            anchors.leftMargin: videoPage.width / 30
            anchors.rightMargin: videoPage.width / 30
            height: videoPage.height / 30
            radius: height / 2
            color: 'transparent'

            Slider {
                id: progressSlider
                anchors.bottom: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: -height / 2
                height: videoController.height / 4
                from: 0
                to: videoPlayer.duration > 0 ? videoPlayer.duration : 1
                value: videoPlayer.position

                onMoved: videoPlayer.position = value

                background: Rectangle {
                    x: progressSlider.leftPadding
                    y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                    width: progressSlider.availableWidth
                    height: 3
                    radius: 2
                    color: '#082839'

                    Rectangle {
                        width: progressSlider.visualPosition * parent.width
                        height: parent.height
                        radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: '#D08831' }
                            GradientStop { position: 1.0; color: '#964405' }
                        }
                    }
                }

                handle: Rectangle {
                    x: progressSlider.leftPadding + progressSlider.visualPosition * (progressSlider.availableWidth - width)
                    y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                    width: 10; height: 10; radius: 5
                    color: progressSlider.pressed ? '#D08831' : '#e7f1ef'
                    border.color: '#D08831'
                    border.width: 2
                    visible: videoPlayer.duration > 0
                }
            }

            Text {
                id: currentTimeText
                anchors.top: videoProgress.top
                anchors.left: videoProgress.left
                anchors.leftMargin: videoController.width / 120
                text: videoPage.formatTime(videoPlayer.position)
                color: '#3D717E'
                font.pixelSize: videoController.height / 5
                font.family: "Arial"
            }

            Text {
                visible: videoPlayer.videoSelected
                anchors.top: videoProgress.top
                anchors.left: currentTimeText.right
                anchors.leftMargin: videoController.width / 20
                anchors.right: totalTimeText.left
                anchors.rightMargin: videoController.width / 20
                text: videoPlayer.videoSelected
                    ? videoPlayer.source.toString().split("/").pop().replace(/\.[^.]+$/, "")
                    : ""
                color: '#e7f1ef'
                font.pixelSize: videoController.height / 5
                font.family: "Arial"
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
            }

            Text {
                id: totalTimeText
                anchors.top: videoProgress.top
                anchors.right: videoProgress.right
                anchors.rightMargin: videoController.width / 120
                text: videoPage.formatTime(videoPlayer.duration)
                color: '#3D717E'
                font.pixelSize: videoController.height / 5
                font.family: "Arial"
            }
        }

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
            color: '#5A3211'
            border.color: '#D08831'
            border.width: 1

            ControlBtn {
                id: volumeBtn
                property bool muted: false
                iconSource: audioOut.muted ? "qrc:/assets/icons/volumedown.png"
                                           : "qrc:/assets/icons/volumeup.png"
                onClicked: audioOut.muted = !audioOut.muted
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: videoController.width / 20
            }

            Slider {
                id: volumeSlider
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: volumeBtn.right
                anchors.leftMargin: videoController.width / 80
                width: videoController.width / 8
                from: 0; to: 1; value: 0.6

                onValueChanged: {
                    audioOut.volume = value
                    volumeBtn.muted = false
                    audioOut.muted = false
                }

                background: Rectangle {
                    x: volumeSlider.leftPadding
                    y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                    width: volumeSlider.availableWidth
                    height: 6
                    radius: 3
                    color: '#082839'

                    Rectangle {
                        width: volumeSlider.visualPosition * parent.width
                        height: parent.height
                        radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: '#D08831' }
                            GradientStop { position: 1.0; color: '#964405' }
                        }
                    }
                }
            }

           Row {
                anchors.centerIn: parent
                spacing: videoController.width / 55

                // Prev
                Rectangle {
                    id: prevBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: videoController.height * 0.6
                    height: width
                    radius: width / 2
                    color: prevArea.containsMouse ? "#964405" : "#5A3211"
                    border.color: "#D08831"
                    border.width: 1
                    scale: prevArea.containsMouse ? 1.15 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 150 } }

                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/assets/icons/prev.png"
                        width: parent.width * 0.5
                        height: parent.height * 0.5
                        fillMode: Image.PreserveAspectFit
                    }

                    MouseArea {
                        id: prevArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (rightPanel.currentIndex === 2 && usbManager.connected && usbManager.videoFiles.length > 0) {
                                var newIndex = videoPlayer.currentFileIndex - 1
                                if (newIndex < 0) newIndex = usbManager.videoFiles.length - 1
                                videoPlayer.currentFileIndex = newIndex
                                videoPlayer.source = "file://" + usbManager.videoFiles[newIndex]
                                videoPlayer.videoSelected = true
                                videoPlayer.play()
                            } else {
                                videoPlayer.position = 0
                            }
                        }
                    }
                }

                // Play / Pause
                Rectangle {
                    width: videoController.height * 0.72
                    height: width
                    radius: width / 2
                    color: playMainArea.containsMouse ? '#964405' : '#5A3211'
                    border.color: '#D08831'
                    border.width: 2
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Image {
                        anchors.centerIn: parent
                        width: 26; height: 26
                        source: videoPlayer.playbackState === MediaPlayer.PlayingState ? "qrc:/assets/icons/pause.png" : "qrc:/assets/icons/play.png"
                        fillMode: Image.PreserveAspectFit
                    }

                    MouseArea {
                        id: playMainArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: videoPlayer.playbackState === MediaPlayer.PlayingState
                                ? videoPlayer.pause() : videoPlayer.play()
                    }
                }

                // Next
                Rectangle {
                    id: nextBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: videoController.height * 0.6
                    height: width
                    radius: width / 2
                    color: nextArea.containsMouse ? "#964405" : "#5A3211"
                    border.color: "#D08831"
                    border.width: 1
                    scale: nextArea.containsMouse ? 1.15 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 150 } }

                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/assets/icons/next.png"
                        width: parent.width * 0.5
                        height: parent.height * 0.5
                        fillMode: Image.PreserveAspectFit
                    }

                    MouseArea {
                        id: nextArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (rightPanel.currentIndex === 2 && usbManager.connected && usbManager.videoFiles.length > 0) {
                                var newIndex = videoPlayer.currentFileIndex + 1
                                if (newIndex >= usbManager.videoFiles.length) newIndex = 0
                                videoPlayer.currentFileIndex = newIndex
                                videoPlayer.source = "file://" + usbManager.videoFiles[newIndex]
                                videoPlayer.videoSelected = true
                                videoPlayer.play()
                            } else {
                                videoPlayer.position = videoPlayer.duration
                            }
                        }
                    }
                }
            }

            ControlBtn {
                id: speedIndicator
                icon: "1.0x"
                onClicked: speedSlider.value = 1
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: speedSlider.left
                anchors.rightMargin: videoController.width / 80
                fontPixel: videoController.width / 55
            }

            Slider {
                id: speedSlider
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: browseBtn.left
                anchors.rightMargin: videoController.width / 20
                width: videoController.width / 8
                from: 0.5; to: 8; value: 1

                onValueChanged: {
                    videoPlayer.playbackRate = value
                    speedIndicator.icon = value.toFixed(1) + "x"
                }

                background: Rectangle {
                    x: speedSlider.leftPadding
                    y: speedSlider.topPadding + speedSlider.availableHeight / 2 - height / 2
                    width: speedSlider.availableWidth
                    height: 6
                    radius: 3
                    color: '#082839'

                    Rectangle {
                        width: speedSlider.visualPosition * parent.width
                        height: parent.height
                        radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: '#D08831' }
                            GradientStop { position: 1.0; color: '#964405' }
                        }
                    }
                }
            }

            ScreenBtn {
                id: screenToggle
                expanded: videoPage.fullScreen
                // Nothing to maximise until a video is playing.
                visible: videoPlayer.videoSelected
                anchors.verticalCenter: parent.verticalCenter
                // Takes the far-right slot when the browse button is hidden.
                anchors.right: browseBtn.visible ? browseBtn.left : parent.right
                anchors.rightMargin: browseBtn.visible ? videoController.width / 40
                                                       : videoController.width / 20
                onClicked: videoPage.fullScreen = !videoPage.fullScreen
            }

            ControlBtn {
                id: browseBtn
                icon: rightPanel.browseIcon
                // Only Internet has anything to browse to — it opens the URL
                // keyboard. Local and USB both load their own contents, so the
                // button would do nothing there.
                visible: rightPanel.currentIndex === 1
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: videoController.width / 20
                // Local has no picker any more — the button returns to the
                // library list instead of opening a file dialog.
                onClicked: rightPanel.currentIndex === 0 ? videoPage.showLocalLibrary() :
                            rightPanel.currentIndex === 1 ? urlKeyboardPopup.open() :
                            console.log("Browse action for other sources coming soon")
            }
        }

        // Close Video Button
        Rectangle {
            width: videoPage.width / 35
            height: width
            radius: width / 2
            color: closeArea.containsMouse ? '#ff4444' : '#aa2222'
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: videoPage.height / 35
            anchors.rightMargin: videoPage.height / 32
            // Fullscreen keeps only the minimise button, so this goes away
            // with the rest of the chrome.
            visible: videoPlayer.videoSelected && !videoPage.fullScreen
            opacity: 0.4
            z: 10

            Text {
                anchors.centerIn: parent
                text: "✖"
                color: "#ffffff"
                font.pixelSize: parent.width * 0.6
                font.bold: true
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                onEntered: parent.opacity = 1
                onExited: parent.opacity = 0.4
                onClicked: videoPage.showLocalLibrary()
            }
        }
    }

    // ========================================== URL Keyboard Popup =========================================
    Popup {
        id: urlKeyboardPopup
        parent: Overlay.overlay
        width: videoPage.width * 0.6
        height: videoPage.height * 0.7
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
                text: "Enter Video URL"
                font.pixelSize: videoPage.height * 0.04
                color: "#D08831"
                font.bold: true
                font.family: "Arial"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            VirtualKeyboard {
                id: urlKeyboard
                width: parent.width
                targetItem: urlField
                passwordMode: false
                maxLength: 256

                onAccepted: {
                    if (urlField.text !== "") {
                        videoPlayer.source = urlField.text
                        videoPlayer.videoSelected = true
                        videoPlayer.play()
                    }
                    urlKeyboard.clear()
                    urlKeyboardPopup.close()
                }

                onCancelled: {
                    urlKeyboard.clear()
                    urlKeyboardPopup.close()
                }
            }
        }

        onOpened: {
            urlKeyboard.targetText = urlField.text
        }
    }

    /*
     * Full screen toggle.
     *
     * The glyph is drawn rather than set as text: the usual characters for
     * this (⛶, ⤢) are outside DejaVu's coverage, and a target image without an
     * emoji font renders them as empty boxes. Canvas has no such dependency.
     */
    component ScreenBtn: Rectangle {
        id: screenBtn
        property bool expanded: false
        // Set by the caller: this is used both inside the control bar and as a
        // standalone overlay, so it cannot size itself from one parent.
        property real btnSize: videoController.height * 0.55
        signal clicked()

        width: btnSize
        height: btnSize
        radius: width / 2

        color: screenBtnArea.containsMouse ? "#964405" : "#5A3211"
        border.color: "#D08831"
        border.width: 1
        scale: screenBtnArea.containsMouse ? 1.15 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 150 } }

        Canvas {
            id: screenBtnCanvas
            anchors.centerIn: parent
            width: parent.width * 0.5
            height: width
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = "#ffffff"
                ctx.lineWidth = Math.max(1.5, width / 9)
                ctx.lineCap = "square"

                // Four corner brackets: pointing outward to enter fullscreen,
                // inward to leave it.
                var arm = width * 0.32
                var pad = screenBtn.expanded ? width * 0.28 : 0
                var corners = [
                    [pad,          pad,          1,  1],
                    [width - pad,  pad,         -1,  1],
                    [pad,          width - pad,  1, -1],
                    [width - pad,  width - pad, -1, -1]
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

    component ControlBtn: Rectangle {
        id: controlBtn
        property string icon: ""
        // Set this instead of `icon` for a bitmap glyph. The two are exclusive;
        // an image wins where both are given.
        property url iconSource: ""
        property var fontPixel: videoController.width / 35
        signal clicked()

        anchors.verticalCenter: parent.verticalCenter

        // An image has no text metrics to grow from, so image buttons take the
        // size of the round transport buttons sharing this bar rather than
        // collapsing to nothing.
        property real btnSize: String(controlBtn.iconSource) !== ""
            ? videoController.height * 0.6
            : Math.max(iconText.width + iconText.width * 0.6, iconText.height + iconText.height * 0.4)
        width: btnSize
        height: btnSize
        radius: width / 2

        color: btnArea.containsMouse ? "#964405" : "#5A3211"
        border.color: "#D08831"
        border.width: 1
        scale: btnArea.containsMouse ? 1.15 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 150 } }

        Text {
            id: iconText
            anchors.centerIn: parent
            text: parent.icon
            visible: String(controlBtn.iconSource) === ""
            color: '#ffffff'
            font.pixelSize: controlBtn.fontPixel
        }

        Image {
            anchors.centerIn: parent
            source: controlBtn.iconSource
            visible: String(controlBtn.iconSource) !== ""
            width: parent.width * 0.5
            height: parent.height * 0.5
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.clicked()
        }
    }

    function formatTime(ms) {
        if (ms <= 0) return "0:00"
        var totalSec = Math.floor(ms / 1000)
        var min = Math.floor(totalSec / 60)
        var sec = totalSec % 60
        return min + ":" + (sec < 10 ? "0" + sec : sec)
    }
}