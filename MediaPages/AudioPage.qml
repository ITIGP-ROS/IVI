import QtQuick
import QtQuick.Controls
pragma ComponentBehavior: Bound
import QtQuick.Dialogs
import QtMultimedia

Rectangle {
    id: audioPage
    required property StackView stackView
    required property MediaPlayer mediaPlayer
    required property var        mediaPage
    anchors.fill: parent
    color: "transparent"

    property bool audioSelected: mediaPage.currentMediaType === 2
    property string errorMessage: ""
    property int currentFileIndex: -1

    // ── Error & state handling for the shared player ──
    Connections {
        target: mediaPlayer
        function onErrorOccurred(error, errorString) {
            if (mediaPage.currentMediaType !== 2) return
            audioPage.errorMessage = ""
            switch(error) {
                case MediaPlayer.NetworkError:
                    audioPage.errorMessage = "⚠  Cannot reach the server — check your internet connection"
                    break
                case MediaPlayer.FormatError:
                    audioPage.errorMessage = "⚠  Unsupported audio format"
                    break
                case MediaPlayer.AccessDeniedError:
                    audioPage.errorMessage = "⚠  Access denied — the server rejected the request"
                    break
                case MediaPlayer.ResourceError:
                    audioPage.errorMessage = "⚠  Invalid URL or resource not found"
                    break
                default:
                    audioPage.errorMessage = "⚠  " + errorString
            }
        }

        function onPlaybackStateChanged() {
            if (mediaPlayer.playbackState === MediaPlayer.PlayingState && mediaPage.currentMediaType === 2)
                audioPage.errorMessage = ""
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
        width: audioPage.width / 5
        height: parent.height
        color: '#082839'

        Column {
            anchors.top: parent.top
            anchors.topMargin: audioPage.height / 10
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: audioPage.height / 40
            // ========================================= Audio Sources ===================================================
            Repeater {
                model: [
                    { label: "🗂️  Local",    idx: 0 },
                    { label: "🔵  Bluetooth",idx: 2 },
                    { label: "💾  USB",      idx: 3 }
                ]

                delegate: Rectangle {
                    id: optionRect
                    required property var modelData
                    width: leftPanel.width * 0.8
                    height: audioPage.height / 14
                    radius: height / 5
                    color: rightPanel.currentIndex === modelData.idx ? '#5A3211'
                            : (srcArea.containsMouse ? '#10475E' : 'transparent')
                    border.color: rightPanel.currentIndex === modelData.idx ? '#D08831' : 'transparent'
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        text: optionRect.modelData.label
                        color: rightPanel.currentIndex === optionRect.modelData.idx ? '#D08831' : '#3D717E'
                        font.pixelSize: audioPage.width / 60
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
            // =============== Spacer ===================
            Rectangle{
                width: 1
                height: audioPage.height / 2.3
                color: "transparent"
            }

            // ============================================ Back button ===============================================
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
                    font.pixelSize: audioPage.width / 55
                    font.family: "Arial"
                    font.bold: true
                }

                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        audioPage.stackView.pop()
                    }
                }
            }
        }
    }

    // ========================================== Right Panel (Content & Controls) =========================================
    Rectangle {
        id: rightPanel
        width: audioPage.width - leftPanel.width - audioPage.width / 10
        height: audioPage.height - audioPage.height / 6
        anchors.top: parent.top
        anchors.topMargin: audioPage.height / 10
        anchors.left: leftPanel.right
        anchors.leftMargin: audioPage.width / 20
        color: 'transparent'
        border.color: '#D08831'
        border.width: 2
        radius: height / 20

        property int currentIndex: 0
        property var browseIcon: "📂"

        // ================================================ Local audio ===============================================
        Rectangle {
            anchors.fill: parent
            visible: rightPanel.currentIndex === 0
            color: 'transparent'

            onVisibleChanged: {
                if (visible) rightPanel.browseIcon = "📂"
            }

            FileDialog {
                id: fileDialog
                title: "Choose Audio File"
                nameFilters: ["Audio files (*.mp3 *.wav *.aac *.flac *.ogg *.m4a)", "All files (*)"]
                onAccepted: {
                    mediaPlayer.source = fileDialog.selectedFile
                    mediaPage.currentMediaType = 2
                    mediaPage.currentMediaTitle = fileDialog.selectedFile.toString().split("/").pop().replace(/\.[^.]+$/, "")
                    mediaPage.currentMediaSubtitle = "Local Audio"
                    mediaPlayer.play()
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: audioPage.width / 40
                anchors.verticalCenterOffset: -audioController.height / 2

                Image {
                    source: "qrc:/assets/icons/audio.png"
                    width: audioPage.height / 3
                    height: width
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                    visible: audioPage.audioSelected
                }

                Text {
                    text: audioPage.audioSelected ? mediaPlayer.source.toString().split("/").pop().replace(/\.[^.]+$/, "") : "Select an audio file"
                    color: audioPage.audioSelected ? '#e7f1ef' : '#3D717E'
                    font.bold: audioPage.audioSelected
                    font.pixelSize: audioPage.audioSelected? audioPage.width / 60 : audioPage.width / 35
                    font.family: "Arial"
                    width: audioPage.audioSelected? audioPage.width / 3 : audioPage.width / 4.1
                    wrapMode: Text.WordWrap
                    anchors.top: parent.top
                    anchors.topMargin: audioPage.audioSelected? audioPage.height / 15 : 0
                }
            }
        }

        // =============================================== Bluetooth audio ===========================================
        Rectangle {
            anchors.fill: parent
            visible: rightPanel.currentIndex === 2
            color: 'transparent'

            onVisibleChanged: {
                if (visible) rightPanel.browseIcon = "🔵"
            }

            Connections {
                target: btManager

                function onTrackInfoChanged() {
                    console.log("Track changed:", btManager.trackTitle)
                }
                function onPlayerStatusChanged() {
                    console.log("Status:", btManager.playerStatus)
                }
                function onConnectedChanged() {
                    console.log("Connected:", btManager.connected)
                }
            }

            Row {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -audioController.height / 2
                spacing: audioPage.width / 40

                Image {
                    source: "qrc:/assets//icons/audio.png"
                    width: audioPage.height / 3
                    height: width
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                    visible: btManager && btManager.connected
                    opacity: btManager && btManager.playerStatus === "playing" ? 1.0 : 0.5
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                }

                Column {
                    anchors.top: parent.top
                    anchors.topMargin: parent.height / 10
                    spacing: audioPage.height / 40

                    Text {
                        visible: !btManager || !btManager.connected
                        text: "No device connected"
                        color: '#3D717E'
                        font.family: "Arial"
                        font.pixelSize: audioPage.width / 35
                    }

                    Rectangle {
                        visible: btManager && btManager.connected
                        width: deviceNameText.width + 24
                        height: deviceNameText.height + 10
                        radius: height / 2
                        color: '#5A3211'
                        border.color: '#D08831'
                        border.width: 1

                        Text {
                            id: deviceNameText
                            anchors.centerIn: parent
                            text: btManager ? "🔵  " + btManager.deviceName : ""
                            color: '#D08831'
                            font.pixelSize: audioPage.width / 90
                            font.family: "Arial"
                        }
                    }

                    Text {
                        visible: btManager && btManager.connected
                        text: btManager && btManager.trackTitle !== ""
                            ? btManager.trackTitle
                            : "Play music on your phone"
                        color: btManager && btManager.trackTitle !== "" ? '#e7f1ef' : '#3D717E'
                        font.family: "Arial"
                        font.bold: btManager && btManager.trackTitle !== ""
                        font.pixelSize: audioPage.width / 55
                        wrapMode: Text.WordWrap
                        width: audioPage.width / 3
                    }

                    Text {
                        visible: btManager && btManager.connected && btManager.trackArtist !== ""
                        text: {
                            if (!btManager) return ""
                            if (btManager.trackArtist !== "" && btManager.trackAlbum !== "")
                                return btManager.trackArtist + "  ·  " + btManager.trackAlbum
                            return btManager.trackArtist
                        }
                        color: '#3D717E'
                        font.family: "Arial"
                        font.pixelSize: audioPage.width / 80
                        wrapMode: Text.WordWrap
                        width: audioPage.width / 3
                    }

                    Rectangle {
                        visible: btManager && btManager.connected && btManager.playerStatus !== ""
                        width: statusText.width + 24
                        height: statusText.height + 10
                        radius: height / 2
                        color: btManager && btManager.playerStatus === "playing" ? '#5A3211' : '#1a1a1a'
                        border.color: btManager && btManager.playerStatus === "playing" ? '#D08831' : '#50FFFFFF'
                        border.width: 1

                        Rectangle {
                            width: 6; height: 6; radius: 3
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: btManager && btManager.playerStatus === "playing" ? '#D08831' : '#3D717E'

                            SequentialAnimation on opacity {
                                running: btManager && btManager.playerStatus === "playing"
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 600; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                            }
                        }

                        Text {
                            id: statusText
                            anchors.centerIn: parent
                            leftPadding: 8
                            text: btManager ? btManager.playerStatus.charAt(0).toUpperCase()
                                            + btManager.playerStatus.slice(1) : ""
                            color: btManager && btManager.playerStatus === "playing" ? '#D08831' : '#3D717E'
                            font.pixelSize: audioPage.width / 95
                            font.family: "Arial"
                        }
                    }
                }
            }
        }

        // ================================================== USB audio ==============================================
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: audioPage.width / 20
            radius: audioPage.width / 20
            visible: rightPanel.currentIndex === 3
            color: 'transparent'

            onVisibleChanged: {
                if (visible) rightPanel.browseIcon = "💾"
            }

            Text {
                anchors.centerIn: parent
                visible: !usbManager.connected
                text: "Plug in a USB device"
                color: '#3D717E'
                font.pixelSize: audioPage.width / 35
                font.family: "Arial"
            }

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: audioPage.width / 65
                anchors.rightMargin: audioPage.width / 65
                anchors.leftMargin: audioPage.width / 65
                anchors.bottomMargin: audioPage.width / 18
                color: '#082839'
                visible: usbManager.scanning
                z: 5
                radius: audioPage.width / 60

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
                        font.pixelSize: audioPage.width / 60
                        font.family: "Arial"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "This may take a moment for phones (MTP)"
                        color: '#3D717E'
                        font.pixelSize: audioPage.width / 80
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
                            font.pixelSize: audioPage.width / 60
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
                        text: "Found: " + usbManager.audioFiles.length + " audio files"
                        color: '#3D717E'
                        font.pixelSize: audioPage.width / 80
                        visible: usbManager.audioFiles.length > 0
                    }
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: audioPage.height / 20
                anchors.bottomMargin: audioController.height + audioPage.height / 20
                spacing: audioPage.height / 30
                visible: usbManager.connected && !usbManager.scanning

                Row {
                    id: driveHeader
                    spacing: 10
                    Text {
                        text: "💾  " + usbManager.driveName
                        color: '#D08831'
                        font.pixelSize: audioPage.width / 55
                        font.bold: true
                        font.family: "Arial"
                    }
                    Text {
                        text: usbManager.audioFiles.length + " files"
                        color: '#3D717E'
                        font.pixelSize: audioPage.width / 75
                        font.family: "Arial"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    width: parent.width
                    height: parent.height - parent.spacing - driveHeader.height
                    clip: true
                    model: usbManager.audioFiles
                    spacing: 4

                    ScrollBar.vertical: ScrollBar {
                        id: listScrollBar
                        width: audioPage.width / 100
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        
                        contentItem: Rectangle {
                            implicitWidth: parent.width
                            radius: width / 2
                            color: listScrollBar.pressed ? '#964405' : listScrollBar.hovered ? '#D08831' : '#5A3211'
                            opacity: listScrollBar.hovered || listScrollBar.pressed ? 1.0 : 0.6
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
                        id: fileRow
                        required property string modelData
                        required property int index
                        width: ListView.view.width - listScrollBar.width * 2 
                        height: audioPage.height / 14
                        radius: height / 5
                        color: mediaPlayer.source.toString() === ("file://" + modelData)
                            ? '#5A3211'
                            : rowArea.containsMouse ? '#10475E' : 'transparent'
                        border.color: mediaPlayer.source.toString() === ("file://" + modelData)
                                    ? '#D08831' : 'transparent'
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: parent.width / 20
                            spacing: parent.width / 30

                            Text {
                                text: "🎵"
                                font.pixelSize: audioPage.width / 70
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: usbManager.fileName(fileRow.modelData)
                                color: mediaPlayer.source.toString() === ("file://" + fileRow.modelData)
                                    ? '#D08831' : '#e7f1ef'
                                font.pixelSize: audioPage.width / 70
                                font.family: "Arial"
                                elide: Text.ElideRight
                                width: parent.parent.width * 0.7
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                mediaPlayer.source = "file://" + fileRow.modelData
                                mediaPage.currentMediaType = 2
                                mediaPage.currentMediaTitle = usbManager.fileName(fileRow.modelData)
                                mediaPage.currentMediaSubtitle = "USB"
                                audioPage.currentFileIndex = fileRow.index
                                mediaPlayer.play()
                            }
                        }
                    }
                }
            }
        }

        // ========================================== Progress Slider ================================================
        Rectangle {
            id: audioProgress
            visible: rightPanel.currentIndex !== 2
            anchors.bottom: audioController.top
            anchors.left: audioController.left
            anchors.right: audioController.right
            anchors.bottomMargin: audioController.height / 100
            anchors.leftMargin: audioPage.width / 30
            anchors.rightMargin: audioPage.width / 30
            height: audioPage.height / 30
            radius: height / 2
            color: 'transparent'

            Slider {
                id: progressSlider
                anchors.bottom: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: -height / 2
                height: audioController.height / 4
                from: 0
                to: mediaPlayer.duration > 0 ? mediaPlayer.duration : 1
                value: mediaPlayer.position

                onMoved: mediaPlayer.position = value

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
                    visible: mediaPlayer.duration > 0
                }
            }

            Row {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: audioController.height / 30
                anchors.leftMargin: audioController.width / 120
                anchors.rightMargin: audioController.width / 120

                Text {
                    id: currentTimeText 
                    text: audioPage.formatTime(mediaPlayer.position)
                    color: '#3D717E'
                    font.pixelSize: audioController.height / 5
                    font.family: "Arial"
                }

                Item { width: parent.width - currentTimeText.width - totalTimeText.width; height: 1 }

                Text {
                    id: totalTimeText
                    text: audioPage.formatTime(mediaPlayer.duration)
                    color: '#3D717E'
                    font.pixelSize: audioController.height / 5
                    font.family: "Arial"
                }
            }
        }
        // ========================================== Playback Controls ================================================
        Rectangle {
            id: audioController
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: audioPage.height / 30
            height: audioPage.height / 11
            radius: height / 2
            color: '#5A3211'
            border.color: '#D08831'
            border.width: 1

            // Mute
            ControlBtn {
                id: volumeBtn
                property bool muted: false
                visible: rightPanel.currentIndex !== 2
                icon: mediaPlayer.audioOutput.muted ? "🔈" : volumeSlider.value < 0.5 ? "🔉" : "🔊"
                onClicked: mediaPlayer.audioOutput.muted = !mediaPlayer.audioOutput.muted
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: audioController.width / 20
            }

            // Volume Slider
            Slider {
                id: volumeSlider
                anchors.verticalCenter: parent.verticalCenter
                visible: rightPanel.currentIndex !== 2
                anchors.left: volumeBtn.right
                anchors.leftMargin: audioController.width / 80
                width: audioController.width / 8
                from: 0; to: 1; value: 0.6
                
                onValueChanged: {
                    mediaPlayer.audioOutput.volume = value
                    volumeBtn.muted = false
                    mediaPlayer.audioOutput.muted = false
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
                spacing: audioController.width / 55
                // Prev
                Rectangle {
                    id: prevBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: audioController.height * 0.6
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
                            if (rightPanel.currentIndex === 2 && btManager && btManager.connected)
                                btManager.previous()
                            else if (rightPanel.currentIndex === 3 && usbManager.connected && usbManager.audioFiles.length > 0) {
                                var newIndex = audioPage.currentFileIndex - 1
                                if(newIndex < 0) newIndex = usbManager.audioFiles.length - 1
                                audioPage.currentFileIndex = newIndex
                                mediaPlayer.source = "file://" + usbManager.audioFiles[newIndex]
                                mediaPage.currentMediaTitle = usbManager.fileName(usbManager.audioFiles[newIndex])
                                mediaPage.currentMediaSubtitle = "USB"
                                mediaPlayer.play()
                            }
                            else
                                mediaPlayer.position = 0
                        }
                    }
                }

                // Play / Pause
                Rectangle {
                    width: audioController.height * 0.72
                    height: width
                    radius: width / 2
                    color: playMainArea.containsMouse ? '#964405' : '#5A3211'
                    border.color: '#D08831'
                    border.width: 2
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Image{
                        anchors.centerIn: parent
                        width: 26; height: 26
                        source:  if(rightPanel.currentIndex === 2 && btManager && btManager.connected){
                                    btManager.playerStatus === "playing" ? "qrc:/assets/icons/pause.png" : "qrc:/assets/icons/play.png"
                                } 
                                else {
                                    mediaPlayer.playbackState === MediaPlayer.PlayingState ? "qrc:/assets/icons/pause.png" : "qrc:/assets/icons/play.png"
                                }
                        fillMode: Image.PreserveAspectFit
                    }

                    MouseArea {
                        id: playMainArea
                        anchors.fill: parent
                        hoverEnabled: true
                         onClicked: {
                            if(rightPanel.currentIndex === 2 && btManager && btManager.connected) {
                                if(btManager.playerStatus === "playing") {
                                    btManager.pause();
                                } 
                                else {
                                    btManager.play();
                                }
                            } 
                            else {
                                mediaPlayer.playbackState === MediaPlayer.PlayingState ? mediaPlayer.pause() : mediaPlayer.play()
                            }
                        }
                    }
                }

                // Next
                Rectangle {
                    id: nextBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: audioController.height * 0.6
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
                            if (rightPanel.currentIndex === 2 && btManager && btManager.connected)
                                btManager.next()
                            else if (rightPanel.currentIndex === 3 && usbManager.connected && usbManager.audioFiles.length > 0) {
                                var newIndex = audioPage.currentFileIndex + 1
                                if(newIndex >= usbManager.audioFiles.length) newIndex = 0
                                audioPage.currentFileIndex = newIndex
                                mediaPlayer.source = "file://" + usbManager.audioFiles[newIndex]
                                mediaPage.currentMediaTitle = usbManager.fileName(usbManager.audioFiles[newIndex])
                                mediaPage.currentMediaSubtitle = "USB"
                                mediaPlayer.play()
                            }
                            else
                                mediaPlayer.position = mediaPlayer.duration
                        }
                    }
                }
            }

            // Speed Indicator
            ControlBtn {
                id: speedIndicator
                icon: "1.0x"
                visible: rightPanel.currentIndex !== 2
                onClicked: speedSlider.value = 1
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: speedSlider.left
                anchors.rightMargin: audioController.width / 80
                fontPixel: audioController.width / 55
            }

            // Speed Slider
            Slider {
                id: speedSlider
                anchors.verticalCenter: parent.verticalCenter
                visible: rightPanel.currentIndex !== 2
                anchors.right: browseBtn.left
                anchors.rightMargin: audioController.width / 20
                width: audioController.width / 8
                from: 0.5; to: 8; value: 1
                
                onValueChanged: {
                    mediaPlayer.playbackRate = value
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

            // Browse
            ControlBtn {
                id: browseBtn
                icon: rightPanel.browseIcon
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: audioController.width / 20
                onClicked: rightPanel.currentIndex === 0 ? fileDialog.open() : 
                            rightPanel.currentIndex === 1 ? urlDialog.open() : console.log("Browse action for other sources coming soon")
            }
        }
    }

    component ControlBtn: Rectangle {
        id: controlBtn
        property string icon: ""
        property var fontPixel: audioController.width / 35
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