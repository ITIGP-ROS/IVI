import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtMultimedia
import QtCore

ApplicationWindow {
    id: mainWindow
    width: 1024
    height: 600
    visible: true
    title: qsTr("IVI Dashboard")
    flags: Qt.FramelessWindowHint | Qt.Window

    property bool splashDone: false

    /*
     * Splash: the branded clip, nothing else. It runs its 90 frames once (~3 s)
     * and then fades into the UI.
     */
    Item {
        id: splashScreen
        anchors.fill: parent
        visible: !mainWindow.splashDone
        z: 10

        // Behind the clip, so the crop can never expose bare window on an
        // aspect ratio the gif does not cover.
        Rectangle { anchors.fill: parent; color: "#020408" }

        AnimatedImage {
            id: splashClip
            anchors.fill: parent
            source: "qrc:/assets/videos/vpace_splash.gif"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // 2.7 MB of frames, shown exactly once — there is nothing to gain
            // from keeping them around for the rest of the session.
            cache: false

            /*
             * AnimatedImage loops forever and has no "finished" signal, so the
             * end of the clip has to be spotted by hand. Stopping *on* the last
             * frame rather than after it matters: let it wrap and the gif
             * visibly restarts underneath the fade.
             *
             * Timing it with a fixed Timer instead would mean hard-coding the
             * clip's length, which then silently clips or double-plays the
             * first time someone drops in a different gif.
             */
            onCurrentFrameChanged: {
                if (frameCount > 1 && currentFrame === frameCount - 1) {
                    playing = false
                    splashFade.start()
                }
            }
        }

        NumberAnimation {
            id: splashFade
            target: splashScreen
            property: "opacity"
            to: 0
            duration: 300
            easing.type: Easing.InOutQuad
            onFinished: mainWindow.splashDone = true
        }

        // Backstop. A missing or undecodable gif must not strand the head unit
        // on a splash screen it can never leave — this is the one failure the
        // frame-driven dismissal above cannot catch by itself.
        Timer {
            interval: 6000
            running: true
            onTriggered: if (!mainWindow.splashDone) splashFade.start()
        }
    }

    property real appBrightness: 1.0

    // GLOBAL BRIGHTNESS OVERLAY
    Rectangle {
        id: brightnessOverlay
        parent: Overlay.overlay // Ensures it sits above popups and dialogs
        anchors.fill: parent
        color: "black"
        z: 99999
        
        // Invert the brightness to get opacity. 
        // Example: Brightness 1.0 -> Opacity 0.0 (Invisible)
        // Example: Brightness 0.2 -> Opacity 0.8 (Dark screen)
        opacity: 1.0 - mainWindow.appBrightness 
        
        // Optional: Animate the brightness changes so it feels premium
        Behavior on opacity {
            NumberAnimation { duration: 250; easing.type: Easing.InOutQuad }
        }
    }

    // Shared Media Player (persistent across all pages)
    MediaPlayer {
        id: sharedMediaPlayer
        audioOutput: AudioOutput { id: sharedAudioOutput; volume: 0.7 }
    }

    property string currentMediaTitle: ""
    property string currentMediaSubtitle: ""
    property string currentMediaFavicon: ""
    // 0 none · 1 radio · 2 audio (local/USB) · 3 video · 4 Bluetooth (A2DP)
    property int    currentMediaType: 0
    property bool   btMediaActive: currentMediaType === 4

    // Bluetooth is driven by the phone, not by sharedMediaPlayer, so the
    // play/pause state has to come from AVRCP instead.
    property bool   mediaPlaying: btMediaActive
                                  ? (btManager && btManager.playerStatus === "playing")
                                  : sharedMediaPlayer.playbackState === MediaPlayer.PlayingState

    // Mirror the phone's A2DP stream into the shared "now playing" state so it
    // surfaces everywhere the other sources do — media status bar and home tile.
    function syncBluetoothMedia() {
        if (!btManager) return

        var live = btManager.connected && btManager.playerStatus !== ""
        if (live) {
            currentMediaType     = 4
            currentMediaFavicon  = ""
            currentMediaTitle    = btManager.trackTitle !== "" ? btManager.trackTitle
                                                               : btManager.deviceName
            var parts = []
            if (btManager.trackArtist !== "") parts.push(btManager.trackArtist)
            if (btManager.trackAlbum  !== "") parts.push(btManager.trackAlbum)
            if (parts.length === 0 && btManager.deviceName !== "") parts.push(btManager.deviceName)
            currentMediaSubtitle = parts.join("  ·  ")
        } else if (currentMediaType === 4) {
            // Only clear if Bluetooth is what is showing — never stomp on a
            // local track the user started afterwards.
            currentMediaType     = 0
            currentMediaTitle    = ""
            currentMediaSubtitle = ""
        }
    }

    Connections {
        target: btManager
        function onConnectedChanged()    { mainWindow.syncBluetoothMedia() }
        function onPlayerStatusChanged() { mainWindow.syncBluetoothMedia() }
        function onTrackInfoChanged()    { mainWindow.syncBluetoothMedia() }
        function onDeviceNameChanged()   { mainWindow.syncBluetoothMedia() }
    }

    // --- NEW: GLOBAL RADIO STATE ---
    property string radioSearchQuery: ""
    property bool   radioSearchAttempted: false
    property bool   radioIsLoading: false
    property var    currentRadioStation: null

    // Persistent Model & API
    property alias  globalStationsModel: globalModel
    property var    globalRadioAPI: mainRadioAPI

    ListModel { id: globalModel }

    RadioAPI {
        id: mainRadioAPI
        stationsModel: globalModel
        radioPlayer: sharedMediaPlayer
        mainWindow: mainWindow
        onLoadingStarted: mainWindow.radioIsLoading = true
        onLoadingFinished: mainWindow.radioIsLoading = false
    }

    Settings {
        id: appSettings
        property string savedCity: "Giza"

        // Last reading that actually came back from the API. Seeding the
        // launcher from this means a boot with no network shows the real
        // numbers from last time rather than an invented placeholder.
        property string lastTemp:  ""
        property string lastDesc:  ""
        property string lastEmoji: ""
    }

    property string preferredCity: appSettings.savedCity

    onPreferredCityChanged: {
        appSettings.savedCity = mainWindow.preferredCity
    }

    /*
     * Routed here from the window bar's WiFi / Bluetooth status icons.
     *
     * Only this file can see the top-level stack, and both sub-pages live
     * inside Settings, so the bar cannot get there on its own. If Settings is
     * already on screen it is told to switch section rather than being pushed
     * a second time.
     */
    function openSettingsSection(section) {
        const settings = stackView.currentItem as SettingPage
        if (settings)
            settings.showSection(section)
        else
            stackView.push(settingPage, { pendingSection: section })
    }

    // No WindowResize: the head unit runs at one fixed size, and edge drag
    // handles on a touchscreen only give the driver a way to break the layout.

    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: launcherPage
    }

    // LAUNCHER PAGE
    Component {
        id: launcherPage

        Item {
            id: launcherItem
            signal openWeather()
            signal openClimateControl()
            signal openMedia()
            signal openSettings()
            signal openCarInfo()

            onOpenWeather:        stackView.push(weatherPage)
            onOpenClimateControl: stackView.push(climatePage)
            onOpenMedia:          stackView.push(mediaPage)
            onOpenSettings:       stackView.push(settingPage)
            onOpenCarInfo:        carInfoPopup.visible = true

            // Weather Data (updated via WeatherAPI component below)
            //
            // Seeded so the card reads as a weather card from the first frame
            // instead of sitting on "Loading..." — on a cold boot the UI is up
            // long before WiFi associates, so that placeholder was the first
            // thing the driver saw every single time.
            //
            // Order of preference: last successful reading, then a typical Giza
            // default for a unit that has never had a network. Neither is live,
            // so weatherIsLive gates the note on the location line — the card
            // must never present a stale or invented number as the real one.
            readonly property string fallbackTemp:  "30°C"
            readonly property string fallbackEmoji: "☀️"
            readonly property string fallbackDesc:  "Clear Sky"

            property bool   weatherIsLive: false
            property string currentTemp:  fallbackTemp
            property string currentEmoji: fallbackEmoji
            property string currentDesc:  fallbackDesc
            // Kept as a binding rather than assigned from the reply handler, so
            // the "not live" note comes back by itself when the city changes.
            property string resolvedLocation: ""
            property string locationText:
                "📍 " + (resolvedLocation !== "" ? resolvedLocation
                                                 : mainWindow.preferredCity)
                      + (weatherIsLive ? "" : " · not live")

            // shared HVAC quick-state (tile + page)
            property int  hvacMode:          0
            property int  hvacTemp:          23
            property int  hvacFan:           3
            property bool recircActive:      false
            property bool airQualityActive:  false
            property bool autoActive:        false
            property bool climatePower:      false
            property bool hvacSyncActive:    true
            property int  hvacRearTemp:     23
            property int  hvacRearFan:      3
            property int  hvacRearMode:     0
            property bool hvacRearPower:    false

            Component.onCompleted: {
                if (appSettings.lastTemp !== "") {
                    currentTemp  = appSettings.lastTemp
                    currentEmoji = appSettings.lastEmoji
                    currentDesc  = appSettings.lastDesc
                }
                weatherAPI.fetch(mainWindow.preferredCity)
            }

            Connections {
                target: mainWindow
                function onPreferredCityChanged() {
                    // What is on screen belongs to the old city, so it is not
                    // live any more until the new one comes back.
                    launcherItem.weatherIsLive    = false
                    launcherItem.resolvedLocation = ""
                    weatherAPI.fetch(mainWindow.preferredCity)
                }
            }

            // WiFi normally associates after the UI is already up, so the fetch
            // at startup has usually failed by the time there is a network.
            // Retrying on the transition fills the tile in straight away
            // instead of waiting out WeatherAPI's backoff.
            Connections {
                target: WifiManager
                function onConnectedSsidChanged() {
                    if (WifiManager.connectedSsid !== "")
                        weatherAPI.retryNow()
                }
            }

            WeatherAPI {
                id: weatherAPI

                // No handler for networkError: the card is already showing the
                // seeded reading with "not live" beside the city, which says
                // more than "Offline" did, and WeatherAPI keeps retrying
                // underneath. A wrong city name is different — that one never
                // resolves itself, so it has to be said out loud.
                onCityNotFound: function(city) {
                    launcherItem.currentDesc = "City not found"
                }

                onWeatherReceived: function(current, daily, hourly, location) {
                    launcherItem.weatherIsLive = true
                    launcherItem.currentTemp = Math.round(current.temperature_2m) + "°C"
                    var code = current.weather_code
                    var d    = current.is_day

                    if (code === 0)
                        launcherItem.currentDesc = d ? "Clear Sky" : "Clear Night"
                    else if (code <= 2)
                        launcherItem.currentDesc = "Partly Cloudy"
                    else if (code === 3)
                        launcherItem.currentDesc = "Overcast"
                    else if (code <= 48)
                        launcherItem.currentDesc = "Foggy"
                    else if (code <= 55)
                        launcherItem.currentDesc = "Drizzle"
                    else if (code <= 65)
                        launcherItem.currentDesc = "Rainy"
                    else if (code <= 75)
                        launcherItem.currentDesc = "Snowy"
                    else if (code <= 82)
                        launcherItem.currentDesc = "Rain Showers"
                    else
                        launcherItem.currentDesc = "Thunderstorm"

                    if (code === 0)
                        launcherItem.currentEmoji = d ? "☀️" : "🌙"
                    else if (code <= 2)
                        launcherItem.currentEmoji = d ? "🌤️" : "🌙"
                    else if (code === 3)
                        launcherItem.currentEmoji = "☁️"
                    else if (code <= 48)
                        launcherItem.currentEmoji = "🌫️"
                    else if (code <= 57)
                        launcherItem.currentEmoji = "🌦️"
                    else if (code <= 65)
                        launcherItem.currentEmoji = "🌧️"
                    else if (code <= 75)
                        launcherItem.currentEmoji = "❄️"
                    else if (code <= 82)
                        launcherItem.currentEmoji = "🌦️"
                    else
                        launcherItem.currentEmoji = "⛈️"
                    
                    launcherItem.resolvedLocation = location.name + ", " + location.country

                    // Remember it for the next cold boot.
                    appSettings.lastTemp  = launcherItem.currentTemp
                    appSettings.lastDesc  = launcherItem.currentDesc
                    appSettings.lastEmoji = launcherItem.currentEmoji
                }
            }

            // ============================================================
            // BACKGROUND
            // ============================================================
            Rectangle {
                anchors.fill: parent
                color: "#020408"

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#0a1628" }
                        GradientStop { position: 0.5; color: "#080e1c" }
                        GradientStop { position: 1.0; color: "#05070a" }
                    }
                }

                Rectangle {
                    x: parent.width * 0.2; y: parent.height * 0.3
                    width: 300; height: 300; radius: 150
                    color: "#1a3a5c"; opacity: 0.15
                    SequentialAnimation on x {
                        loops: Animation.Infinite
                        NumberAnimation { to: launcherItem.width * 0.25; duration: 8000; easing.type: Easing.InOutSine }
                        NumberAnimation { to: launcherItem.width * 0.2;  duration: 8000; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation on y {
                        loops: Animation.Infinite
                        NumberAnimation { to: launcherItem.height * 0.35; duration: 10000; easing.type: Easing.InOutSine }
                        NumberAnimation { to: launcherItem.height * 0.3;  duration: 10000; easing.type: Easing.InOutSine }
                    }
                }
                Rectangle {
                    x: parent.width * 0.7; y: parent.height * 0.6
                    width: 400; height: 400; radius: 200
                    color: "#2d1b4e"; opacity: 0.12
                    SequentialAnimation on x {
                        loops: Animation.Infinite
                        NumberAnimation { to: launcherItem.width * 0.65; duration: 12000; easing.type: Easing.InOutSine }
                        NumberAnimation { to: launcherItem.width * 0.7;  duration: 12000; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation on y {
                        loops: Animation.Infinite
                        NumberAnimation { to: launcherItem.height * 0.55; duration: 9000; easing.type: Easing.InOutSine }
                        NumberAnimation { to: launcherItem.height * 0.6;  duration: 9000; easing.type: Easing.InOutSine }
                    }
                }
            }

            // TOP GLASS BAR
            Rectangle {
                id: topBar
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.margins: 24; anchors.topMargin: 20
                height: 56; radius: 16
                color: Qt.rgba(1,1,1,0.04)
                border.color: Qt.rgba(1,1,1,0.08)
                border.width: 1

                Column {
                    id: timeColumn
                    anchors.left: parent.left
                    anchors.leftMargin: 25
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        id: timeText
                        color: "#ffffff"
                        font { pixelSize: 26; bold: true; family: "Arial" }
                    }
                    Text {
                        id: dateText
                        color: "#8899bb"
                        font { pixelSize: 12; family: "Arial" }
                    }
                }

                Column {
                    id: welcomeColumn
                    anchors.centerIn: parent;
                    spacing: 2
                    Text {
                        text: "Welcome"
                        color: "#ffffff"
                        font { pixelSize: 20; bold: true; family: "Arial" }
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: "Drive Safe"
                        color: "#8899bb"
                        font { pixelSize: 16; family: "Arial" }
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                Image {
                    id: mercedesLogo
                    source: "qrc:/assets/images/vpace.png"
                    width: 50; height: 50; fillMode: Image.PreserveAspectFit
                    anchors.right: parent.right; anchors.rightMargin: 25
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    var now = new Date()
                    dateText.text = now.toLocaleDateString(Qt.locale(), "dddd, MMM d yyyy")
                    timeText.text = now.toLocaleTimeString(Qt.locale(), "hh:mm AP")
                }
            }

            // BENTO GRID
            Row {
                id: bentoRow
                anchors.top: topBar.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.margins: 24; anchors.topMargin: 20
                spacing: 20

                // LEFT COLUMN (30.5%)
                Column {
                    width: parent.width * 0.305; height: parent.height; spacing: 20

                    // Weather
                    Item {
                        width: parent.width; height: parent.height * 0.4
                        Rectangle {
                            anchors.fill: parent; radius: 28
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: hovered ? Qt.rgba(0.2,0.6,1,0.4) : Qt.rgba(1,1,1,0.12)
                            border.width: 1
                            property bool hovered: false
                            scale: hovered ? 1.02 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1,1,1,0.08) }
                                    GradientStop { position: 0.5; color: "transparent" }
                                    GradientStop { position: 1.0; color: Qt.rgba(0,0,0,0.08) }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                color: "#36a9de"; opacity: 0.06; z: -1; anchors.margins: -2
                            }

                            transform: Translate { id: wFloat }
                            SequentialAnimation {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { target: wFloat; property: "y"; to: -5; duration: 4000; easing.type: Easing.InOutSine }
                                NumberAnimation { target: wFloat; property: "y"; to: 5;  duration: 4000; easing.type: Easing.InOutSine }
                            }

                            Column {
                                anchors.centerIn: parent; spacing: 10
                                Text { 
                                    text: launcherItem.currentEmoji
                                    font { pixelSize: 64 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text { 
                                    text: launcherItem.currentTemp
                                    color: "#ffffff"
                                    font { pixelSize: 42; bold: true; family: "Arial" }
                                    anchors.horizontalCenter: parent.horizontalCenter 
                                }
                                Text { 
                                    text: launcherItem.currentDesc
                                    color: "#aaccff"
                                    font { pixelSize: 16; family: "Arial" }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text { 
                                    text: launcherItem.locationText
                                    color: "#6677aa"
                                    font { pixelSize: 13; family: "Arial" }
                                    anchors.horizontalCenter: parent.horizontalCenter 
                                }
                            }

                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true
                                onEntered: parent.hovered = true
                                onExited:  parent.hovered = false
                                onClicked: launcherItem.openWeather()
                            }
                        }
                    }

                    // Voice Bar
                    Item {
                        width: parent.width; height: parent.height * 0.2
                        Rectangle {
                            anchors.fill: parent; radius: 24
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: hovered ? Qt.rgba(1,1,1,0.25) : Qt.rgba(1,1,1,0.12)
                            border.width: 1
                            property bool hovered: false
                            scale: hovered ? 1.02 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1,1,1,0.08) }
                                    GradientStop { position: 0.5; color: "transparent" }
                                    GradientStop { position: 1.0; color: Qt.rgba(0,0,0,0.08) }
                                }
                            }

                            transform: Translate { id: vFloat }
                            SequentialAnimation {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { target: vFloat; property: "y"; to: -3; duration: 4500; easing.type: Easing.InOutSine }
                                NumberAnimation { target: vFloat; property: "y"; to: 3;  duration: 4500; easing.type: Easing.InOutSine }
                            }

                            Row {
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 12

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 48; height: 48; radius: 24
                                    color: speechManager && speechManager.listening ? "#ff4444" : "#2674cc"
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: speechManager && speechManager.listening ? "🔴" : "🎤"
                                        font.pixelSize: 22
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        preventStealing: true
                                        pressAndHoldInterval: 100
                                        onPressed: {
                                            console.log("MIC PRESSED - speechManager:", speechManager)
                                            if (speechManager) speechManager.startListening()
                                        }
                                        onReleased: {
                                            console.log("MIC RELEASED")
                                            if (speechManager) speechManager.stopListening()
                                        }
                                        onCanceled: {
                                            console.log("MIC CANCELED")
                                            if (speechManager) speechManager.stopListening()
                                        }
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 70
                                    spacing: 4

                                    Text {
                                        width: parent.width
                                        clip: true
                                        elide: Text.ElideRight
                                        text: speechManager && speechManager.listening
                                            ? (speechManager.partialResult !== "" ? speechManager.partialResult : "Listening...")
                                            : "Hold to speak"
                                        color: speechManager && speechManager.listening ? "#ffffff" : "#8899bb"
                                        font {
                                            pixelSize: 14
                                            italic: !speechManager || !speechManager.listening
                                            family: "Arial"
                                        }
                                    }

                                    // Status indicator row
                                    Row {
                                        spacing: 6
                                        visible: speechManager !== null

                                        Rectangle {
                                            width: 8; height: 8; radius: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: {
                                                if (!speechManager) return "#444"
                                                if (speechManager.listening) return "#ff4444"
                                                return "#444"
                                            }
                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            // Pulsing animation when listening
                                            SequentialAnimation on opacity {
                                                running: speechManager && speechManager.listening
                                                loops: Animation.Infinite
                                                NumberAnimation { to: 0.3; duration: 500 }
                                                NumberAnimation { to: 1.0; duration: 500 }
                                                onStopped: parent.opacity = 1.0
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: {
                                                if (!speechManager) return "Unavailable"
                                                if (speechManager.listening) return "Recording..."
                                                return "Ready"
                                            }
                                            color: {
                                                if (!speechManager) return "#555"
                                                if (speechManager.listening) return "#ff8888"
                                                return "#556677"
                                            }
                                            font.pixelSize: 11
                                            font.family: "Arial"
                                        }
                                    }
                                }
                            }

                            HoverHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onHoveredChanged: parent.hovered = hovered
                            }

                            Connections {
                                target: speechManager
                                function onResultReady(text) {
                                    console.log("Recognized:", text)
                                    var lowerText = text.toLowerCase().trim()
                                    if (lowerText.includes("weather"))
                                        launcherItem.openWeather()
                                    else if (lowerText.includes("hvac") || lowerText.includes("climate") || lowerText.includes("ac"))
                                        launcherItem.openClimateControl()
                                    else if (lowerText.includes("media") || lowerText.includes("music") || lowerText.includes("radio"))
                                        launcherItem.openMedia()
                                    else if (lowerText.includes("settings") || lowerText.includes("setting"))
                                        launcherItem.openSettings()
                                    else if (lowerText.includes("about"))
                                        launcherItem.openCarInfo()
                                    // VOLUME COMMANDS
                                    else if (lowerText.includes("volume up") || lowerText.includes("increase volume")) {
                                        var newVol = Math.min(systemVolume.maxVolume, systemVolume.volume + 11)
                                        systemVolume.volume = newVol
                                        console.log("Volume up →", newVol + "%")
                                    }
                                    else if (lowerText.includes("volume down") || lowerText.includes("decrease volume")) {
                                        var newVol = Math.max(0, systemVolume.volume - 9)
                                        systemVolume.volume = newVol
                                        console.log("Volume down →", newVol + "%")
                                    }
                                    else if (lowerText.includes("volume mute") || lowerText.includes("mute")) {
                                        if (!systemVolume.muted)
                                            systemVolume.toggleMute()
                                        console.log("Volume muted")
                                    }
                                    else if (lowerText.includes("unmute")) {
                                        if (systemVolume.muted)
                                            systemVolume.toggleMute()
                                        console.log("Volume unmuted")
                                    }
                                    // FAN COMMANDS
                                    else if (lowerText.includes("fan up")) {
                                        var newFan = Math.min(7, launcherItem.hvacFan + 1)
                                        launcherItem.hvacFan = newFan
                                        console.log("Fan up →", newFan)
                                    }
                                    else if (lowerText.includes("fan down")) {
                                        var newFan = Math.max(0, launcherItem.hvacFan - 1)
                                        launcherItem.hvacFan = newFan
                                        console.log("Fan down →", newFan)
                                    }
                                    // TEMPERATURE COMMANDS
                                    else if (lowerText.includes("temp up")) {
                                        var newTemp = Math.min(30, launcherItem.hvacTemp + 1)
                                        launcherItem.hvacTemp = newTemp
                                        console.log("Temp up →", newTemp + "°")
                                    }
                                    else if (lowerText.includes("temp down")) {
                                        var newTemp = Math.max(16, launcherItem.hvacTemp - 1)
                                        launcherItem.hvacTemp = newTemp
                                        console.log("Temp down →", newTemp + "°")
                                    }
                                }

                                function onListeningChanged() {
                                    console.log("Listening state changed:", speechManager.listening)
                                }
                            }
                        }
                    }

                    // Volume Control — wired to shared C++ controller
                    Item {
                        width: parent.width; height: parent.height * 0.3
                        Rectangle {
                            id: volumeCardRect
                            anchors.fill: parent; radius: 28
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: hovered ? Qt.rgba(0.2,0.6,1,0.4) : Qt.rgba(1,1,1,0.12)
                            border.width: 1
                            property bool hovered: false
                            scale: hovered ? 1.02 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1,1,1,0.08) }
                                    GradientStop { position: 0.5; color: "transparent" }
                                    GradientStop { position: 1.0; color: Qt.rgba(0,0,0,0.08) }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                color: "#36a9de"; opacity: 0.06; z: -1; anchors.margins: -2
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                width: parent.width * 0.78

                                Item {
                                    width: parent.width
                                    height: volumeLabel.height

                                    Text {
                                        id: volumeLabel
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Volume"
                                        color: "#ffffff"
                                        font { pixelSize: 18; bold: true; family: "Arial" }
                                    }

                                }

                                Slider {
                                    id: volumeSlider
                                    width: parent.width
                                    height: 32
                                    from: 0
                                    to: systemVolume.maxVolume
                                    stepSize: 1
                                    live: true
                                    value: systemVolume.volume

                                    onValueChanged: {
                                        if (pressed && systemVolume.volume !== value)
                                            systemVolume.volume = value
                                    }

                                    background: Rectangle {
                                        x: volumeSlider.leftPadding
                                        y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                        width: volumeSlider.availableWidth
                                        height: 6
                                        radius: 3
                                        color: "#082839"

                                        Rectangle {
                                            width: volumeSlider.visualPosition * parent.width
                                            height: parent.height
                                            color: "#36a9de"
                                            radius: 3
                                        }
                                    }

                                    handle: Rectangle {
                                        x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                                        y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                        width: 16
                                        height: 16
                                        radius: 8
                                        color: volumeSlider.pressed ? "#ffffff" : "#36a9de"
                                        border.color: "#ffffff"
                                        border.width: 1.5
                                    }
                                }

                                Item { height: 8; width: 1 }

                                Rectangle {
                                    width: parent.width * 0.55
                                    height: 34
                                    radius: 8
                                    color: muteArea.containsMouse ? Qt.rgba(0.21, 0.66, 0.87, 0.2) : Qt.rgba(1,1,1,0.06)
                                    border.color: "#36a9de"
                                    border.width: 1
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: systemVolume.muted ? "Unmute" : "Mute"
                                        font { pixelSize: 15; family: "Arial"; bold: true }
                                        color: "#ffffff"
                                    }

                                    MouseArea {
                                        id: muteArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: systemVolume.toggleMute()
                                    }
                                }
                            }

                            HoverHandler {
                                onHoveredChanged: parent.hovered = hovered
                            }
                        }
                    }
                }

                // ---- MIDDLE COLUMN (35%) — CENTERED ----
                Column {
                    width: parent.width * 0.35; height: parent.height; spacing: 20

                    // Mercedes Status
                    Item {
                        width: parent.width; height: parent.height * 0.3
                        Rectangle {
                            anchors.fill: parent; radius: 28
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: hovered ? Qt.rgba(1,0.6,0.2,0.4) : Qt.rgba(1,1,1,0.12)
                            border.width: 1
                            property bool hovered: false
                            scale: hovered ? 1.02 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1,1,1,0.08) }
                                    GradientStop { position: 0.5; color: "transparent" }
                                    GradientStop { position: 1.0; color: Qt.rgba(0,0,0,0.08) }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                color: "#f79b55"; opacity: 0.06; z: -1; anchors.margins: -2
                            }

                            transform: Translate { id: cFloat }
                            SequentialAnimation {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { target: cFloat; property: "y"; to: 4;  duration: 5000; easing.type: Easing.InOutSine }
                                NumberAnimation { target: cFloat; property: "y"; to: -4; duration: 5000; easing.type: Easing.InOutSine }
                            }

                            Column {
                                anchors.centerIn: parent; spacing: 8
                                Image {
                                    source: "qrc:/assets/images/vpace.png"
                                    width: 65; height: 65; fillMode: Image.PreserveAspectFit
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text { 
                                    text: "V-PACE"
                                    color: "#e7f1ef"
                                    font { pixelSize: 20; bold: true; family: "Arial" }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text { 
                                    text: "System Online"
                                    color: "#21cfa4"
                                    font { pixelSize: 13; family: "Arial" }
                                    anchors.horizontalCenter: parent.horizontalCenter 
                                }
                                // NEW: hint text
                                Text {
                                    text: "Tap for info"
                                    color: Qt.rgba(1, 1, 1, 0.3)
                                    font { pixelSize: 10; italic: true; family: "Arial" }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: parent.hovered = true
                                onExited:  parent.hovered = false
                                onClicked: launcherItem.openCarInfo()
                            }
                        }
                    }

                    // HVAC
                    Item {
                        width: parent.width; height: parent.height * 0.65
                        Rectangle {
                            id: hvacRect
                            anchors.fill: parent; radius: 28
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: hovered ? Qt.rgba(0.6,0.3,1,0.4) : Qt.rgba(1,1,1,0.12)
                            border.width: 1
                            property bool hovered: false
                            scale: hovered ? 1.02 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1,1,1,0.08) }
                                    GradientStop { position: 0.5; color: "transparent" }
                                    GradientStop { position: 1.0; color: Qt.rgba(0,0,0,0.08) }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                color: "#a855f7"; opacity: 0.06; z: -1; anchors.margins: -2
                            }

                            transform: Translate { id: hFloat }
                            SequentialAnimation {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { target: hFloat; property: "y"; to: 3;  duration: 6000; easing.type: Easing.InOutSine }
                                NumberAnimation { target: hFloat; property: "y"; to: -3; duration: 6000; easing.type: Easing.InOutSine }
                            }

                            // Hover glow only — does NOT block clicks
                            HoverHandler {
                                onHoveredChanged: parent.hovered = hovered
                            }

                            // Small expand button (top-right) to open full page
                            Rectangle {
                                anchors.top: parent.top; anchors.right: parent.right
                                anchors.margins: 18
                                width: 35; height: 35; radius: 8
                                color: expandMa.containsMouse ? Qt.rgba(1,1,1,0.15) : Qt.rgba(1,1,1,0.05)
                                border.color: Qt.rgba(1,1,1,0.2)
                                border.width: 1
                                Image{
                                    anchors.centerIn: parent
                                    width: 20; height: 20
                                    source: "qrc:/assets/icons/pagenavigation.png"
                                    fillMode: Image.PreserveAspectFit
                                }
                                MouseArea {
                                    id: expandMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: launcherItem.openClimateControl()
                                }
                            }

                            Column {
                                anchors.fill: parent
                                anchors.margins: 10
                                anchors.topMargin: 20
                                spacing: 5

                                Text {
                                    text: "HVAC"
                                    color: "#ffffff"
                                    font { pixelSize: 22; bold: true; family: "Arial" }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                // Spacer
                                Item { height: 8; width: 1 }

                                // ---- 3 air direction modes ----
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 12
                                    Repeater {
                                        model: [
                                            "qrc:/assets/icons/parallel.png",
                                            "qrc:/assets/icons/feet.png",
                                            "qrc:/assets/icons/parallel-feet.png"
                                        ]
                                        Rectangle {
                                            width: 38; height: 38; radius: 8
                                            color: launcherItem.hvacMode === index ? '#18b78f' : Qt.rgba(1, 1, 1, 0.23)
                                            border.width: launcherItem.hvacMode === index ? 2 : 0
                                            border.color: "#FFFFFF"
                                            Image {
                                                anchors.centerIn: parent
                                                width: 22; height: 22
                                                source: modelData
                                                fillMode: Image.PreserveAspectFit
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: launcherItem.hvacMode = index
                                            }
                                        }
                                    }
                                }

                                // Spacer
                                Item { height: 6; width: 1 }

                                // ---- Temp + Fan mini gauges ----
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 16

                                    // Mini Temp
                                    Item {
                                        width: 135; height: 142

                                        Canvas {
                                            id: miniTempCanvas
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            width: 120; height: 120
                                            property real val: launcherItem.hvacTemp
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                var cx = width/2, cy = height/2, r = 50
                                                var t = (val - 16) / (30 - 16)
                                                var s = 0.8 * Math.PI, e = 2.2 * Math.PI, c = s + t*(e-s)
                                                ctx.clearRect(0,0,width,height)
                                                ctx.beginPath(); ctx.arc(cx,cy,r,s,e); ctx.lineWidth=9; ctx.strokeStyle="#082839"; ctx.lineCap="round"; ctx.stroke()
                                                ctx.beginPath(); ctx.arc(cx,cy,r,s,c); ctx.lineWidth=9; ctx.strokeStyle="#18b78f"; ctx.lineCap="round"; ctx.stroke()
                                            }
                                            onValChanged: requestPaint()
                                            Component.onCompleted: requestPaint()
                                        }

                                        Text {
                                            anchors.centerIn: miniTempCanvas
                                            text: Math.round(launcherItem.hvacTemp) + "°"
                                            color: "#FFFFFF"
                                            font { pixelSize: 32; bold: true; family: "Arial" }
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: miniTempCanvas.bottom
                                            anchors.topMargin: -18
                                            text: "Temperature"
                                            color: '#f5eee6'
                                            font { pixelSize: 14; bold: true; family: "Arial" }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            preventStealing: true

                                            function setTempFromMouse(mx, my) {
                                                var cx = parent.width / 2
                                                var cy = miniTempCanvas.height / 2
                                                var dx = mx - cx
                                                var dy = my - cy
                                                var rad = Math.atan2(dy, dx)
                                                var deg = rad * 180 / Math.PI
                                                if (deg < 0) deg += 360

                                                var startDeg = 144
                                                var sweepDeg = 252
                                                var t = 0
                                                if (deg >= 144 && deg <= 360) {
                                                    t = (deg - startDeg) / sweepDeg
                                                } else if (deg >= 0 && deg <= 36) {
                                                    t = (deg + 360 - startDeg) / sweepDeg
                                                } else {
                                                    // dead zone — snap to nearest end based on current value
                                                    t = (launcherItem.hvacTemp > 23) ? 1 : 0
                                                }

                                                var newVal = 16 + t * 14
                                                newVal = Math.round(newVal)
                                                newVal = Math.max(16, Math.min(30, newVal))
                                                if (newVal !== launcherItem.hvacTemp)
                                                    launcherItem.hvacTemp = newVal
                                            }

                                            onPressed: (mouse) => setTempFromMouse(mouse.x, mouse.y)
                                            onPositionChanged: (mouse) => {
                                                if (pressed) setTempFromMouse(mouse.x, mouse.y)
                                            }
                                        }
                                    }

                                    // Mini Fan
                                    Item {
                                        width: 135; height: 142

                                        Canvas {
                                            id: miniFanCanvas
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            width: 120; height: 120
                                            property real val: launcherItem.hvacFan
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                var cx = width/2, cy = height/2, r = 50
                                                var t = val / 7
                                                var s = 0.8 * Math.PI, e = 2.2 * Math.PI, c = s + t*(e-s)
                                                ctx.clearRect(0,0,width,height)
                                                ctx.beginPath(); ctx.arc(cx,cy,r,s,e); ctx.lineWidth=9; ctx.strokeStyle="#082839"; ctx.lineCap="round"; ctx.stroke()
                                                ctx.beginPath(); ctx.arc(cx,cy,r,s,c); ctx.lineWidth=9; ctx.strokeStyle="#18b78f"; ctx.lineCap="round"; ctx.stroke()
                                            }
                                            onValChanged: requestPaint()
                                            Component.onCompleted: requestPaint()
                                        }

                                        Text {
                                            anchors.centerIn: miniFanCanvas
                                            text: Math.round(launcherItem.hvacFan)
                                            color: "#FFFFFF"
                                            font { pixelSize: 32; bold: true; family: "Arial" }
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: miniFanCanvas.bottom
                                            anchors.topMargin: -18
                                            text: "Fan Speed"
                                            color: "#f5eee6"
                                            font { pixelSize: 14; bold: true; family: "Arial" }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            preventStealing: true

                                            function setFanFromMouse(mx, my) {
                                                var cx = parent.width / 2
                                                var cy = miniFanCanvas.height / 2
                                                var dx = mx - cx
                                                var dy = my - cy
                                                var rad = Math.atan2(dy, dx)
                                                var deg = rad * 180 / Math.PI
                                                if (deg < 0) deg += 360

                                                var startDeg = 144
                                                var sweepDeg = 252
                                                var t = 0
                                                if (deg >= 144 && deg <= 360) {
                                                    t = (deg - startDeg) / sweepDeg
                                                } else if (deg >= 0 && deg <= 36) {
                                                    t = (deg + 360 - startDeg) / sweepDeg
                                                } else {
                                                    t = (launcherItem.hvacFan > 3) ? 1 : 0
                                                }

                                                var newVal = t * 7
                                                newVal = Math.round(newVal)
                                                newVal = Math.max(0, Math.min(7, newVal))
                                                if (newVal !== launcherItem.hvacFan)
                                                    launcherItem.hvacFan = newVal
                                            }

                                            onPressed: (mouse) => setFanFromMouse(mouse.x, mouse.y)
                                            onPositionChanged: (mouse) => {
                                                if (pressed) setFanFromMouse(mouse.x, mouse.y)
                                            }
                                        }
                                    }
                                }

                                // ---- 5 master toggles (Recirc, AQ, Auto, Sync, Power) ----
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    // Recirc
                                    spacing: 8
                                    Rectangle {
                                        width: 36; height: 36; radius: 8
                                        color: launcherItem.recircActive ? '#18b78f' : Qt.rgba(1,1,1,0.08)
                                        border.color: "#FFFFFF"
                                        border.width: launcherItem.recircActive ? 2 : 0
                                        Image{
                                            anchors.centerIn: parent
                                            width: 18; height: 18
                                            fillMode: Image.PreserveAspectFit
                                            source: "qrc:/assets/icons/reload.png"
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: launcherItem.recircActive = !launcherItem.recircActive }
                                    }
                                    // Air Quality
                                    Rectangle {
                                        width: 36; height: 36; radius: 8
                                        color: launcherItem.airQualityActive ? '#18b78f' : Qt.rgba(1,1,1,0.08)
                                        border.color: "#FFFFFF"
                                        border.width: launcherItem.airQualityActive ? 2 : 0
                                        Text { anchors.centerIn: parent; text: "AQ"; color: "#FFFFFF"; font.pixelSize: 10; font.bold: true }
                                        MouseArea { anchors.fill: parent; onClicked: launcherItem.airQualityActive = !launcherItem.airQualityActive }
                                    }
                                    // Spacer
                                    Rectangle{
                                        width: 8; height: 8
                                        color: "transparent"
                                    }
                                    // Power
                                    Rectangle {
                                        width: 36; height: 36; radius: 18
                                        color: launcherItem.climatePower ? '#964405' : Qt.rgba(1,1,1,0.08)
                                        border.color: launcherItem.climatePower ? '#97ffffff' : "transparent"
                                        border.width: 1
                                        Image{
                                            anchors.centerIn: parent
                                            width: 18; height: 18
                                            fillMode: Image.PreserveAspectFit
                                            source: "qrc:/assets/icons/power.png"
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: launcherItem.climatePower = !launcherItem.climatePower }
                                    }
                                    // Spacer
                                    Rectangle{
                                        width: 8; height: 8
                                        color: "transparent"
                                    }
                                    Rectangle {
                                        width: 36; height: 36; radius: 8
                                        color: launcherItem.autoActive ? '#18b78f' : Qt.rgba(1,1,1,0.08)
                                        border.color: "#FFFFFF"
                                        border.width: launcherItem.autoActive ? 2 : 0
                                        Text { anchors.centerIn: parent; text: "AUTO"; color: "#FFFFFF"; font.pixelSize: 9; font.bold: true }
                                        MouseArea { anchors.fill: parent; onClicked: launcherItem.autoActive = !launcherItem.autoActive }
                                    }
                                    // SYNC
                                    Rectangle {
                                        width: 36; height: 36; radius: 8
                                        color: launcherItem.hvacSyncActive ? '#18b78f' : Qt.rgba(1,1,1,0.08)
                                        border.color: "#FFFFFF"
                                        border.width: launcherItem.hvacSyncActive ? 2 : 0
                                        Text {
                                            anchors.centerIn: parent
                                            text: "SYNC"
                                            color: "#FFFFFF"
                                            font { pixelSize: 9; bold: true; family: "Arial" }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: launcherItem.hvacSyncActive = !launcherItem.hvacSyncActive
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- RIGHT COLUMN (30.5%) ----
                Column {
                    width: parent.width * 0.305; height: parent.height; spacing: 20

                    // Media Player — MINI PLAYER TILE WITH CONTROLS
                    Item {
                        width: parent.width; height: parent.height * 0.45
                        Rectangle {
                            anchors.fill: parent; radius: 28
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: hovered ? Qt.rgba(0.1,0.8,0.6,0.4) : Qt.rgba(1,1,1,0.12)
                            border.width: 1
                            property bool hovered: false
                            scale: hovered ? 1.02 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1,1,1,0.08) }
                                    GradientStop { position: 0.5; color: "transparent" }
                                    GradientStop { position: 1.0; color: Qt.rgba(0,0,0,0.08) }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                color: "#21cfa4"; opacity: 0.06; z: -1; anchors.margins: -2
                            }

                            transform: Translate { id: mFloat }
                            SequentialAnimation {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { target: mFloat; property: "y"; to: -4; duration: 5500; easing.type: Easing.InOutSine }
                                NumberAnimation { target: mFloat; property: "y"; to: 4;  duration: 5500; easing.type: Easing.InOutSine }
                            }

                            HoverHandler {
                                onHoveredChanged: parent.hovered = hovered
                            }

                            Rectangle {
                                anchors.top: parent.top; anchors.right: parent.right
                                anchors.margins: 18
                                width: 35; height: 35; radius: 8
                                color: expandMe.containsMouse ? Qt.rgba(1,1,1,0.15) : Qt.rgba(1,1,1,0.05)
                                border.color: Qt.rgba(1,1,1,0.2)
                                border.width: 1
                                Image{
                                    anchors.centerIn: parent
                                    width: 20; height: 20
                                    source: "qrc:/assets/icons/pagenavigation.png"
                                    fillMode: Image.PreserveAspectFit
                                }
                                MouseArea {
                                    id: expandMe
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: launcherItem.openMedia()
                                }
                            }

                            Column {
                                anchors.centerIn: parent; spacing: 10

                                Rectangle {
                                    width: 70; height: 70; radius: 16
                                    color: Qt.rgba(1,1,1,0.08)
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Image {
                                        id: faviconImage
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        source: mainWindow.currentMediaFavicon
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        visible: mainWindow.currentMediaType === 1 && mainWindow.currentMediaFavicon !== "" && status === Image.Ready
                                    }

                                    // Bluetooth gets its own mark so the source is
                                    // identifiable at a glance, like radio's favicon.
                                    Image {
                                        id: btTileIcon
                                        anchors.centerIn: parent
                                        width: 36; height: 36
                                        source: "qrc:/assets/icons/bt.png"
                                        fillMode: Image.PreserveAspectFit
                                        visible: mainWindow.currentMediaType === 4
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: mainWindow.currentMediaType === 1 ? "📻" : "🎵"
                                        font.pixelSize: 32
                                        visible: mainWindow.currentMediaType !== 0
                                                 && !faviconImage.visible && !btTileIcon.visible
                                    }
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: "🎵"
                                        font.pixelSize: 32
                                        visible: mainWindow.currentMediaType === 0
                                    }
                                }

                                Text {
                                    text: mainWindow.currentMediaType !== 0 ? mainWindow.currentMediaTitle : "Media Player"
                                    color: "#ffffff"
                                    font { pixelSize: 18; bold: true; family: "Arial" }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    elide: Text.ElideRight
                                    width: parent.parent.width * 0.8
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Text {
                                    text: mainWindow.currentMediaType !== 0 ? mainWindow.currentMediaSubtitle : "Audio, Video & Radio"
                                    color: "#a3ffe0"
                                    font { pixelSize: 12; family: "Arial" }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    elide: Text.ElideRight
                                    width: parent.parent.width * 0.8
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                // Spacer
                                Rectangle{
                                    height: 5
                                    width: 1
                                    color: "transparent"
                                }

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 14
                                    visible: mainWindow.currentMediaType !== 0

                                    Rectangle {
                                        width: 32; height: 32; radius: 16
                                        color: tilePrevArea.containsMouse ? "#082839" : "#21cfa4"
                                        border.color: "#21cfa4"; border.width: 1
                                        visible: mainWindow.currentMediaType === 1
                                                 || mainWindow.currentMediaType === 4
                                        Image{
                                            anchors.centerIn: parent
                                            width: 18; height: 18
                                            source: "qrc:/assets/icons/prev.png"
                                            fillMode: Image.PreserveAspectFit
                                        }
                                        MouseArea {
                                            id: tilePrevArea; anchors.fill: parent; hoverEnabled: true
                                            onClicked: {
                                                if (mainWindow.btMediaActive) btManager.previous()
                                                else mainWindow.globalRadioAPI.playPrevious()
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: 32; height: 32; radius: 16
                                        color: tilePlayArea.containsMouse ? "#082839" : "#21cfa4"
                                        border.color: "#21cfa4"; border.width: 1
                                        Image{
                                            anchors.centerIn: parent
                                            width: 25; height: 25
                                            source: mainWindow.mediaPlaying? "qrc:/assets/icons/pause.png" : "qrc:/assets/icons/play.png"
                                            fillMode: Image.PreserveAspectFit
                                        }
                                        MouseArea {
                                            id: tilePlayArea; anchors.fill: parent; hoverEnabled: true
                                            onClicked: {
                                                if (mainWindow.btMediaActive) {
                                                    if (mainWindow.mediaPlaying) btManager.pause()
                                                    else                        btManager.play()
                                                } else if (mainWindow.mediaPlaying) sharedMediaPlayer.pause()
                                                else sharedMediaPlayer.play()
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: 32; height: 32; radius: 16
                                        color: tileStopArea.containsMouse ? "#082839" : "#ff4444"
                                        border.color: "#ff4444"; border.width: 1
                                        Image{
                                            anchors.centerIn: parent
                                            width: 16; height: 16
                                            source: "qrc:/assets/icons/stop.png"
                                            fillMode: Image.PreserveAspectFit
                                        }
                                        MouseArea {
                                            id: tileStopArea; anchors.fill: parent; hoverEnabled: true
                                            onClicked: {
                                                // Bluetooth playback lives on the phone; stopping
                                                // it is an AVRCP command, not a local stop.
                                                if (mainWindow.btMediaActive) { btManager.stop(); return }
                                                sharedMediaPlayer.stop()
                                                mainWindow.currentMediaType = 0
                                                mainWindow.currentMediaTitle = ""
                                                mainWindow.currentMediaSubtitle = ""
                                                mainWindow.currentMediaFavicon = ""
                                                mainWindow.currentRadioStation = null
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: 32; height: 32; radius: 16
                                        color: tileNextArea.containsMouse ? "#082839" : "#21cfa4"
                                        border.color: "#21cfa4"; border.width: 1
                                        visible: mainWindow.currentMediaType === 1
                                                 || mainWindow.currentMediaType === 4
                                        Image{
                                            anchors.centerIn: parent
                                            width: 18; height: 18
                                            source: "qrc:/assets/icons/next.png"
                                            fillMode: Image.PreserveAspectFit
                                        }
                                        MouseArea {
                                            id: tileNextArea; anchors.fill: parent; hoverEnabled: true
                                            onClicked: {
                                                if (mainWindow.btMediaActive) btManager.next()
                                                else mainWindow.globalRadioAPI.playNext()
                                            }
                                        }
                                    }
                                }

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 16
                                    visible: mainWindow.currentMediaType === 0
                                    Image{
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18; height: 18
                                        source: "qrc:/assets/icons/prev.png"
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    Image{
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 21; height: 21
                                        source: "qrc:/assets/icons/play.png"
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    Image{
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18; height: 18
                                        source: "qrc:/assets/icons/next.png"
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }
                            }
                        }
                    }

                    // Brightness Control (Left)
                    Item {
                        width: parent.width
                        height: parent.width * 0.39
                        Rectangle {
                            anchors.fill: parent; radius: 28
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: hovered ? Qt.rgba(0.95,0.75,0.2,0.5) : Qt.rgba(1,1,1,0.12)
                            border.width: 1
                            property bool hovered: false
                            scale: hovered ? 1.02 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1,1,1,0.08) }
                                    GradientStop { position: 0.5; color: "transparent" }
                                    GradientStop { position: 1.0; color: Qt.rgba(0,0,0,0.08) }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                color: "#f7c45f"; opacity: 0.06; z: -1; anchors.margins: -2
                            }

                            transform: Translate { id: brFloat }
                            SequentialAnimation {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { target: brFloat; property: "y"; to: -3; duration: 5200; easing.type: Easing.InOutSine }
                                NumberAnimation { target: brFloat; property: "y"; to: 3;  duration: 5200; easing.type: Easing.InOutSine }
                            }

                            HoverHandler {
                                onHoveredChanged: parent.hovered = hovered
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                width: parent.width * 0.75

                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    source: "qrc:/assets/icons/brightness.png"
                                    width: 34; height: 34
                                    fillMode: Image.PreserveAspectFit
                                }
                                Text {
                                    text: "Brightness"
                                    color: "#ffffff"
                                    font { pixelSize: 14; bold: true; family: "Arial" }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Slider {
                                    id: brightnessSlider
                                    width: parent.width
                                    height: 28
                                    from: 0.1
                                    to: 1.0
                                    stepSize: 0.01
                                    live: true
                                    value: mainWindow.appBrightness

                                    onValueChanged: {
                                        if (pressed && Math.abs(mainWindow.appBrightness - value) > 0.001)
                                            mainWindow.appBrightness = value
                                    }

                                    background: Rectangle {
                                        x: brightnessSlider.leftPadding
                                        y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                        width: brightnessSlider.availableWidth
                                        height: 6
                                        radius: 3
                                        color: "#082839"

                                        Rectangle {
                                            width: brightnessSlider.visualPosition * parent.width
                                            height: parent.height
                                            color: '#D08831'
                                            radius: 3
                                        }
                                    }

                                    handle: Rectangle {
                                        x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                                        y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                        width: 16
                                        height: 16
                                        radius: 8
                                        color: brightnessSlider.pressed ? "#ffffff" : '#815116'
                                        border.color: "#ffffff"
                                        border.width: 1.5
                                    }
                                }
                            }
                        }
                    }
                    // Settings
                    Item {
                        width: parent.width
                        height: parent.width * 0.33
                        Rectangle {
                            anchors.fill: parent; radius: 28
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: hovered ? Qt.rgba(1,1,1,0.3) : Qt.rgba(1,1,1,0.12)
                            border.width: 1
                            property bool hovered: false
                            scale: hovered ? 1.05 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1,1,1,0.08) }
                                    GradientStop { position: 0.5; color: "transparent" }
                                    GradientStop { position: 1.0; color: Qt.rgba(0,0,0,0.08) }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                color: "#f79b55"; opacity: 0.06; z: -1; anchors.margins: -2
                            }

                            transform: Translate { id: seFloat }
                            SequentialAnimation {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { target: seFloat; property: "y"; to: -4; duration: 5500; easing.type: Easing.InOutSine }
                                NumberAnimation { target: seFloat; property: "y"; to: 4;  duration: 5500; easing.type: Easing.InOutSine }
                            }

                            Column {
                                anchors.centerIn: parent; spacing: 10
                                Text { text: "⚙️"; font.pixelSize: 40; anchors.horizontalCenter: parent.horizontalCenter }
                                Text {
                                    text: "Settings"
                                    color: "#ffffff"
                                    font { pixelSize: 16; bold: true; family: "Arial" }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true
                                onEntered: parent.hovered = true
                                onExited:  parent.hovered = false
                                onClicked: launcherItem.openSettings()
                            }
                        }
                    }
                }
            }
            
            // CAR INFO POPUP
            CarInfoPopup {
                id: carInfoPopup
                visible: false
                z: 100
                onClosePopup: visible = false
            }

            // Climate Control page
            Component {
                id: climatePage
                ClimateControlPage {
                    id: climatePageInstance
                    onGoBack: stackView.pop()

                    // init from shared state 
                    Component.onCompleted: {
                        syncActive       = launcherItem.hvacSyncActive
                        frontTempValue   = launcherItem.hvacTemp
                        frontFanValue    = launcherItem.hvacFan
                        frontModeIndex   = launcherItem.hvacMode
                        frontPowerOn     = launcherItem.climatePower
                        recircActive     = launcherItem.recircActive
                        airQualityActive = launcherItem.airQualityActive
                        autoActive       = launcherItem.autoActive

                        if (syncActive) {
                            backTempValue  = launcherItem.hvacTemp
                            backFanValue   = launcherItem.hvacFan
                            backModeIndex  = launcherItem.hvacMode
                            backPowerOn    = launcherItem.climatePower
                        } else {
                            backTempValue  = launcherItem.hvacRearTemp
                            backFanValue   = launcherItem.hvacRearFan
                            backModeIndex  = launcherItem.hvacRearMode
                            backPowerOn    = launcherItem.hvacRearPower
                        }
                    }

                    // page → home tile (write-back) 
                    onSyncActiveChanged: {
                        launcherItem.hvacSyncActive = syncActive
                        if (syncActive) {
                            // when sync turned on, persist rear = front
                            launcherItem.hvacRearTemp  = frontTempValue
                            launcherItem.hvacRearFan   = frontFanValue
                            launcherItem.hvacRearMode  = frontModeIndex
                            launcherItem.hvacRearPower = frontPowerOn
                        }
                    }
                    onFrontTempValueChanged:   launcherItem.hvacTemp        = frontTempValue
                    onFrontFanValueChanged:    launcherItem.hvacFan         = frontFanValue
                    onFrontModeIndexChanged:   launcherItem.hvacMode        = frontModeIndex
                    onRecircActiveChanged:     launcherItem.recircActive    = recircActive
                    onAirQualityActiveChanged: launcherItem.airQualityActive= airQualityActive
                    onAutoActiveChanged:       launcherItem.autoActive      = autoActive
                    onFrontPowerOnChanged:     launcherItem.climatePower    = frontPowerOn

                    // rear only persists when sync is OFF
                    onBackTempValueChanged:  { if (!syncActive) launcherItem.hvacRearTemp  = backTempValue }
                    onBackFanValueChanged:   { if (!syncActive) launcherItem.hvacRearFan   = backFanValue }
                    onBackModeIndexChanged:  { if (!syncActive) launcherItem.hvacRearMode  = backModeIndex }
                    onBackPowerOnChanged:    { if (!syncActive) launcherItem.hvacRearPower = backPowerOn }

                    // home tile → page (read) 
                    Connections {
                        target: launcherItem
                        function onHvacSyncActiveChanged() {
                            climatePageInstance.syncActive = launcherItem.hvacSyncActive
                        }
                        function onHvacTempChanged() {
                            climatePageInstance.frontTempValue = launcherItem.hvacTemp
                            if (climatePageInstance.syncActive)
                                climatePageInstance.backTempValue = launcherItem.hvacTemp
                        }
                        function onHvacFanChanged() {
                            climatePageInstance.frontFanValue = launcherItem.hvacFan
                            if (climatePageInstance.syncActive)
                                climatePageInstance.backFanValue = launcherItem.hvacFan
                        }
                        function onHvacModeChanged() {
                            climatePageInstance.frontModeIndex = launcherItem.hvacMode
                            if (climatePageInstance.syncActive)
                                climatePageInstance.backModeIndex = launcherItem.hvacMode
                        }
                        function onRecircActiveChanged() {
                            climatePageInstance.recircActive = launcherItem.recircActive
                        }
                        function onAirQualityActiveChanged() {
                            climatePageInstance.airQualityActive = launcherItem.airQualityActive
                        }
                        function onAutoActiveChanged() {
                            climatePageInstance.autoActive = launcherItem.autoActive
                        }
                        function onClimatePowerChanged() {
                            climatePageInstance.frontPowerOn = launcherItem.climatePower
                            if (climatePageInstance.syncActive)
                                climatePageInstance.backPowerOn = launcherItem.climatePower
                        }
                    }
                }
            }
        }
    }

    // Weather page
    Component {
        id: weatherPage
        WeatherPage {
            onGoBack: stackView.pop()
            city: mainWindow.preferredCity
        }
    }

    Component {
        id: mediaPage
        MediaPlayerPage {
            mediaPlayer: sharedMediaPlayer
            mediaPage: mainWindow
            onGoBack: stackView.pop()
        }
    }

    Component {
        id: settingPage
        SettingPage {
            id: settingsInstance
            onGoBack: stackView.pop()
            preferredCity: mainWindow.preferredCity
            
            onPreferredCityChanged: {
                mainWindow.preferredCity = settingsInstance.preferredCity
                var launcher = stackView.get(0)
                if (launcher && launcher.weatherAPI) {
                    launcher.weatherAPI.fetch(settingsInstance.preferredCity)
                }
            }
        }
    }
}