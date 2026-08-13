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

    // OTA APPROVAL PROMPT
    // Lives on Overlay.overlay so it covers whatever page is on the stack —
    // an update request has to be answerable from media, settings, anywhere.
    // Below brightnessOverlay's z on purpose: the prompt is still subject to
    // the screen dimming, like every other thing on this display.
    OtaPopup {
        parent: Overlay.overlay
        anchors.fill: parent
        z: 9000
        ota: otaManager

        // Hold it back until the splash has finished. An offer waiting from
        // before boot would otherwise render underneath the splash clip and be
        // answered blind by whoever touches the screen first.
        visible: mainWindow.splashDone && opacity > 0
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
        // Reachable from Drive View's window bar, which is not on the stack —
        // step off it first, or the pushed page lands under a hidden StackView.
        driveViewLoader.shown = false
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
        // Above the loader while it warms up, below it once Drive View opens.
        z: 1

        // Nothing under Drive View is worth drawing: it covers the screen
        // opaquely, and leaving the launcher rendering behind it costs a full
        // extra scene every frame on top of the 3D view.
        //
// Gated on Ready, not just on `shown`. Tapping the card before the
        // asynchronous loader has finished would otherwise hide this while
        // Drive View is still not visible either — a black screen for however
        // long the scene takes to build. The launcher stays up until there is
        // something to replace it with.
        visible: !(driveViewLoader.shown && driveViewLoader.status === Loader.Ready
                   && !driveViewLoader.entering && !driveViewLoader.exiting)

        // The StackView's default push/pop move BOTH pages: the one arriving
        // slides in from the right while the one below slides out to the left
        // (push), and the reverse on pop. The launcher takes the "below" role
        // here, so it gets the opposite slide to the loader, via its own
        // Translate — the anchor system would snap a direct x write back.
        transform: Translate { id: launcherSlide }
    }

    /*
     * DRIVE VIEW — built once, then kept.
     *
     * It used to be a Component pushed onto the StackView, which destroys a
     * page when it is popped. So every trip back into Drive View re-created
     * the whole 3D world from nothing: two 1k HDRI probes (1.6 MB + 1.5 MB,
     * and an IBL probe has to be decoded and pre-filtered before the first
     * frame), the Audi ego model with its thirteen meshes and ~1.7 MB of maps,
     * the Tesla detection mesh, and 42 dynamically-created city instances.
     * That is the delay on the Jetson, and it was paid on every single entry.
     *
     * Now: `active` latches true and never goes back, so the cost is paid at
     * most once per boot; `shown` is what actually opens and closes it. A
     * hidden Item is not rendered, so keeping it costs memory, not frame time.
     *
     * asynchronous: the scene is incubated in slices instead of blocking the
     * GUI thread, so the launcher stays responsive while it builds rather than
     * freezing solid for the duration.
     */
    Loader {
        id: driveViewLoader
        anchors.fill: parent
        asynchronous: true
        active: false
        sourceComponent: driveViewPage

        // Separate from `active` on purpose: closing must not unload it.
        property bool shown: false

        // In-flight transitions, mimicking the StackView's default push/pop
        // (slide from/to the right, 400 ms, OutCubic) without destroying the
        // scene — it just slides in and out.
        property bool entering: false
        property bool exiting: false

        /*
         * Warm frame.
         *
         * Building the QML objects is only half the first-open cost. The other
         * half is GPU-side — pre-filtering the two HDRI probes into an IBL
         * environment, uploading the Audi and Tesla maps, compiling shaders —
         * and none of that happens until something actually renders. An
         * invisible Item never renders, so a purely hidden warm-up would have
         * left the whole GPU bill to be paid on the first open anyway.
         *
         * So for a short window after it loads, the scene renders for real,
         * underneath the launcher. Qt Quick has no occlusion culling: a covered
         * item is still drawn, still uploads its textures, still compiles its
         * shaders. The launcher's background is fully opaque (#020408 plus an
         * opaque gradient over it), so nothing of this is visible.
         *
         * Then it goes properly invisible and costs nothing per frame.
         */
        property bool warming: false

        // Below the launcher while warming, above everything once opened (and
        // while sliding out, so it stays on top of the launcher).
        z: shown || exiting ? 5 : 0

        visible: (shown ? status === Loader.Ready : warming) || entering || exiting

        // The slide animates this transform, not `x`: the loader is pinned by
        // anchors.fill, which would snap any direct x write straight back.
        transform: Translate { id: driveSlide }

        onStatusChanged: {
            if (status === Loader.Ready && !shown) {
                warming = true
                warmTimer.restart()
            }
            // A tap that reached the card before the async build finished
            // starts the slide only once there is something to slide.
            if (status === Loader.Ready && entering && !slideIn.running) {
                driveSlide.x = width
                launcherOut.from = launcherSlide.x
                launcherSlide.x = 0
                slideIn.start()
                launcherOut.start()
            }
        }
    }

    // Mimic the StackView's default push: the new page slides in from the
    // right while the page below (the launcher) slides out to the left.
    // Same 400 ms / OutCubic as Basic/StackView.qml.
    NumberAnimation {
        id: slideIn
        target: driveSlide
        property: "x"
        from: driveViewLoader.width
        to: 0
        duration: 400
        easing.type: Easing.OutCubic
        onFinished: driveViewLoader.entering = false
    }
    NumberAnimation {
        id: launcherOut
        target: launcherSlide
        property: "x"
        from: 0
        to: -driveViewLoader.width
        duration: 400
        easing.type: Easing.OutCubic
    }

    // Mimic the StackView's default pop: the top page slides out to the
    // right while the launcher re-enters from the left.
    NumberAnimation {
        id: slideOut
        target: driveSlide
        property: "x"
        to: driveViewLoader.width
        duration: 400
        easing.type: Easing.OutCubic
        onFinished: {
            driveViewLoader.shown = false
            driveViewLoader.exiting = false
            driveSlide.x = 0
        }
    }
    NumberAnimation {
        id: launcherIn
        target: launcherSlide
        property: "x"
        to: 0
        duration: 400
        easing.type: Easing.OutCubic
        onFinished: launcherSlide.x = 0
    }

    // How long to leave the scene rendering behind the launcher. There is no
    // signal for "all resources are resident", so this is a fixed window —
    // ~150 frames, far more than the handful the uploads and the probe
    // pre-filter actually need, and it only ever runs once per boot.
    Timer {
        id: warmTimer
        interval: 2500
        onTriggered: driveViewLoader.warming = false
    }

    // Warm Drive View up shortly after the splash clears, so the first tap on
    // the card is as quick as the ones after it. Deliberately not during the
    // splash: the video and the scene build would fight for the same GPU, and
    // a stuttering splash is more visible than a delay nobody is waiting on.
    Timer {
        interval: 1200
        running: mainWindow.splashDone && !driveViewLoader.active
        onTriggered: driveViewLoader.active = true
    }

    // LAUNCHER PAGE
    Component {
        id: launcherPage

        Item {
            id: launcherItem
            signal openWeather()
            signal openMedia()
            signal openSettings()
            signal openCarInfo()
            signal openDriveView()

            onOpenWeather:        stackView.push(weatherPage)
            onOpenMedia:          stackView.push(mediaPage)
            onOpenSettings:       stackView.push(settingPage)
            onOpenCarInfo:        carInfoPopup.visible = true
            // active latches on first use in case the warm-up timer has not
            // fired yet; after that this is just a visibility flip.
            onOpenDriveView: {
                driveViewLoader.active = true
                driveViewLoader.shown = true
                driveViewLoader.entering = true
                if (driveViewLoader.status === Loader.Ready) {
                    driveSlide.x = driveViewLoader.width
                    launcherOut.from = launcherSlide.x
                    launcherSlide.x = 0
                    slideIn.start()
                    launcherOut.start()
                }
                // otherwise the slides are started from onStatusChanged once
                // the async build finishes
            }

            // Weather Data (updated via WeatherAPI component below)
            //
            // Seeded so the card reads as a weather card from the first frame
            // instead of sitting on "Loading..." — on a cold boot the UI is up
            // long before WiFi associates, so that placeholder was the first
            // thing the driver saw every single time.
            //
            // Order of preference: last successful reading, then a typical Giza
            // default for a unit that has never had a network.
            //
            // The card used to mark a non-live reading with " · not live" beside
            // the city. It is gone: at this tile's width the note ate the city
            // name down to "milan · not l…", and it reported a condition the
            // driver can do nothing about — WeatherAPI is already retrying
            // underneath, and the reading it replaces is a real one either way.
            readonly property string fallbackTemp:  "30°C"
            readonly property string fallbackEmoji: "☀️"
            readonly property string fallbackDesc:  "Clear Sky"

            property string currentTemp:  fallbackTemp
            property string currentEmoji: fallbackEmoji
            property string currentDesc:  fallbackDesc
            property string resolvedLocation: ""
            property string locationText:
                "📍 " + (resolvedLocation !== "" ? resolvedLocation
                                                 : mainWindow.preferredCity)

            Component.onCompleted: {
                /*
                 * Cache first, summary second. WeatherStore keeps the full last
                 * reading on disk, so on a warm start the card is not just
                 * seeded but genuinely current. appSettings.last* stays as the
                 * fallback for a unit whose stored payload is missing or was
                 * written by an older build that had no store.
                 */
                if (!applyCached(mainWindow.preferredCity)
                        && appSettings.lastTemp !== "") {
                    currentTemp  = appSettings.lastTemp
                    currentEmoji = appSettings.lastEmoji
                    currentDesc  = appSettings.lastDesc
                }
                WeatherStore.request(mainWindow.preferredCity)
            }

            Connections {
                target: mainWindow
                function onPreferredCityChanged() {
                    // What is on screen belongs to the old city, so the resolved
                    // name has to go until the new one comes back — otherwise
                    // the card shows the new city's reading under the old
                    // city's name.
                    launcherItem.resolvedLocation = ""
                    launcherItem.applyCached(mainWindow.preferredCity)
                    WeatherStore.request(mainWindow.preferredCity)
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
                        WeatherStore.retryNow()
                }
            }

            /* Cached reading for a city onto the card. False if nothing cached. */
            function applyCached(city) {
                var e = WeatherStore.entryFor(city)
                if (e === null)
                    return false
                applyWeather(e.current, e.location)
                return true
            }

            Connections {
                target: WeatherStore

                /*
                 * No handler for failed() or notFound().
                 *
                 * The card is a glance, not a console. Both used to write their
                 * complaint into it — notFound() replaced the conditions line
                 * with "City not found" — and neither is answerable from the
                 * home screen: the city is set in Settings, and WeatherAPI
                 * retries a failed request on its own. So the card keeps showing
                 * the last real reading and says nothing about the fetch.
                 *
                 * The Weather page still reports a city that does not resolve.
                 * That is where the search box is, so there the message is the
                 * answer to something the driver just typed.
                 */
                function onUpdated(city) {
                    if (WeatherStore.normalise(city)
                            !== WeatherStore.normalise(mainWindow.preferredCity))
                        return
                    var e = WeatherStore.entryFor(city)
                    if (e === null)
                        return
                    launcherItem.applyWeather(e.current, e.location)

                    // Tiny always-writable fallback, separate from the store's
                    // full payload — see Component.onCompleted above.
                    appSettings.lastTemp  = launcherItem.currentTemp
                    appSettings.lastDesc  = launcherItem.currentDesc
                    appSettings.lastEmoji = launcherItem.currentEmoji
                }
            }

            function applyWeather(current, location) {
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
                // Lifts on hover. The bar is the only way into car info now
                // that the About card is gone, and a header that reacts to
                // nothing gives no hint that it can be pressed at all.
                color: topBarClick.containsMouse ? Qt.rgba(1,1,1,0.08)
                                                 : Qt.rgba(1,1,1,0.04)
                border.color: topBarClick.containsMouse ? Qt.rgba(1,1,1,0.18)
                                                        : Qt.rgba(1,1,1,0.08)
                border.width: 1
                Behavior on color        { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

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

                    // Same signal the window bar's WiFi icon watches, so the two
                    // can never disagree about whether we are connected.
                    readonly property bool online: WifiManager.connectedSsid !== ""

                    Text {
                        text: "Drive Safe"
                        color: "#ffffff"
                        font { pixelSize: 20; bold: true; family: "Arial" }
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: welcomeColumn.online ? "Online" : "Offline"
                        // Coloured, not just worded: at 16 px the two read alike
                        // at a glance, and this line is the only thing on the
                        // home screen that says whether the car has a link.
                        color: welcomeColumn.online ? "#3ad07a" : "#8899bb"
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

                // Last child, so it sits above the clock and the logo and gets
                // the press wherever on the bar it lands.
                MouseArea {
                    id: topBarClick
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: launcherItem.openCarInfo()
                }
            }

            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true

                // The car runs on UTC+3. Formatting `new Date()` directly means
                // trusting whatever zone the host is set to, and the Jetson's
                // image comes up as UTC — so the bar read three hours behind
                // even though the epoch time underneath was right.
                //
                // Deriving the wall clock from the epoch instead gives the same
                // answer on the Jetson and on a dev laptop in any zone: undo the
                // host's own offset, then add ours. getTimezoneOffset() is
                // UTC-minus-local, so adding it back lands on UTC.
                readonly property int tzOffsetMinutes: 3 * 60

                onTriggered: {
                    var now = new Date()
                    var here = new Date(now.getTime()
                                        + (now.getTimezoneOffset() + tzOffsetMinutes) * 60000)
                    dateText.text = here.toLocaleDateString(Qt.locale(), "dddd, MMM d yyyy")
                    timeText.text = here.toLocaleTimeString(Qt.locale(), "hh:mm AP")
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

                    // Fractions below are of this, not of `height`: the three
                    // add up to 100% on their own, so they have to share what is
                    // left after the gaps or the column overruns by 40 px.
                    readonly property real slot: height - spacing * 2

                    // Weather
                    Item {
                        width: parent.width; height: parent.slot * 0.32
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

                            /*
                             * Two columns either side of a hairline: icon and
                             * conditions on the left, the reading on the right.
                             *
                             * Stacked in one column this card was tall and
                             * narrow with dead space down both sides; split
                             * across the width it fits fonts 15% larger in the
                             * same 35% of the panel.
                             *
                             * Everything is a fraction of the card, not a fixed
                             * pixel size — the panel proportions have moved
                             * twice already and hard-coded sizes overflowed
                             * onto the card below both times.
                             */
                            Item {
                                id: weatherBody
                                anchors.fill: parent
                                anchors.margins: Math.round(parent.width * 0.07)

                                Rectangle {
                                    id: weatherSep
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 1
                                    height: Math.round(parent.height * 0.62)
                                    color: Qt.rgba(1,1,1,0.12)
                                }

                                // ---- left: icon + conditions
                                Column {
                                    anchors.right: weatherSep.left
                                    anchors.rightMargin: Math.round(weatherBody.width * 0.04)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.round(weatherBody.width * 0.44)
                                    spacing: Math.round(weatherBody.height * 0.04)

                                    Text {
                                        text: launcherItem.currentEmoji
                                        font { pixelSize: Math.round(weatherBody.height * 0.5) }
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                    Text {
                                        text: launcherItem.currentDesc
                                        color: "#aaccff"
                                        font { pixelSize: Math.max(14, Math.round(weatherBody.height * 0.12)); family: "Arial" }
                                        // Elided, not wrapped: "Thunderstorm With
                                        // Heavy Hail" is a real API string and a
                                        // second line pushes the icon off the card.
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }

                                // ---- right: reading + place
                                Column {
                                    anchors.left: weatherSep.right
                                    anchors.leftMargin: Math.round(weatherBody.width * 0.04)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.round(weatherBody.width * 0.44)
                                    spacing: Math.round(weatherBody.height * 0.04)

                                    Text {
                                        text: launcherItem.currentTemp
                                        color: "#ffffff"
                                        font { pixelSize: Math.round(weatherBody.height * 0.35); bold: true; family: "Arial" }
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    Text {
                                        text: launcherItem.locationText
                                        color: "#6677aa"
                                        font { pixelSize: Math.max(12, Math.round(weatherBody.height * 0.15)); family: "Arial" }
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
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

                    // Ambient — quick controls only; the picker, brightness and
                    // zones stay in Settings.
                    Item {
                        width: parent.width; height: parent.slot * 0.48
                        AmbientCard { anchors.fill: parent }
                    }


                    // Voice Bar
                    Item {
                        width: parent.width; height: parent.slot * 0.18
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
                                }

                                function onListeningChanged() {
                                    console.log("Listening state changed:", speechManager.listening)
                                }
                            }
                        }
                    }
                }

                // ---- MIDDLE COLUMN (35%) — CENTERED ----
                Column {
                    width: parent.width * 0.35; height: parent.height; spacing: 20

                    // Drive View (3D surroundings)
                    // 0.73 leaves room for the voice bar below it while the
                    // column still reaches the same depth as the two either
                    // side of it.
                    Item {
                        width: parent.width; height: parent.height * 0.64
                        Rectangle {
                            anchors.fill: parent; radius: 28
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: hovered ? Qt.rgba(0.4,0.7,1,0.5) : Qt.rgba(1,1,1,0.12)
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
                                color: "#4a9eff"; opacity: 0.06; z: -1; anchors.margins: -2
                            }

                            // Live preview of the same scene the full page
                            // draws. Fills the card — it masks itself to the
                            // card's corners, so it no longer needs an inset to
                            // stay clear of them.
                            MiniScene3D {
                                id: drivePreview
                                anchors.fill: parent
                                // Follow the card, so the preview can never be
                                // the one square-cornered tile on the launcher.
                                cornerRadius: parent.radius
                            }

                            // ROS link indicator. Grey and still when nothing is
                            // publishing, so a dead pipeline is visible from the
                            // home screen instead of looking like an empty road.
                            Row {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 20
                                spacing: 6

                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: drivePreview.hasSignal ? "#3ad07a" : "#6b7280"
                                    SequentialAnimation on opacity {
                                        running: drivePreview.hasSignal
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutSine }
                                    }
                                }
                                Text {
                                    text: drivePreview.hasSignal ? "LIVE" : "OFFLINE"
                                    color: drivePreview.hasSignal ? "#3ad07a" : "#6b7280"
                                    font { pixelSize: 11; bold: true; letterSpacing: 1.2; family: "Arial" }
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Below the overlays, so the badges and the expand
                            // button get the clicks that land on them.
                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true
                                z: -1
                                onEntered: parent.hovered = true
                                onExited:  parent.hovered = false
                                onClicked: launcherItem.openDriveView()
                            }
                        }
                    }

                    // Volume Control — wired to shared C++ controller
                    Item {
                        width: parent.width; height: parent.height * 0.305
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
                // Assigning preferredCity is enough on its own now — the
                // launcher watches it and the store dedupes — but the explicit
                // request keeps the fetch starting from here rather than
                // depending on notification order.
                mainWindow.preferredCity = settingsInstance.preferredCity
                WeatherStore.request(settingsInstance.preferredCity)
            }
        }
    }

    // Drive View page (3D surroundings, ROS2). Hosted by driveViewLoader, not
    // by the StackView — going home hides it instead of destroying it.
    Component {
        id: driveViewPage
        DriveViewPage {
            onGoBack: {
                slideIn.stop()
                launcherOut.stop()
                driveViewLoader.entering = false
                driveViewLoader.exiting = true
                slideOut.from = driveSlide.x
                launcherIn.from = launcherSlide.x
                slideOut.start()
                launcherIn.start()
            }
        }
    }
}
