import QtQuick
import QtQuick.Controls

pragma ComponentBehavior: Bound

/*
 * Weather, on the home screen's glass.
 *
 * Three things changed from the teal-and-amber version:
 *
 *  - The palette is Theme's, and the backdrop is the shared GlassBackground, so
 *    this page and Settings cannot drift apart.
 *
 *  - Every icon is drawn (WeatherGlyph) instead of typed as an emoji. The old
 *    ones — ☀️ 🌧️ 💨 🧭 — are not in Liberation Sans, which is what "Arial"
 *    resolves to on both the dev laptop and the Yocto image, so the entire icon
 *    set was rendering as tofu boxes.
 *
 *  - Qt5Compat's InnerShadow/DropShadow are gone. There were seven stacked
 *    shadow chains here, each an offscreen render target, and the drop shadow
 *    sat outside the pane and gave every card a hard edge. GlassCard gets the
 *    same depth from a halo and a sheen gradient with no extra layers.
 *
 * The data path is untouched: WeatherStore still owns fetching and caching, and
 * applyWeather() still paints from either a fresh reply or the cache.
 */
Item {
    id: root

    signal goBack()
    property int currentHour: 2
    property string city: "Giza"

    // ---- layout -------------------------------------------------------------
    readonly property real gutter:    width * 0.042
    readonly property real colGap:    width * 0.014
    readonly property real rowGap:    height * 0.022
    readonly property real innerW:    width - gutter * 2
    // The window bar is drawn over this page rather than above it.
    readonly property real barClear:  height * 0.088

    readonly property real headerH:   height * 0.105
    readonly property real rowAH:     height * 0.300
    readonly property real rowBH:     height * 0.372

    // ---- condition ----------------------------------------------------------
    /*
     * The current condition as a WeatherGlyph kind. Held as state rather than
     * recomputed at each use site: the hero glyph, the card's accent and the
     * backdrop's orbs all key off it, and they must never disagree.
     */
    property string conditionKind: "partly-day"

    /*
     * One hue per condition. This is what makes the page feel like weather
     * rather than like a table — the glow behind the glass is amber at noon,
     * violet at night and blue in rain, and it is the same hue on the hero
     * card's halo and on the backdrop's orbs.
     */
    function conditionAccent(kind) {
        switch (kind) {
        case "clear-day":    return Theme.accentAmber
        case "showers":
        case "partly-day":   return Theme.accentCyan
        case "clear-night":
        case "partly-night": return Theme.accentViolet
        case "rain":
        case "drizzle":      return Theme.accentBlue
        case "snow":         return "#bcd8f5"
        case "thunder":      return "#c9a6ff"
        case "fog":
        case "overcast":     return Theme.textSecondary
        default:             return Theme.accentCyan
        }
    }
    readonly property color conditionColor: root.conditionAccent(root.conditionKind)

    function weatherKind(code, isDay) {
        if (code === 0)  return isDay ? "clear-day"  : "clear-night"
        if (code <= 2)   return isDay ? "partly-day" : "partly-night"
        if (code === 3)  return "overcast"
        if (code <= 48)  return "fog"
        if (code <= 55)  return "drizzle"
        if (code <= 65)  return "rain"
        if (code <= 67)  return "rain"
        if (code <= 77)  return "snow"
        if (code <= 82)  return "showers"
        if (code <= 86)  return "snow"
        if (code <= 99)  return "thunder"
        return "partly-day"
    }

    // Shown under the title when a search comes back empty. Without it a bad
    // city name silently cleared the box and nothing else happened.
    property string statusNote: ""

    // ---- models -------------------------------------------------------------
    // `t`, `tmax` and `tmin` are the numeric twins of the display strings. The
    // curve and the range bars need to do arithmetic, and parsing "19°C" back
    // out of the label at paint time is the kind of thing that works until a
    // locale puts a minus sign in front of it.
    ListModel {
        id: weatherInfoModel
        ListElement { label: "Wind Speed";     glyph: "wind";     value: "12 km/h"  }
        ListElement { label: "Humidity";       glyph: "humidity"; value: "65%"      }
        ListElement { label: "Wind Direction"; glyph: "compass";  value: "270°"     }
        ListElement { label: "Pressure";       glyph: "pressure"; value: "1013 hPa" }
    }
    ListModel {
        id: hourlyWeatherModel
        ListElement { time: "12 AM"; temp: "19°C"; t: 19 } ListElement { time: "1 AM";  temp: "18°C"; t: 18 }
        ListElement { time: "2 AM";  temp: "18°C"; t: 18 } ListElement { time: "3 AM";  temp: "17°C"; t: 17 }
        ListElement { time: "4 AM";  temp: "17°C"; t: 17 } ListElement { time: "5 AM";  temp: "17°C"; t: 17 }
        ListElement { time: "6 AM";  temp: "18°C"; t: 18 } ListElement { time: "7 AM";  temp: "19°C"; t: 19 }
        ListElement { time: "8 AM";  temp: "21°C"; t: 21 } ListElement { time: "9 AM";  temp: "23°C"; t: 23 }
        ListElement { time: "10 AM"; temp: "25°C"; t: 25 } ListElement { time: "11 AM"; temp: "27°C"; t: 27 }
        ListElement { time: "12 PM"; temp: "29°C"; t: 29 } ListElement { time: "1 PM";  temp: "30°C"; t: 30 }
        ListElement { time: "2 PM";  temp: "31°C"; t: 31 } ListElement { time: "3 PM";  temp: "31°C"; t: 31 }
        ListElement { time: "4 PM";  temp: "30°C"; t: 30 } ListElement { time: "5 PM";  temp: "28°C"; t: 28 }
        ListElement { time: "6 PM";  temp: "26°C"; t: 26 } ListElement { time: "7 PM";  temp: "24°C"; t: 24 }
        ListElement { time: "8 PM";  temp: "23°C"; t: 23 } ListElement { time: "9 PM";  temp: "22°C"; t: 22 }
        ListElement { time: "10 PM"; temp: "21°C"; t: 21 } ListElement { time: "11 PM"; temp: "20°C"; t: 20 }
    }
    ListModel {
        id: dailyWeatherModel
        ListElement { day: "Today";     uvIndex: 2.1; maxTemp: "26°C"; minTemp: "15°C"; tmax: 26; tmin: 15 }
        ListElement { day: "Tomorrow";  uvIndex: 2.5; maxTemp: "27°C"; minTemp: "17°C"; tmax: 27; tmin: 17 }
        ListElement { day: "Tuesday";   uvIndex: 4.0; maxTemp: "28°C"; minTemp: "17°C"; tmax: 28; tmin: 17 }
        ListElement { day: "Wednesday"; uvIndex: 4.6; maxTemp: "27°C"; minTemp: "17°C"; tmax: 27; tmin: 17 }
        ListElement { day: "Thursday";  uvIndex: 5.9; maxTemp: "29°C"; minTemp: "18°C"; tmax: 29; tmin: 18 }
        ListElement { day: "Friday";    uvIndex: 7.1; maxTemp: "32°C"; minTemp: "20°C"; tmax: 32; tmin: 20 }
        ListElement { day: "Saturday";  uvIndex: 8.5; maxTemp: "33°C"; minTemp: "21°C"; tmax: 33; tmin: 21 }
    }

    function uvColor(uv) {
        const v = Math.round(uv)
        return v <= 2 ? Theme.success
             : v <= 5 ? Theme.accentAmber
             : v <= 7 ? "#f4a445"
             : v <= 10 ? Theme.danger
                       : "#c060c0"
    }

    // Span of the week, so every day's bar is drawn on the same scale — a bar
    // per row normalised to itself would make every day look identical.
    function weekSpan() {
        let lo = 1e9, hi = -1e9
        for (let i = 0; i < dailyWeatherModel.count; i++) {
            const e = dailyWeatherModel.get(i)
            if (e.tmin < lo) lo = e.tmin
            if (e.tmax > hi) hi = e.tmax
        }
        if (lo > hi) { lo = 0; hi = 1 }
        if (hi - lo < 1) hi = lo + 1
        return { lo: lo, hi: hi }
    }
    property var span: ({ lo: 15, hi: 33 })

    // ==================================================== BACKDROP
    GlassBackground {
        z: -1
        anchors.fill: parent
        orbA: root.conditionColor
        // Well under the default: the condition hues are saturated, and at full
        // strength one of them washes the whole page and takes the glass with it.
        orbAStrength: 0.24
        orbB: Theme.accentBlue
        orbBStrength: 0.30
        Behavior on orbA { ColorAnimation { duration: 600 } }
    }

    WindowBar {
        id: titleBar
        z: 2
        window: mainWindow
        titleName: "Weather"
        showBackButton: true
        onBackRequested: root.goBack()

        color0: Theme.gradientTop
        color1: Theme.gradientMid
        color2: Theme.gradientBot
        accent: Theme.accentCyan
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

    // ==================================================== HEADER
    Item {
        id: header
        anchors {
            left: parent.left;   leftMargin:  root.gutter
            right: parent.right; rightMargin: root.gutter
            top: parent.top;     topMargin:   root.barClear
        }
        height: root.headerH

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.height * 0.006
            width: parent.width * 0.5

            Text {
                id: cityName
                text: "Cairo, Egypt"
                color: Theme.textPrimary
                font { bold: true; family: "Arial"; pixelSize: root.height * 0.048 }
                elide: Text.ElideRight
                width: parent.width
            }
            Text {
                text: root.statusNote !== "" ? root.statusNote
                                             : qsTr("Population ") + populationValue.text
                color: root.statusNote !== "" ? Theme.accentAmber : Theme.textSecondary
                font { family: "Arial"; pixelSize: root.height * 0.024 }
                elide: Text.ElideRight
                width: parent.width
            }
        }

        // Holds the value so the line above can read it without applyWeather
        // needing to know how the header is laid out.
        Text { id: populationValue; visible: false; text: "137,844" }

        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: root.width * 0.010

            // SEARCH — a glass well rather than a filled box, so it belongs to
            // the same surface family as the cards.
            Rectangle {
                id: cityInputContainer
                width: root.width * 0.235
                height: root.height * 0.062
                radius: height / 2
                color: cityInputMouse.containsMouse ? Theme.glassFillHover : Theme.glassFill
                border.width: 1
                border.color: cityInputMouse.containsMouse
                              ? Theme.tint(Theme.accentCyan, 0.55) : Theme.glassBorder
                Behavior on color        { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                WeatherGlyph {
                    id: searchGlyph
                    kind: "search"
                    tint: cityInputMouse.containsMouse ? Theme.accentCyan : Theme.textSecondary
                    width: parent.height * 0.46; height: width
                    anchors {
                        left: parent.left; leftMargin: parent.height * 0.34
                        verticalCenter: parent.verticalCenter
                    }
                    Behavior on tint { ColorAnimation { duration: 150 } }
                }

                Text {
                    anchors {
                        left: searchGlyph.right; leftMargin: parent.height * 0.28
                        right: parent.right;     rightMargin: parent.height * 0.34
                        verticalCenter: parent.verticalCenter
                    }
                    text: cityInputHidden.text !== "" ? cityInputHidden.text
                                                      : qsTr("Search a city")
                    color: cityInputHidden.text !== "" ? Theme.textPrimary : Theme.textMuted
                    font { family: "Arial"; pixelSize: root.height * 0.026 }
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: cityInputMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: keyboardPopup.open()
                }
            }

            // REFRESH
            Rectangle {
                id: refreshBtn
                width: root.height * 0.062
                height: width
                radius: width / 2
                color: refreshMouse.containsMouse ? Theme.glassFillHover : Theme.glassFill
                border.width: 1
                border.color: refreshMouse.containsMouse
                              ? Theme.tint(Theme.accentCyan, 0.55) : Theme.glassBorder
                scale: refreshMouse.pressed ? 0.9 : 1.0
                Behavior on scale        { NumberAnimation { duration: 120 } }
                Behavior on color        { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                WeatherGlyph {
                    id: refreshGlyph
                    kind: "refresh"
                    tint: refreshMouse.containsMouse ? Theme.accentCyan : Theme.textSecondary
                    width: parent.width * 0.5; height: width
                    anchors.centerIn: parent
                    Behavior on tint { ColorAnimation { duration: 150 } }

                    // A full turn on tap. The reply usually lands from cache
                    // before this finishes, so the spin is what tells you the
                    // press registered at all.
                    RotationAnimation {
                        id: spin
                        target: refreshGlyph
                        from: 0; to: 360
                        duration: 600
                        easing.type: Easing.InOutQuad
                    }
                }

                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    // Forced: the refresh button exists precisely to overrule the TTL.
                    onClicked: { spin.restart(); root.showCity(cityInputHidden.text, true) }
                }
            }
        }
    }

    // ==================================================== ROW A
    Item {
        id: rowA
        anchors {
            left: parent.left;   leftMargin:  root.gutter
            right: parent.right; rightMargin: root.gutter
            top: header.bottom;  topMargin:   root.rowGap
        }
        height: root.rowAH

        // ---- NOW
        GlassCard {
            id: heroCard
            width: root.innerW * 0.345
            height: parent.height
            accent: root.conditionColor
            interactive: false
            Behavior on accent { ColorAnimation { duration: 600 } }

            Row {
                anchors.centerIn: parent
                spacing: heroCard.width * 0.055

                WeatherGlyph {
                    kind: root.conditionKind
                    tint: Theme.textPrimary
                    accent: root.conditionColor
                    width: heroCard.height * 0.44
                    height: width
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: heroCard.height * 0.012

                    Text {
                        id: temperature
                        text: "21°C"
                        color: Theme.textPrimary
                        font { bold: true; family: "Arial"
                               pixelSize: heroCard.height * 0.33 }
                    }
                    Text {
                        id: weatherDescription
                        text: "Partly Cloudy"
                        color: Theme.textPrimary
                        font { family: "Arial"; pixelSize: heroCard.height * 0.115 }
                    }
                    Text {
                        id: feelsLike
                        text: "Feels like 19°C"
                        color: Theme.textSecondary
                        font { family: "Arial"; pixelSize: heroCard.height * 0.095 }
                    }
                }
            }
        }

        // ---- 24 HOURS
        GlassCard {
            id: hourlyCard
            anchors.right: parent.right
            width: root.innerW - heroCard.width - root.colGap
            height: parent.height
            accent: Theme.accentCyan
            interactive: false

            Text {
                id: hourlyTitle
                anchors {
                    left: parent.left; leftMargin: hourlyCard.width * 0.030
                    top: parent.top;   topMargin:  hourlyCard.height * 0.10
                }
                text: qsTr("NEXT 24 HOURS")
                color: Theme.textMuted
                font { bold: true; family: "Arial"
                       pixelSize: root.height * 0.021; letterSpacing: 1.2 }
            }

            Flickable {
                id: hourlyFlick
                anchors {
                    left: parent.left;     leftMargin:   hourlyCard.width * 0.024
                    right: parent.right;   rightMargin:  hourlyCard.width * 0.024
                    top: hourlyTitle.bottom; topMargin:  hourlyCard.height * 0.04
                    bottom: parent.bottom; bottomMargin: hourlyCard.height * 0.07
                }
                contentWidth: hourStrip.width
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Item {
                    id: hourStrip
                    readonly property real slotW: root.width * 0.062
                    width: slotW * hourlyWeatherModel.count
                    height: hourlyFlick.height

                    // Where the curve lives inside a slot, as fractions of the
                    // strip height. The labels sit above and below it.
                    readonly property real curveTop: height * 0.34
                    readonly property real curveH:   height * 0.34

                    /*
                     * The temperature curve.
                     *
                     * One Canvas across the whole strip rather than a segment
                     * per delegate: a shared canvas is the only way the line
                     * between two hours can be drawn at all, and it means the
                     * fill under it is one path instead of 24 abutting
                     * trapezoids with seams between them.
                     */
                    Canvas {
                        id: curve
                        anchors.fill: parent
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const n = hourlyWeatherModel.count
                            if (n < 2) return

                            let lo = 1e9, hi = -1e9
                            for (let i = 0; i < n; i++) {
                                const v = hourlyWeatherModel.get(i).t
                                if (v < lo) lo = v
                                if (v > hi) hi = v
                            }
                            if (hi - lo < 1) hi = lo + 1

                            const sw = hourStrip.slotW
                            const top = hourStrip.curveTop
                            const ch  = hourStrip.curveH
                            const xy = i => ({
                                x: sw * (i + 0.5),
                                y: top + ch - ((hourlyWeatherModel.get(i).t - lo) / (hi - lo)) * ch
                            })

                            // Area under the line, fading out downwards, so the
                            // curve has body without a hard block of colour.
                            const g = ctx.createLinearGradient(0, top, 0, top + ch * 1.6)
                            g.addColorStop(0, Qt.rgba(0.29, 0.62, 1.0, 0.30))
                            g.addColorStop(1, Qt.rgba(0.29, 0.62, 1.0, 0.0))
                            ctx.fillStyle = g
                            ctx.beginPath()
                            ctx.moveTo(xy(0).x, top + ch * 1.6)
                            for (let i = 0; i < n; i++) { const p = xy(i); ctx.lineTo(p.x, p.y) }
                            ctx.lineTo(xy(n - 1).x, top + ch * 1.6)
                            ctx.closePath()
                            ctx.fill()

                            ctx.strokeStyle = Theme.accentCyan
                            ctx.lineWidth = Math.max(2, root.height * 0.004)
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            ctx.beginPath()
                            for (let i = 0; i < n; i++) {
                                const p = xy(i)
                                if (i === 0) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y)
                            }
                            ctx.stroke()

                            // Marker on the hour the reading is for.
                            if (root.currentHour >= 0 && root.currentHour < n) {
                                const p = xy(root.currentHour)
                                ctx.fillStyle = Theme.textPrimary
                                ctx.beginPath()
                                ctx.arc(p.x, p.y, Math.max(3, root.height * 0.0075), 0, Math.PI * 2)
                                ctx.fill()
                            }
                        }
                    }

                    Row {
                        Repeater {
                            model: hourlyWeatherModel

                            delegate: Item {
                                id: hourSlot
                                required property string time
                                required property string temp
                                required property int    index
                                readonly property bool isCurrent: index === root.currentHour

                                width: hourStrip.slotW
                                height: hourStrip.height

                                // The current hour gets a lit column behind it
                                // instead of a differently coloured tile — the
                                // curve has to stay readable across it.
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.72
                                    height: parent.height
                                    radius: Theme.chipRadius
                                    visible: hourSlot.isCurrent
                                    color: Theme.tint(Theme.accentCyan, 0.14)
                                    border.width: 1
                                    border.color: Theme.tint(Theme.accentCyan, 0.45)
                                }

                                Text {
                                    anchors {
                                        top: parent.top
                                        horizontalCenter: parent.horizontalCenter
                                    }
                                    text: hourSlot.time
                                    color: hourSlot.isCurrent ? Theme.textPrimary : Theme.textMuted
                                    font { family: "Arial"
                                           bold: hourSlot.isCurrent
                                           pixelSize: root.height * 0.022 }
                                }

                                Text {
                                    anchors {
                                        bottom: parent.bottom
                                        horizontalCenter: parent.horizontalCenter
                                    }
                                    text: hourSlot.temp
                                    color: hourSlot.isCurrent ? Theme.textPrimary : Theme.textSecondary
                                    font { family: "Arial"; bold: true
                                           pixelSize: root.height * 0.028 }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ==================================================== ROW B
    Item {
        id: rowB
        anchors {
            left: parent.left;   leftMargin:  root.gutter
            right: parent.right; rightMargin: root.gutter
            top: rowA.bottom;    topMargin:   root.rowGap
        }
        height: root.rowBH

        // ---- 7 DAYS
        GlassCard {
            id: dailyCard
            width: root.innerW * 0.455
            height: parent.height
            accent: Theme.accentBlue
            interactive: false

            Text {
                id: dailyTitle
                anchors {
                    left: parent.left; leftMargin: dailyCard.width * 0.055
                    top: parent.top;   topMargin:  dailyCard.height * 0.055
                }
                text: qsTr("7-DAY OUTLOOK")
                color: Theme.textMuted
                font { bold: true; family: "Arial"
                       pixelSize: root.height * 0.021; letterSpacing: 1.2 }
            }

            Column {
                anchors {
                    left: parent.left;     leftMargin:   dailyCard.width * 0.055
                    right: parent.right;   rightMargin:  dailyCard.width * 0.055
                    top: dailyTitle.bottom; topMargin:   dailyCard.height * 0.035
                    bottom: parent.bottom; bottomMargin: dailyCard.height * 0.05
                }

                Repeater {
                    model: dailyWeatherModel

                    delegate: Item {
                        id: dayRow
                        required property string day
                        required property string maxTemp
                        required property string minTemp
                        required property real   tmax
                        required property real   tmin
                        required property var    uvIndex

                        width: parent.width
                        height: (dailyCard.height * 0.86 - dailyTitle.height)
                                / dailyWeatherModel.count

                        Text {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: parent.width * 0.30
                            text: dayRow.day
                            color: Theme.textPrimary
                            font { family: "Arial"; bold: true
                                   pixelSize: root.height * 0.025 }
                            elide: Text.ElideRight
                        }

                        // UV as a dot plus its number: the colour carries the
                        // severity at a glance, the figure is there when it
                        // matters. The old version put an emoji here.
                        Row {
                            anchors {
                                left: parent.left; leftMargin: parent.width * 0.31
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: parent.width * 0.022

                            Rectangle {
                                width: root.height * 0.016; height: width
                                radius: width / 2
                                color: root.uvColor(dayRow.uvIndex)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: dayRow.uvIndex.toFixed(1)
                                color: Theme.textSecondary
                                font { family: "Arial"; pixelSize: root.height * 0.022 }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        /*
                         * Range bar, on the week's scale rather than the row's.
                         * A warm day is a bar sitting to the right; a cold one
                         * sits left. That comparison is the entire reason to
                         * show seven days at once, and a column of "32° / 20°"
                         * does not give it to you.
                         */
                        Rectangle {
                            id: track
                            anchors {
                                left: parent.left; leftMargin: parent.width * 0.46
                                verticalCenter: parent.verticalCenter
                            }
                            width: parent.width * 0.28
                            height: root.height * 0.008
                            radius: height / 2
                            color: Theme.surfaceSunk

                            Rectangle {
                                readonly property real lo: root.span.lo
                                readonly property real hi: root.span.hi
                                x: track.width * (dayRow.tmin - lo) / (hi - lo)
                                width: Math.max(track.height,
                                                track.width * (dayRow.tmax - dayRow.tmin) / (hi - lo))
                                height: parent.height
                                radius: height / 2
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Theme.accentCyan }
                                    GradientStop { position: 1.0; color: Theme.accentAmber }
                                }
                            }
                        }

                        Text {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: dayRow.maxTemp + "  " + dayRow.minTemp
                            color: Theme.textSecondary
                            font { family: "Arial"; pixelSize: root.height * 0.023 }
                        }
                    }
                }
            }
        }

        // ---- DETAILS 2×2
        Grid {
            id: metrics
            anchors.right: parent.right
            width: root.innerW - dailyCard.width - root.colGap
            height: parent.height
            columns: 2
            rowSpacing: root.rowGap
            columnSpacing: root.colGap

            Repeater {
                model: weatherInfoModel

                delegate: GlassCard {
                    id: metricCard
                    required property string label
                    required property string glyph
                    required property string value
                    required property int    index

                    width: (metrics.width - metrics.columnSpacing) / 2
                    height: (metrics.height - metrics.rowSpacing) / 2
                    interactive: false
                    accent: [Theme.accentCyan, Theme.accentBlue,
                             Theme.accentViolet, Theme.accentAmber][index]

                    Row {
                        anchors.centerIn: parent
                        spacing: metricCard.width * 0.075

                        // Same seat the settings cards give their icons, with a
                        // drawn glyph in it instead of a PNG.
                        Rectangle {
                            width: metricCard.height * 0.45
                            height: width
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.tint(metricCard.accent, 0.15)
                            border.color: Theme.tint(metricCard.accent, 0.5)
                            border.width: 1

                            WeatherGlyph {
                                anchors.centerIn: parent
                                width: parent.width * 0.55; height: width
                                kind: metricCard.glyph
                                tint: Theme.textPrimary
                                accent: metricCard.accent
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: metricCard.height * 0.03

                            Text {
                                text: metricCard.label
                                color: Theme.textSecondary
                                font { family: "Arial"; pixelSize: root.height * 0.022 }
                            }
                            Text {
                                text: metricCard.value
                                color: Theme.textPrimary
                                font { family: "Arial"; bold: true
                                       pixelSize: root.height * 0.038 }
                            }
                        }
                    }
                }
            }
        }
    }

    // Hidden TextInput to sync with the keyboard
    TextInput {
        id: cityInputHidden
        visible: false
        text: ""
    }

    // ==================================================== KEYBOARD
    Popup {
        id: keyboardPopup
        width: parent.width * 0.85
        height: parent.height * 0.75
        anchors.centerIn: parent
        modal: true
        Overlay.modal: Rectangle {
            color: Theme.scrim
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        // Nearly opaque, like the other dialogs: a see-through modal over a
        // moving backdrop is unreadable whatever it costs in prettiness.
        background: Rectangle {
            color: Theme.surface
            radius: Theme.dialogRadius
            border.color: Theme.glassBorder
            border.width: 1
        }

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Text {
                text: qsTr("Search City")
                color: Theme.textPrimary
                font { bold: true; family: "Arial"; pixelSize: root.height * 0.038 }
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: qsTr("Enter a city name")
                color: Theme.textSecondary
                font { family: "Arial"; pixelSize: root.height * 0.024 }
                anchors.horizontalCenter: parent.horizontalCenter
            }

            VirtualKeyboard {
                id: keyboard
                width: parent.width
                targetItem: cityInputHidden
                passwordMode: false
                maxLength: 32

                onAccepted: {
                    root.showCity(cityInputHidden.text)
                    keyboard.clear()
                    keyboardPopup.close()
                }

                onCancelled: {
                    keyboard.clear()
                    keyboardPopup.close()
                }
            }
        }

        onOpened: keyboard.targetText = cityInputHidden.text
    }

    // ==================================================== DATA
    /*
     * Painting is a plain function rather than only a signal handler, because
     * the page has to be able to fill itself in from cache the instant it is
     * constructed — the same code has to run for a reply that has just landed
     * and for one that landed ten minutes ago.
     */
    function applyWeather(current, daily, hourly, location) {
        root.statusNote      = ""
        cityName.text        = location.name + ", " + location.country
        temperature.text     = Math.round(current.temperature_2m) + "°C"
        feelsLike.text       = qsTr("Feels like ") + Math.round(current.apparent_temperature) + "°C"
        root.conditionKind   = root.weatherKind(current.weather_code, current.is_day)
        populationValue.text = location.population.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")
        root.currentHour     = parseInt(current.time.split("T")[1].split(":")[0])

        const code = current.weather_code
        if      (code === 0)  weatherDescription.text = current.is_day ? qsTr("Clear Sky") : qsTr("Clear Night")
        else if (code <= 2)   weatherDescription.text = qsTr("Partly Cloudy")
        else if (code === 3)  weatherDescription.text = qsTr("Overcast")
        else if (code <= 48)  weatherDescription.text = qsTr("Foggy")
        else if (code <= 55)  weatherDescription.text = qsTr("Drizzle")
        else if (code <= 65)  weatherDescription.text = qsTr("Rainy")
        else if (code <= 75)  weatherDescription.text = qsTr("Snowy")
        else if (code <= 82)  weatherDescription.text = qsTr("Rain Showers")
        else if (code <= 99)  weatherDescription.text = qsTr("Thunderstorm")

        weatherInfoModel.setProperty(0, "value", Math.round(current.wind_speed_10m)   + " km/h")
        weatherInfoModel.setProperty(1, "value", current.relative_humidity_2m         + "%")
        weatherInfoModel.setProperty(2, "value", current.wind_direction_10m           + "°")
        weatherInfoModel.setProperty(3, "value", Math.round(current.surface_pressure) + " hPa")

        hourlyWeatherModel.clear()
        for (let i = 0; i < 24; i++) {
            const amPm = i < 12 ? "AM" : "PM"
            const hour = i % 12 === 0 ? "12" : (i % 12).toString()
            const v = Math.round(hourly.temperature_2m[i])
            hourlyWeatherModel.append({ "time": hour + " " + amPm, "temp": v + "°C", "t": v })
        }

        const dayNames = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
        dailyWeatherModel.clear()
        for (let j = 0; j < daily.time.length; j++) {
            const date = new Date(daily.time[j])
            const hiT = Math.round(daily.temperature_2m_max[j])
            const loT = Math.round(daily.temperature_2m_min[j])
            dailyWeatherModel.append({
                "day":     j === 0 ? qsTr("Today") : j === 1 ? qsTr("Tomorrow") : dayNames[date.getDay()],
                "maxTemp": hiT + "°",
                "minTemp": loT + "°",
                "tmax":    hiT,
                "tmin":    loT,
                "uvIndex": daily.uv_index_max[j]
            })
        }

        // Both derived from the models, so they are refreshed here rather than
        // bound — a binding on a ListModel's contents does not re-evaluate when
        // rows are appended.
        root.span = root.weekSpan()
        curve.requestPaint()
    }

    /*
     * The city this page is currently displaying.
     *
     * Not the same thing as `city`, which is bound to the launcher's preferred
     * city: typing somewhere into the search box has to move the page without
     * moving the home screen. Kept as its own property so replies can be
     * matched against what is actually on screen.
     */
    property string shownCity: ""

    /* Paint from cache. Returns false when there is nothing cached yet. */
    function showCached(name) {
        const e = WeatherStore.entryFor(name)
        if (e === null)
            return false
        applyWeather(e.current, e.daily, e.hourly, e.location)
        return true
    }

    /* Point the page at a city: cache first so it is instant, then revalidate. */
    function showCity(name, force) {
        if (name === "")
            return
        root.shownCity = name
        cityInputHidden.text = name
        showCached(name)
        WeatherStore.request(name, force === true)
    }

    Connections {
        target: WeatherStore

        // Only react to the city this page is showing. The launcher refreshes
        // the preferred city on its own schedule, and without this guard that
        // reply would redraw the page out from under a search.
        function onUpdated(city) {
            if (WeatherStore.normalise(city) === WeatherStore.normalise(root.shownCity))
                root.showCached(city)
        }
        function onNotFound(city) {
            root.statusNote = qsTr("No city called “") + city + qsTr("”")
        }

        /*
         * No handler for failed().
         *
         * "Could not reach the weather service" told the driver about a
         * condition they cannot act on, in place of the page's own content, and
         * WeatherAPI is already retrying with backoff underneath — so the note
         * outlived the problem it described. The page keeps showing the last
         * reading and fills in when a reply lands.
         *
         * notFound() stays: an unresolvable city name never fixes itself, and
         * the search box that produced it is on this page.
         */
    }

    onCityChanged: root.showCity(root.city)

    /*
     * The point of the cache: on re-entry this paints the page from memory
     * before the first frame is drawn, and request() then does nothing at all
     * unless the reading has aged past the store's TTL. Entering, leaving and
     * entering again no longer costs a geocode + forecast pair every time.
     */
    Component.onCompleted: {
        root.span = root.weekSpan()
        root.showCity(root.city)
    }
}
