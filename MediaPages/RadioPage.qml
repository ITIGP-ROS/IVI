import QtQuick
import QtQuick.Controls
import QtMultimedia
pragma ComponentBehavior: Bound

/*
 * Internet radio browser.
 *
 * Laid out to the same skeleton as the audio and video pages — a narrow left
 * rail over the full height, a bordered content panel beside it, and a glass
 * transport pill along the bottom of that panel — so the three sub-pages read
 * as one app rather than three. What the rail holds differs: radio has no
 * sources to switch between, so it carries the station you are listening to
 * instead.
 */
Rectangle {
    id: radioPage
    required property StackView stackView
    required property MediaPlayer mediaPlayer
    required property var        mediaPage
    anchors.fill: parent
    color: "transparent"

    readonly property color accent: Theme.accentAmber

    // ---- geometry ----------------------------------------------------------
    // Same numbers as AudioPage/VideoPage. Deliberately: the rail width and the
    // panel inset are what make the three pages feel like one screen with a
    // different middle, and they drift the moment they are re-derived.
    readonly property real railW:  radioPage.width / 5
    readonly property real topPad: radioPage.height / 10

    // ---- shared-player state -----------------------------------------------
    /*
     * The MediaPlayer belongs to the window and is shared with the audio and
     * video pages, so every read of it has to be gated on radio actually owning
     * it (currentMediaType 1). The old code watched mediaStatus unconditionally
     * and lit this page's indicator while a local file was playing.
     */
    readonly property bool radioActive: mediaPage.currentMediaType === 1
                                        && mediaPage.currentRadioStation !== null
    readonly property bool radioPlaying: radioActive
                                         && mediaPlayer.playbackState === MediaPlayer.PlayingState

    readonly property string streamState: {
        if (!radioPage.radioActive) return "idle"
        switch (mediaPlayer.mediaStatus) {
        case MediaPlayer.LoadingMedia:
        case MediaPlayer.BufferingMedia: return "buffering"
        case MediaPlayer.BufferedMedia:  return "live"
        case MediaPlayer.StalledMedia:   return "stalled"
        case MediaPlayer.InvalidMedia:   return "error"
        default:                         return "idle"
        }
    }

    readonly property string streamLabel: {
        switch (radioPage.streamState) {
        case "buffering": return "Buffering"
        case "live":      return radioPage.radioPlaying ? "On air" : "Paused"
        case "stalled":   return "Reconnecting"
        case "error":     return "Stream error"
        default:          return "No station"
        }
    }

    readonly property color streamColor: {
        switch (radioPage.streamState) {
        case "buffering": return radioPage.accent
        case "live":      return radioPage.radioPlaying ? Theme.success : Theme.textSecondary
        case "stalled":
        case "error":     return Theme.danger
        default:          return Theme.textMuted
        }
    }

    // A dead stream used to fail silently — the station stayed highlighted and
    // nothing ever came out of the speakers.
    property string errorMessage: ""

    Connections {
        target: radioPage.mediaPlayer

        function onErrorOccurred(error, errorString) {
            if (radioPage.mediaPage.currentMediaType !== 1) return
            radioPage.errorMessage = errorString
        }

        function onPlaybackStateChanged() {
            if (radioPage.mediaPlayer.playbackState === MediaPlayer.PlayingState)
                radioPage.errorMessage = ""
        }
    }

    function playFromDelegate(d) {
        radioPage.errorMessage = ""
        radioPage.mediaPage.globalRadioAPI.playStation({
            stationuuid: d.stationuuid, name: d.name, url: d.url,
            favicon: d.favicon, country: d.country, codec: d.codec, tags: d.tags
        })
    }

    function runSearch() {
        radioPage.errorMessage = ""
        radioPage.mediaPage.radioSearchAttempted = true
        radioPage.mediaPage.globalStationsModel.clear()
        radioPage.mediaPage.globalRadioAPI.fetchStations()
    }

    // ========================================== Left rail =========================================
    // Height matches the content panel so the Back button can be lined up with
    // the transport bar by arithmetic — they sit in different parents, so they
    // cannot be anchored to each other.
    Item {
        id: leftRail
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: radioPage.topPad
        width: radioPage.railW
        height: rightPanel.height

        // ---- now playing ----
        GlassCard {
            id: nowCard
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: leftRail.width * 0.8
            height: radioPage.height * 0.45
            accent: radioPage.accent
            interactive: false

            Column {
                anchors.centerIn: parent
                width: parent.width * 0.84
                spacing: nowCard.height * 0.045

                // Station artwork, or the drawn receiver when the station has
                // no favicon — which is most of them on Radio Browser.
                Item {
                    id: artFrame
                    width: parent.width * 0.62
                    height: width
                    anchors.horizontalCenter: parent.horizontalCenter

                    // Breathing ring while the stream is actually up. Same idea
                    // as the Bluetooth disc on the audio page.
                    Rectangle {
                        id: pulseRing
                        anchors.centerIn: parent
                        width: parent.width + 14
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.color: radioPage.accent
                        border.width: 2
                        opacity: 0
                        SequentialAnimation on opacity {
                            running: radioPage.radioPlaying
                            loops: Animation.Infinite
                            // An `on opacity` animation leaves the property
                            // wherever it stopped, so without this the ring
                            // stays lit around a card that says "No station".
                            onStopped: pulseRing.opacity = 0
                            NumberAnimation { to: 0.45; duration: 1100; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.0;  duration: 1100; easing.type: Easing.InOutSine }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Theme.tint(radioPage.accent, radioPage.radioActive ? 0.16 : 0.06)
                        border.color: Theme.tint(radioPage.accent,
                                                 radioPage.radioActive ? 0.55 : 0.20)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 250 } }

                        Image {
                            id: nowArt
                            anchors.fill: parent
                            anchors.margins: parent.width * 0.14
                            source: radioPage.radioActive
                                    ? (radioPage.mediaPage.currentRadioStation.favicon || "") : ""
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                            asynchronous: true
                            mipmap: true
                        }

                        MediaGlyph {
                            anchors.centerIn: parent
                            width: parent.width * 0.46
                            height: width
                            kind: "radio"
                            tint: radioPage.radioActive ? radioPage.accent : Theme.textMuted
                            visible: !nowArt.visible
                        }
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: radioPage.radioActive
                          ? radioPage.mediaPage.currentRadioStation.name
                          : "No station playing"
                    color: radioPage.radioActive ? Theme.textPrimary : Theme.textSecondary
                    font { pixelSize: radioPage.width / 72; bold: true; family: "Arial" }
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: radioPage.radioActive
                          ? [radioPage.mediaPage.currentRadioStation.country,
                             radioPage.mediaPage.currentRadioStation.codec]
                            .filter(function (s) { return !!s }).join("  ·  ")
                          : "Search the directory to begin"
                    color: Theme.textSecondary
                    font { pixelSize: radioPage.width / 100; family: "Arial" }
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: radioPage.errorMessage !== ""
                    text: radioPage.errorMessage
                    color: Theme.danger
                    font { pixelSize: radioPage.width / 108; family: "Arial" }
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        // ---- back ----
        BackButton {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            // Level with the transport bar across the panel.
            anchors.bottomMargin: radioPage.height / 30
                                  + (controller.height - height) / 2
            accent: Theme.danger
            fontSize: radioPage.width / 55
            onClicked: radioPage.stackView.pop()
        }
    }

    // ========================================== Content panel =========================================
    Rectangle {
        id: rightPanel
        width: radioPage.width - leftRail.width - radioPage.width / 10
        height: radioPage.height - radioPage.height / 6
        anchors.top: parent.top
        anchors.topMargin: radioPage.topPad
        anchors.left: leftRail.right
        anchors.leftMargin: radioPage.width / 20
        color: "transparent"
        border.color: Theme.glassBorder
        border.width: 1
        radius: height / 20

        // ---- search row ----
        Item {
            id: searchRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: rightPanel.width / 26
            height: radioPage.height / 13

            // Fixed width, not sized to its text: letting it shrink to nothing
            // when the list is empty dragged the search field wider, so the
            // whole row jumped every time a search returned or was cleared.
            Text {
                id: countText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: radioPage.width / 11
                horizontalAlignment: Text.AlignRight
                text: radioPage.mediaPage.globalStationsModel.count > 0
                      ? radioPage.mediaPage.globalStationsModel.count + " stations" : ""
                color: Theme.textSecondary
                font { pixelSize: radioPage.width / 95; family: "Arial" }
                elide: Text.ElideRight
            }

            Rectangle {
                id: searchBtn
                anchors.right: countText.left
                anchors.rightMargin: radioPage.width / 70
                anchors.verticalCenter: parent.verticalCenter
                width: radioPage.width / 9
                height: parent.height
                radius: height / 2
                color: searchBtnArea.pressed ? Theme.tint(radioPage.accent, 0.42)
                     : searchBtnArea.containsMouse ? Theme.tint(radioPage.accent, 0.30)
                                                   : Theme.tint(radioPage.accent, 0.18)
                border.color: radioPage.accent
                border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "Search"
                    color: Theme.textPrimary
                    font { pixelSize: radioPage.width / 62; family: "Arial"; bold: true }
                }

                MouseArea {
                    id: searchBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: radioPage.runSearch()
                }
            }

            // Recessed rather than glass: this is the one thing on the page you
            // put something *into*, and Theme keeps a sunk colour for exactly
            // that. A glass pill here looked like a third button.
            Rectangle {
                id: searchWell
                anchors.left: parent.left
                anchors.right: searchBtn.left
                anchors.rightMargin: radioPage.width / 70
                height: parent.height
                radius: height / 2
                color: Theme.surfaceSunk
                border.color: searchMouse.containsMouse
                              ? Theme.tint(radioPage.accent, 0.7) : Theme.glassBorder
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 150 } }

                // Hidden input — the real text lives here and the on-screen
                // keyboard writes to it.
                TextInput {
                    id: searchField
                    visible: false
                    text: radioPage.mediaPage.radioSearchQuery
                    onTextChanged: {
                        radioPage.mediaPage.radioSearchQuery = text
                        if (text === "") radioPage.mediaPage.radioSearchAttempted = false
                    }
                }

                MediaGlyph {
                    id: searchIcon
                    anchors.left: parent.left
                    anchors.leftMargin: parent.height * 0.42
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.height * 0.44
                    height: width
                    kind: "search"
                    tint: searchField.text !== "" ? radioPage.accent : Theme.textSecondary
                }

                Text {
                    anchors.left: searchIcon.right
                    anchors.leftMargin: parent.height * 0.32
                    anchors.right: clearBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: searchField.text !== "" ? searchField.text : "Search station name…"
                    color: searchField.text !== "" ? Theme.textPrimary : Theme.textSecondary
                    font { pixelSize: radioPage.width / 62; family: "Arial" }
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: clearBtn
                    anchors.right: parent.right
                    anchors.rightMargin: parent.height * 0.22
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.height * 0.6
                    height: width
                    radius: width / 2
                    visible: searchField.text !== ""
                    color: clearArea.containsMouse ? Theme.glassFillHover : "transparent"

                    MediaGlyph {
                        anchors.centerIn: parent
                        width: parent.width * 0.5
                        height: width
                        kind: "close"
                        tint: clearArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                    }

                    MouseArea {
                        id: clearArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            searchField.text = ""
                            radioPage.mediaPage.globalStationsModel.clear()
                        }
                    }
                }

                MouseArea {
                    id: searchMouse
                    anchors.fill: parent
                    anchors.rightMargin: clearBtn.visible ? clearBtn.width + 12 : 0
                    hoverEnabled: true
                    onClicked: keyboardPopup.open()
                }
            }
        }

        // ---- station list ----
        Item {
            id: listArea
            anchors.top: searchRow.bottom
            anchors.topMargin: radioPage.height / 40
            anchors.left: searchRow.left
            anchors.right: searchRow.right
            anchors.bottom: controller.top
            anchors.bottomMargin: radioPage.height / 40

            ListView {
                id: stationList
                anchors.fill: parent
                model: radioPage.mediaPage.globalStationsModel
                clip: true
                spacing: 6
                visible: !radioPage.mediaPage.radioIsLoading

                ScrollBar.vertical: GlassScrollBar {
                    id: listScrollBar
                    accent: radioPage.accent
                    view: stationList
                    thickness: radioPage.width / 110
                }

                delegate: Rectangle {
                    id: row
                    required property string stationuuid
                    required property string name
                    required property string url
                    required property string favicon
                    required property string codec
                    required property string tags
                    required property string country
                    required property int    index

                    readonly property bool isActive:
                        radioPage.radioActive
                        && radioPage.mediaPage.currentRadioStation.stationuuid === row.stationuuid

                    width: stationList.width - listScrollBar.width * 2
                    height: radioPage.height / 8.6
                    radius: height / 4

                    color: row.isActive ? Theme.tint(radioPage.accent, 0.16)
                         : rowArea.containsMouse ? Theme.glassFillHover
                                                 : Theme.glassFill
                    border.color: row.isActive ? radioPage.accent
                                : rowArea.containsMouse ? Theme.tint(radioPage.accent, 0.45)
                                                        : Theme.glassBorder
                    border.width: row.isActive ? 2 : 1
                    Behavior on color        { ColorAnimation { duration: 140 } }
                    Behavior on border.color { ColorAnimation { duration: 160 } }

                    // Accent edge on the playing row. Reads at a glance from the
                    // driver's seat in a way a border-width change does not.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 4
                        height: parent.height * 0.5
                        radius: 2
                        color: radioPage.accent
                        opacity: row.isActive ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: parent.height * 0.22
                        anchors.rightMargin: parent.height * 0.22

                        Rectangle {
                            id: art
                            width: parent.height * 0.62
                            height: width
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            radius: width * 0.28
                            color: row.isActive ? Theme.tint(radioPage.accent, 0.18)
                                                : Theme.glassFill
                            border.color: row.isActive ? Theme.tint(radioPage.accent, 0.6)
                                                       : Theme.glassBorder
                            border.width: 1

                            Image {
                                id: artImage
                                anchors.fill: parent
                                anchors.margins: parent.width * 0.16
                                source: row.favicon
                                fillMode: Image.PreserveAspectFit
                                visible: status === Image.Ready
                                asynchronous: true
                                mipmap: true
                            }

                            MediaGlyph {
                                anchors.centerIn: parent
                                width: parent.width * 0.5
                                height: width
                                kind: "radio"
                                tint: row.isActive ? radioPage.accent : Theme.textSecondary
                                visible: !artImage.visible
                            }
                        }

                        Column {
                            anchors.left: art.right
                            anchors.leftMargin: parent.height * 0.20
                            anchors.right: rowPlay.left
                            anchors.rightMargin: parent.height * 0.20
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: parent.height * 0.045

                            Row {
                                id: nameRow
                                width: parent.width
                                spacing: 8

                                LevelMeter {
                                    id: rowEq
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: radioPage.width / 70
                                    height: width * 0.75
                                    tint: radioPage.accent
                                    visible: row.isActive && radioPage.radioPlaying
                                    running: visible
                                }

                                Text {
                                    text: row.name
                                    color: row.isActive ? radioPage.accent : Theme.textPrimary
                                    font { pixelSize: radioPage.width / 78; bold: true; family: "Arial" }
                                    elide: Text.ElideRight
                                    // A Row lays invisible children out at zero
                                    // width but still charges for the spacing.
                                    width: nameRow.width
                                           - (rowEq.visible ? rowEq.width + nameRow.spacing : 0)
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                width: parent.width
                                text: [row.country, row.codec]
                                      .filter(function (s) { return !!s }).join("  ·  ")
                                color: Theme.textSecondary
                                font { pixelSize: radioPage.width / 100; family: "Arial" }
                                elide: Text.ElideRight
                            }

                            // The directory returns tags as a bare CSV run
                            // ("pop,top40,charts"). Three of them, spaced, is
                            // as much as the row can carry legibly.
                            Text {
                                width: parent.width
                                text: row.tags.split(",")
                                         .filter(function (t) { return t.trim() !== "" })
                                         .slice(0, 3)
                                         .map(function (t) { return t.trim() })
                                         .join("   ·   ")
                                color: Theme.textMuted
                                font { pixelSize: radioPage.width / 108; family: "Arial" }
                                elide: Text.ElideRight
                                visible: text !== ""
                            }
                        }

                        Rectangle {
                            id: rowPlay
                            width: parent.height * 0.54
                            height: width
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            radius: width / 2
                            color: rowPlayArea.pressed ? Theme.tint(radioPage.accent, 0.5)
                                 : rowPlayArea.containsMouse ? Theme.tint(radioPage.accent, 0.35)
                                                             : Theme.tint(radioPage.accent, 0.10)
                            border.color: radioPage.accent
                            border.width: 1
                            scale: rowPlayArea.containsMouse ? 1.07 : 1
                            Behavior on color { ColorAnimation  { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 150 } }

                            Image {
                                anchors.centerIn: parent
                                width: parent.width * 0.42
                                height: width
                                source: row.isActive && radioPage.radioPlaying
                                        ? "qrc:/assets/icons/pause.png"
                                        : "qrc:/assets/icons/play.png"
                                fillMode: Image.PreserveAspectFit
                                mipmap: true
                            }

                            MouseArea {
                                id: rowPlayArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (row.isActive)
                                        radioPage.mediaPage.globalRadioAPI.togglePlayPause()
                                    else
                                        radioPage.playFromDelegate(row)
                                }
                            }
                        }
                    }

                    // Below the controls in stacking order, so the round button
                    // takes its own presses. A single tap starts the station —
                    // the double click this replaced is not a gesture anyone
                    // performs on a touch panel.
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        z: -1
                        onClicked: {
                            if (!row.isActive) radioPage.playFromDelegate(row)
                        }
                    }
                }
            }

            // ---- loading ----
            Item {
                id: loadingOverlay
                anchors.fill: parent
                visible: radioPage.mediaPage.radioIsLoading
                z: 10

                Column {
                    anchors.centerIn: parent
                    spacing: radioPage.height / 40

                    Spinner {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: radioPage.height / 12
                        height: width
                        tint: radioPage.accent
                        running: loadingOverlay.visible
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Searching stations…"
                        color: Theme.textPrimary
                        font { pixelSize: radioPage.width / 62; family: "Arial"; bold: true }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: radioPage.mediaPage.radioSearchQuery !== ""
                              ? "“" + radioPage.mediaPage.radioSearchQuery + "”"
                              : "Most voted worldwide"
                        color: Theme.textSecondary
                        font { pixelSize: radioPage.width / 95; family: "Arial" }
                    }
                }
            }

            // ---- empty ----
            Column {
                anchors.centerIn: parent
                spacing: radioPage.height / 45
                visible: radioPage.mediaPage.globalStationsModel.count === 0
                         && !radioPage.mediaPage.radioIsLoading
                z: 5

                MediaGlyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: radioPage.height / 8
                    height: width
                    kind: radioPage.mediaPage.radioSearchAttempted ? "warning" : "waves"
                    tint: radioPage.mediaPage.radioSearchAttempted
                          ? Theme.textSecondary : Theme.tint(radioPage.accent, 0.75)
                    accent: Theme.danger
                    weight: 0.85
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: radioPage.mediaPage.radioSearchAttempted
                          ? "No station found" : "Nothing tuned in yet"
                    color: Theme.textPrimary
                    font { pixelSize: radioPage.width / 55; family: "Arial"; bold: true }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: radioPage.mediaPage.radioSearchAttempted
                          ? "Try a shorter name, or clear the box to browse the top stations."
                          : "Search by name, or leave the box empty for the most voted stations."
                    color: Theme.textSecondary
                    font { pixelSize: radioPage.width / 90; family: "Arial" }
                }
            }
        }

        // ---- transport ----
        Rectangle {
            id: controller
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: radioPage.height / 30
            height: radioPage.height / 11
            radius: height / 2
            color: Theme.glassFill
            border.color: Theme.glassBorder
            border.width: 1

            // Accent halo, same trick as GlassCard's — it lifts the bar off the
            // backdrop without painting the bar itself.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: parent.radius + 2
                z: -1
                color: radioPage.accent
                opacity: 0.07
            }

            // Stream state, left.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: controller.height * 0.6
                spacing: 10

                Rectangle {
                    id: statusDot
                    width: 9
                    height: 9
                    radius: 4.5
                    anchors.verticalCenter: parent.verticalCenter
                    color: radioPage.streamColor
                    Behavior on color { ColorAnimation { duration: 200 } }

                    SequentialAnimation on opacity {
                        running: radioPage.streamState === "buffering"
                                 || radioPage.streamState === "stalled"
                        loops: Animation.Infinite
                        onStopped: statusDot.opacity = 1
                        NumberAnimation { to: 0.25; duration: 500; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0;  duration: 500; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: radioPage.streamLabel
                    color: radioPage.streamColor
                    font { pixelSize: radioPage.width / 95; family: "Arial"; bold: true }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }

            // Transport, centre.
            Row {
                anchors.centerIn: parent
                spacing: controller.width / 34

                // The three differ in size, so each has to be centred against
                // the Row itself — a Row only manages x.
                TransportButton {
                    accent: radioPage.accent
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: controller.height * 0.6
                    iconSource: "qrc:/assets/icons/prev.png"
                    onClicked: radioPage.mediaPage.globalRadioAPI.playPrevious()
                }

                TransportButton {
                    accent: radioPage.accent
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: controller.height * 0.78
                    ringWidth: 2
                    iconScale: 0.44
                    iconSource: radioPage.radioPlaying ? "qrc:/assets/icons/pause.png"
                                                       : "qrc:/assets/icons/play.png"
                    onClicked: {
                        if (!radioPage.radioActive) return
                        if (radioPage.radioPlaying) radioPage.mediaPlayer.pause()
                        else                        radioPage.mediaPlayer.play()
                    }
                }

                TransportButton {
                    accent: radioPage.accent
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: controller.height * 0.6
                    iconSource: "qrc:/assets/icons/next.png"
                    onClicked: radioPage.mediaPage.globalRadioAPI.playNext()
                }
            }

            // Volume, right.
            TransportButton {
                accent: radioPage.accent
                id: muteBtn
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: volumeSlider.left
                anchors.rightMargin: controller.width / 60
                diameter: controller.height * 0.6
                iconSource: radioPage.mediaPlayer.audioOutput.muted
                            ? "qrc:/assets/icons/volumedown.png"
                            : "qrc:/assets/icons/volumeup.png"
                onClicked: radioPage.mediaPlayer.audioOutput.muted =
                           !radioPage.mediaPlayer.audioOutput.muted
            }

            GlassSlider {
                id: volumeSlider
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: controller.height * 0.6
                width: controller.width / 6
                accent: radioPage.accent
                handleSize: 14
                from: 0
                to: 1
                value: 0.6

                onValueChanged: {
                    radioPage.mediaPlayer.audioOutput.volume = value
                    radioPage.mediaPlayer.audioOutput.muted = false
                }
            }
        }
    }

    // ========================================== Keyboard =========================================
    Popup {
        id: keyboardPopup
        parent: Overlay.overlay
        width: radioPage.width * 0.62
        height: radioPage.height * 0.72
        anchors.centerIn: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        Overlay.modal: Rectangle {
            color: Theme.scrim
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        background: Rectangle {
            color: Theme.surface
            radius: Theme.dialogRadius
            border.color: Theme.tint(radioPage.accent, 0.55)
            border.width: 1
        }

        onOpened: keyboard.targetText = searchField.text

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Search Stations"
                color: Theme.textPrimary
                font { pixelSize: radioPage.height * 0.042; bold: true; family: "Arial" }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Leave it empty for the most voted stations worldwide"
                color: Theme.textSecondary
                font { pixelSize: radioPage.height * 0.024; family: "Arial" }
            }

            VirtualKeyboard {
                id: keyboard
                width: parent.width
                targetItem: searchField
                passwordMode: false
                maxLength: 64

                accent:        radioPage.accent
                panelColor:    Theme.glassFill
                fieldColor:    Qt.rgba(0, 0, 0, 0.30)
                keyColor:      Theme.glassFill
                keyHoverColor: Theme.tint(radioPage.accent, 0.30)
                keyBorder:     Theme.glassBorder
                keyTextColor:  Theme.textPrimary
                enterColor:    Theme.tint(radioPage.accent, 0.22)

                onAccepted: {
                    radioPage.runSearch()
                    keyboard.clear()
                    keyboardPopup.close()
                }

                onCancelled: {
                    keyboard.clear()
                    keyboardPopup.close()
                }
            }
        }
    }
}
