import QtQuick
import QtQuick.Controls
pragma ComponentBehavior: Bound
import QtQuick.Dialogs
import QtMultimedia

Rectangle {
    id: videoPage
    required property StackView stackView
    anchors.fill: parent
    color: "transparent"

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
        width: videoPage.width - leftPanel.width - videoPage.width / 10
        height: videoPage.height - videoPage.height / 6
        anchors.top: parent.top
        anchors.topMargin: videoPage.height / 10
        anchors.left: leftPanel.right
        anchors.leftMargin: videoPage.width / 20
        color: 'transparent'
        border.color: '#D08831'
        border.width: 2
        radius: height / 20

        property int currentIndex: 0
        property var browseIcon: "📂"

        VideoOutput {
            id: videoOut
            z: 1
            anchors.fill: parent
            anchors.bottomMargin: videoController.height + videoProgress.height + videoPage.height / 16
            anchors.margins: videoPage.height / 50
        }

        // ================================================ Local video ===============================================
        Rectangle {
            anchors.fill: parent
            visible: rightPanel.currentIndex === 0
            color: 'transparent'

            onVisibleChanged: {
                if (visible) rightPanel.browseIcon = "📂"
            }

            FileDialog {
                id: fileDialog
                title: "Choose Video File"
                nameFilters: ["Video files (*.mp4 *.mkv *.avi *.mov *.wmv *.webm)", "All files (*)"]
                onAccepted: {
                    videoPlayer.source = fileDialog.selectedFile
                    videoPlayer.videoSelected = true
                    videoPlayer.play()
                }
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
                    text: "Select a video file"
                    color: '#3D717E'
                    font.pixelSize: videoPage.width / 35
                    font.family: "Arial"
                }
            }
        }

        // ================================================ Internet video ============================================
        Rectangle {
            anchors.fill: parent
            visible: rightPanel.currentIndex === 1
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
            visible: rightPanel.currentIndex === 2
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
                icon: audioOut.muted ? "🔈" : volumeSlider.value < 0.5 ? "🔉" : "🔊"
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

            ControlBtn {
                id: browseBtn
                icon: rightPanel.browseIcon
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: videoController.width / 20
                onClicked: rightPanel.currentIndex === 0 ? fileDialog.open() :
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
            visible: videoPlayer.videoSelected
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
                onClicked: {
                    videoPlayer.stop()
                    videoPlayer.videoSelected = false
                }
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

    component ControlBtn: Rectangle {
        id: controlBtn
        property string icon: ""
        property var fontPixel: videoController.width / 35
        signal clicked()

        anchors.verticalCenter: parent.verticalCenter

        property real btnSize: Math.max(iconText.width + iconText.width * 0.6, iconText.height + iconText.height * 0.4)
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
            color: '#ffffff'
            font.pixelSize: controlBtn.fontPixel
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