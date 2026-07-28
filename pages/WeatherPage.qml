import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Qt5Compat.GraphicalEffects

pragma ComponentBehavior: Bound

Item {
    id: root

    signal goBack()
    property int currentHour: 2
    property string city: "Giza"

    // BACKGROUND — autumn dark navy
    Rectangle {
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
                ctx.fillStyle = "#dd9c4d"
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

    // Dark overlay for readability
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.1
    }

    WindowBar {
        id: titleBar
        z: 1
        window: mainWindow
        titleName: "Weather"
        showBackButton: true
        onBackRequested: root.goBack()
        color0: '#082839'
        color1: '#10475E'
        color2: '#3D717E'

        brightnessValue: mainWindow.appBrightness
        volumeValue: systemVolume.volume
        volumeMax: systemVolume.maxVolume
        volumeMuted: systemVolume.muted
        
        onBrightnessChanged: (value) => mainWindow.appBrightness = value
        onVolumeChanged: (value) => systemVolume.volume = value
        onVolumeMuteToggled: systemVolume.toggleMute()
    }

    // Weather helper
    function weatherEmoji(code, isDay) {
        if (code === 0)  return isDay ? "☀️"  : "🌙"
        if (code <= 2)   return isDay ? "🌤️" : "🌙"
        if (code === 3)  return "☁️"
        if (code <= 48)  return "🌫️"
        if (code <= 55)  return "🌦️"
        if (code <= 57)  return "🌧️"
        if (code <= 65)  return "🌧️"
        if (code <= 67)  return "🌨️"
        if (code <= 75)  return "❄️"
        if (code <= 77)  return "🌨️"
        if (code <= 82)  return "🌦️"
        if (code <= 86)  return "❄️"
        if (code <= 99)  return "⛈️"
        return "🌡️"
    }

    // Models
    ListModel {
        id: weatherInfoModel
        ListElement { label: "Wind Speed";     emoji: "💨"; value: "12 km/h"  }
        ListElement { label: "Humidity";       emoji: "💧"; value: "65%"      }
        ListElement { label: "Wind Direction"; emoji: "🧭"; value: "270°"     }
        ListElement { label: "Pressure";       emoji: "🔵"; value: "1013 hPa" }
    }
    ListModel {
        id: hourlyWeatherModel
        ListElement { time: "12 AM"; temp: "19°C" } ListElement { time: "1 AM";  temp: "18°C" }
        ListElement { time: "2 AM";  temp: "18°C" } ListElement { time: "3 AM";  temp: "17°C" }
        ListElement { time: "4 AM";  temp: "17°C" } ListElement { time: "5 AM";  temp: "17°C" }
        ListElement { time: "6 AM";  temp: "18°C" } ListElement { time: "7 AM";  temp: "19°C" }
        ListElement { time: "8 AM";  temp: "21°C" } ListElement { time: "9 AM";  temp: "23°C" }
        ListElement { time: "10 AM"; temp: "25°C" } ListElement { time: "11 AM"; temp: "27°C" }
        ListElement { time: "12 PM"; temp: "29°C" } ListElement { time: "1 PM";  temp: "30°C" }
        ListElement { time: "2 PM";  temp: "31°C" } ListElement { time: "3 PM";  temp: "31°C" }
        ListElement { time: "4 PM";  temp: "30°C" } ListElement { time: "5 PM";  temp: "28°C" }
        ListElement { time: "6 PM";  temp: "26°C" } ListElement { time: "7 PM";  temp: "24°C" }
        ListElement { time: "8 PM";  temp: "23°C" } ListElement { time: "9 PM";  temp: "22°C" }
        ListElement { time: "10 PM"; temp: "21°C" } ListElement { time: "11 PM"; temp: "20°C" }
    }
    ListModel {
        id: dailyWeatherModel
        ListElement { day: "Today";     uvIndex: 2.1; maxTemp: "26°C"; minTemp: "15°C" }
        ListElement { day: "Tomorrow";  uvIndex: 2.5; maxTemp: "27°C"; minTemp: "17°C" }
        ListElement { day: "Tuesday";   uvIndex: 4.0; maxTemp: "28°C"; minTemp: "17°C" }
        ListElement { day: "Wednesday"; uvIndex: 4.6; maxTemp: "27°C"; minTemp: "17°C" }
        ListElement { day: "Thursday";  uvIndex: 5.9; maxTemp: "29°C"; minTemp: "18°C" }
        ListElement { day: "Friday";    uvIndex: 7.1; maxTemp: "32°C"; minTemp: "20°C" }
        ListElement { day: "Saturday";  uvIndex: 8.5; maxTemp: "33°C"; minTemp: "21°C" }
    }

    // Refresh button — autumn styled
    Rectangle {
        id: refreshBtn
        width: root.height * 0.065
        height: root.height * 0.065
        color: "#3D717E"
        anchors { left: parent.left; leftMargin: root.width * 0.045; top: titleBar.bottom; topMargin: root.height * 0.028 }
        radius: width / 2
        border.color: "#dd9c4d"; border.width: 1
        opacity: 0.9
        z: 5
        Behavior on scale   { NumberAnimation { duration: 120 } }
        Behavior on opacity { NumberAnimation { duration: 120 } }
        
        Image{
            anchors.centerIn: parent
            width: 18; height: 18
            fillMode: Image.PreserveAspectFit
            source: "qrc:/assets/icons/reload.png"
        }

        MouseArea {
            anchors.fill: parent; hoverEnabled: true
            onEntered:  refreshBtn.opacity = 1.0
            onExited:   refreshBtn.opacity = 0.9
            onPressed:  refreshBtn.scale   = 0.88
            onReleased: { refreshBtn.scale = 1.0; weatherAPI.fetch(cityInputHidden.text) }
        }
    }

    // Main Content
    Column {
        id: mainContent
        width: parent.width
        anchors { top: titleBar.bottom; topMargin: root.height * 0.028; horizontalCenter: parent.horizontalCenter }
        spacing: root.height * 0.028

        // Search field — glass style (read-only, opens keyboard popup)
        Rectangle {
            id: cityInputContainer
            width: root.width * 0.3
            height: root.height * 0.055
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#082839"
            radius: root.height * 0.027
            border.color: cityInputMouse.containsMouse ? "#dd9c4d" : "#3D717E"
            border.width: cityInputMouse.containsMouse ? 2 : 1
            opacity: 0.85

            Text {
                id: cityInputDisplay
                anchors.fill: parent
                anchors.leftMargin: root.width * 0.012
                anchors.rightMargin: root.width * 0.012
                verticalAlignment: Text.AlignVCenter
                font { pointSize: root.height * 0.016; family: "Arial" }
                color: "white"
                text: cityInputHidden.text
                elide: Text.ElideRight
            }

            Text {
                id: cityPlaceholder
                anchors.fill: parent
                anchors.leftMargin: root.width * 0.012
                verticalAlignment: Text.AlignVCenter
                text: "🔍 Enter city name..."
                color: '#dd9c4d'
                font { pointSize: root.height * 0.016; family: "Arial" }
                visible: cityInputHidden.text === ""
            }

            MouseArea {
                id: cityInputMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: keyboardPopup.open()
                onEntered: cityInputContainer.scale = 1.05
                onExited: cityInputContainer.scale = 1.0
            }

            Behavior on scale { NumberAnimation { duration: 120 } }
        }

        // Main info banner — GLASS MORPHISM
        Item {
            id: mainInfoContainer
            width: root.width * 0.8; height: root.height * 0.13
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
                id: mainInfoGlass
                anchors.fill: parent
                radius: root.height * 0.025
                color: "#3D717E"
                border.width: 1
                border.color: "#50FFFFFF"
                visible: false
            }

            InnerShadow {
                id: mainInfoInner
                anchors.fill: mainInfoGlass
                source: mainInfoGlass
                horizontalOffset: -3
                verticalOffset: -3
                radius: 10
                samples: 20
                color: "#80FFFFFF"
                visible: false
            }

            DropShadow {
                anchors.fill: mainInfoGlass
                source: mainInfoInner
                horizontalOffset: 6
                verticalOffset: 6
                radius: 14
                samples: 28
                color: "#50000000"
            }

            // Content on top
            Row {
                anchors.centerIn: parent
                spacing: root.width * 0.015
                Text { id: weatherEmojiText; text: "🌤️"; font.pointSize: root.height * 0.065; anchors.verticalCenter: parent.verticalCenter }
                Rectangle { width: 1; height: root.height * 0.09; color: "#dd9c4d"; opacity: 0.5; anchors.verticalCenter: parent.verticalCenter }
                Column {
                    spacing: root.height * 0.005; anchors.verticalCenter: parent.verticalCenter
                    Text { id: weatherDescription; text: "Partly Cloudy"; color: "white"; font { pointSize: root.height * 0.020; family: "Arial" } }
                    Text { id: temperature;        text: "21°C";          color: "#dd9c4d"; font { pointSize: root.height * 0.040; family: "Arial"; bold: true } }
                }
                Item { width: root.width * 0.2; height: 1 }
                Column {
                    spacing: root.height * 0.014; anchors.verticalCenter: parent.verticalCenter
                    Text { id: cityName;   text: "Cairo, Egypt"; color: "white"; font { pointSize: root.height * 0.026; family: "Arial"; bold: true } }
                    Text { id: feelsLike;  text: "Feels like: 19°C"; color: "#dd9c4d"; font { pointSize: root.height * 0.02; family: "Arial" } }
                }
                Rectangle { width: 1; height: root.height * 0.09; color: "#dd9c4d"; opacity: 0.5; anchors.verticalCenter: parent.verticalCenter }
                Column {
                    spacing: root.height * 0.014; anchors.verticalCenter: parent.verticalCenter
                    Text { text: "Population"; color: "white"; font { pointSize: root.height * 0.02; family: "Arial"; bold: true } }
                    Text { id: populationValue; text: "137,844"; color: "#dd9c4d"; font { pointSize: root.height * 0.018; family: "Arial" } }
                }
            }

            Behavior on scale   { NumberAnimation { duration: 120 } }
            Behavior on opacity { NumberAnimation { duration: 120 } }
            MouseArea {
                anchors.fill: parent; hoverEnabled: true
                onEntered: { mainInfoContainer.scale = 1.01; mainInfoContainer.opacity = 1.0 }
                onExited:  { mainInfoContainer.scale = 1.0;  mainInfoContainer.opacity = 0.9 }
            }
        }

        // Hourly forecast — GLASS MORPHISM
        Item {
            id: hourlyContainer
            width: root.width * 0.8; height: root.height * 0.18
            anchors.horizontalCenter: parent.horizontalCenter
            clip: true

            Rectangle {
                id: hourlyGlass
                anchors.fill: parent
                radius: root.height * 0.025
                color: "#3D717E"
                border.width: 1
                border.color: "#50FFFFFF"
                visible: false
            }

            InnerShadow {
                id: hourlyInner
                anchors.fill: hourlyGlass
                source: hourlyGlass
                horizontalOffset: -3
                verticalOffset: -3
                radius: 10
                samples: 20
                color: "#80FFFFFF"
                visible: false
            }

            DropShadow {
                anchors.fill: hourlyGlass
                source: hourlyInner
                horizontalOffset: 6
                verticalOffset: 6
                radius: 14
                samples: 28
                color: "#50000000"
            }

            Flickable {
                anchors { fill: parent; margins: root.height * 0.02 }
                contentWidth: hourlyRow.width
                flickableDirection: Flickable.HorizontalFlick
                clip: true
                Row {
                    id: hourlyRow
                    spacing: root.width * 0.02
                    height: parent.height
                    Repeater {
                        model: hourlyWeatherModel
                        delegate: Rectangle {
                            id: hourlyDelegate
                            required property string time
                            required property string temp
                            required property int    index
                            property bool isCurrent: index === root.currentHour
                            width: root.width * 0.08; height: hourlyRow.height
                            color: hourlyDelegate.isCurrent ? "#dd9c4d" : "#5A3211"
                            radius: root.height * 0.01
                            opacity: hourlyDelegate.isCurrent ? 1.0 : 0.8
                            border.color: hourlyDelegate.isCurrent ? "#FFFFFF" : "#dd9c4d"
                            border.width: hourlyDelegate.isCurrent ? 2 : 1
                            Behavior on scale   { NumberAnimation { duration: 120 } }
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            Column {
                                anchors.horizontalCenter: parent.horizontalCenter
                                topPadding: parent.height * 0.1
                                spacing: root.height * 0.005
                                Text { 
                                    text: hourlyDelegate.time; color: hourlyDelegate.isCurrent ? "#082839" : "#FFFFFF"
                                    font { pointSize: root.height * 0.02; family: "Arial" }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Rectangle { width: parent.width * 0.8; height: 1; color: hourlyDelegate.isCurrent ? "#082839" : "#dd9c4d"; radius: width / 2; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { 
                                    text: hourlyDelegate.temp; 
                                    color: hourlyDelegate.isCurrent ? "#082839" : "#dd9c4d"; 
                                    font { 
                                        pointSize: root.height * 0.035; 
                                        bold: true; 
                                        family: "Arial" 
                                    } 
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true
                                onEntered: { hourlyDelegate.scale = 1.01; hourlyDelegate.opacity = 1.0; hourlyDelegate.border.width = 2 }
                                onExited:  { hourlyDelegate.scale = 1.0;  hourlyDelegate.opacity = 0.8; hourlyDelegate.border.width = hourlyDelegate.isCurrent ? 2 : 1 }
                            }
                        }
                    }
                }
            }
        }

        // Weekly + Details row
        Row {
            spacing: root.width * 0.024
            anchors.horizontalCenter: parent.horizontalCenter

            // Weekly — GLASS MORPHISM
            Item {
                id: weeklyContainer
                width: root.width * 0.4; height: root.height * 0.43

                Rectangle {
                    id: weeklyGlass
                    anchors.fill: parent
                    radius: root.height * 0.025
                    color: "#3D717E"
                    border.width: 1
                    border.color: "#50FFFFFF"
                    visible: false
                }

                InnerShadow {
                    id: weeklyInner
                    anchors.fill: weeklyGlass
                    source: weeklyGlass
                    horizontalOffset: -3
                    verticalOffset: -3
                    radius: 10
                    samples: 20
                    color: "#80FFFFFF"
                    visible: false
                }

                DropShadow {
                    anchors.fill: weeklyGlass
                    source: weeklyInner
                    horizontalOffset: 6
                    verticalOffset: 6
                    radius: 14
                    samples: 28
                    color: "#50000000"
                }

                Column {
                    anchors.centerIn: parent
                    spacing: root.height * 0.015
                    width: weeklyContainer.width - root.height * 0.04
                    Row {
                        width: parent.width
                        Text { text: "Day";      color: "#dd9c4d"; font { pointSize: root.height * 0.018; family: "Arial"; bold: true }
                            width: parent.width * 0.42 }
                        Text { text: "UV";       color: "#dd9c4d"; font { pointSize: root.height * 0.018; family: "Arial"; bold: true }
                            width: parent.width * 0.08; horizontalAlignment: Text.AlignHCenter }
                        Text { text: "Max / Min"; color: "#dd9c4d"; font { pointSize: root.height * 0.018; family: "Arial"; bold: true }
                            width: parent.width * 0.45; horizontalAlignment: Text.AlignRight }
                    }
                    Rectangle { width: parent.width; height: 1; color: "#dd9c4d"; opacity: 0.4 }
                    Repeater {
                        model: dailyWeatherModel
                        delegate: Row {
                            id: dailyRow
                            required property string day
                            required property string maxTemp
                            required property string minTemp
                            required property var    uvIndex
                            width: weeklyContainer.width - root.height * 0.04
                            Text { 
                                text: dailyRow.day; color: "white";
                                font { pointSize: root.height * 0.022; family: "Arial"; bold: true }
                                width: parent.width * 0.44 
                            }
                            Text {
                                text: { var uv = Math.round(dailyRow.uvIndex); return uv<=2?"🌤 "+dailyRow.uvIndex:uv<=5?"☀️ "+dailyRow.uvIndex:uv<=7?"🌞 "+dailyRow.uvIndex:uv<=10?"🔆 "+dailyRow.uvIndex:"🔥 "+dailyRow.uvIndex }
                                color: { var uv = Math.round(dailyRow.uvIndex); return uv<=2?"#a8d8a8":uv<=5?"#f9e07a":uv<=7?"#f4a445":uv<=10?"#e05a5a":"#c060c0" }
                                font { pointSize: root.height * 0.020; family: "Arial"; bold: true }
                                width: parent.width * 0.1
                            }
                            Text { text: dailyRow.maxTemp + " / " + dailyRow.minTemp; color: "#dd9c4d"; font { pointSize: root.height * 0.020; family: "Arial" }
                                horizontalAlignment: Text.AlignRight; width: parent.width * 0.45 
                            }
                        }
                    }
                }

                Behavior on scale   { NumberAnimation { duration: 120 } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onEntered: { weeklyContainer.scale = 1.05; weeklyContainer.opacity = 1.0 }
                    onExited:  { weeklyContainer.scale = 1.0;  weeklyContainer.opacity = 0.9 }
                }
            }

            Rectangle { width: 1; height: weeklyContainer.height; color: "#dd9c4d"; opacity: 0.4 }

            // Info grid — GLASS MORPHISM
            Grid {
                columns: 2
                width: root.width * 0.35; height: root.height * 0.43
                rowSpacing: root.height * 0.02; columnSpacing: root.width * 0.02
                Repeater {
                    model: weatherInfoModel
                    delegate: Item {
                        id: infoDelegate
                        required property var modelData
                        width: (root.width * 0.35 - root.width * 0.02) / 2
                        height: (root.height * 0.43 - root.height * 0.02) / 2

                        Rectangle {
                            id: infoGlass
                            anchors.fill: parent
                            radius: root.height * 0.015
                            color: "#3D717E"
                            border.width: 1
                            border.color: "#50FFFFFF"
                            visible: false
                        }

                        InnerShadow {
                            id: infoInner
                            anchors.fill: infoGlass
                            source: infoGlass
                            horizontalOffset: -2
                            verticalOffset: -2
                            radius: 8
                            samples: 16
                            color: "#80FFFFFF"
                            visible: false
                        }

                        DropShadow {
                            anchors.fill: infoGlass
                            source: infoInner
                            horizontalOffset: 4
                            verticalOffset: 4
                            radius: 10
                            samples: 20
                            color: "#50000000"
                        }

                        Column {
                            anchors.centerIn: parent; spacing: root.height * 0.009
                            Text { text: infoDelegate.modelData.emoji; font.pointSize: root.height * 0.035; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: infoDelegate.modelData.label; color: "#FFFFFF"; font { pointSize: root.height * 0.02; family: "Arial" }
                                anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: infoDelegate.modelData.value; color: "#dd9c4d"; font { pointSize: root.height * 0.028; family: "Arial"; bold: true }
                                anchors.horizontalCenter: parent.horizontalCenter }
                        }

                        Behavior on scale   { NumberAnimation { duration: 120 } }
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            onEntered: { infoDelegate.scale = 1.05; infoDelegate.opacity = 1.0 }
                            onExited:  { infoDelegate.scale = 1.0;  infoDelegate.opacity = 0.9 }
                        }
                    }
                }
            }
        }
    }

    // Hidden TextInput to sync with keyboard
    TextInput {
        id: cityInputHidden
        visible: false
        text: ""
    }

    // Keyboard Popup — uses your existing VirtualKeyboard.qml
    Popup {
        id: keyboardPopup
        width: parent.width * 0.85
        height: parent.height * 0.75
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: "#082839"
            radius: 16
            border.color: "#dd9c4d"
            border.width: 2
        }

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            // Header
            Text {
                text: "Search City"
                font.pixelSize: root.height * 0.04
                color: "#dd9c4d"
                font.bold: true
                font.family: "Arial"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "Enter city name"
                font.pixelSize: root.height * 0.025
                color: "#3D717E"
                font.family: "Arial"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Virtual Keyboard
            VirtualKeyboard {
                id: keyboard
                width: parent.width
                targetItem: cityInputHidden
                passwordMode: false
                maxLength: 32

                onAccepted: {
                    weatherAPI.fetch(cityInputHidden.text)
                    keyboard.clear()
                    keyboardPopup.close()
                }

                onCancelled: {
                    keyboard.clear()
                    keyboardPopup.close()
                }
            }
        }

        onOpened: {
            keyboard.targetText = cityInputHidden.text
        }
    }

    // API
    WeatherAPI {
        id: weatherAPI
        onWeatherReceived: function(current, daily, hourly, location) {
            cityName.text         = location.name + ", " + location.country
            temperature.text      = Math.round(current.temperature_2m) + "°C"
            feelsLike.text        = "Feels like: " + Math.round(current.apparent_temperature) + "°C"
            weatherEmojiText.text = root.weatherEmoji(current.weather_code, current.is_day)
            populationValue.text  = location.population.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")
            root.currentHour      = parseInt(current.time.split("T")[1].split(":")[0])

            var code = current.weather_code
            if      (code === 0)  weatherDescription.text = current.is_day ? "Clear Sky" : "Clear Night"
            else if (code <= 2)   weatherDescription.text = "Partly Cloudy"
            else if (code === 3)  weatherDescription.text = "Overcast"
            else if (code <= 48)  weatherDescription.text = "Foggy"
            else if (code <= 55)  weatherDescription.text = "Drizzle"
            else if (code <= 65)  weatherDescription.text = "Rainy"
            else if (code <= 75)  weatherDescription.text = "Snowy"
            else if (code <= 82)  weatherDescription.text = "Rain Showers"
            else if (code <= 99)  weatherDescription.text = "Thunderstorm"

            weatherInfoModel.setProperty(0, "value", Math.round(current.wind_speed_10m)   + " km/h")
            weatherInfoModel.setProperty(1, "value", current.relative_humidity_2m         + "%")
            weatherInfoModel.setProperty(2, "value", current.wind_direction_10m           + "°")
            weatherInfoModel.setProperty(3, "value", Math.round(current.surface_pressure) + " hPa")

            hourlyWeatherModel.clear()
            for (var i = 0; i < 24; i++) {
                var amPm = i < 12 ? "AM" : "PM"
                var hour = i % 12 === 0 ? "12" : (i % 12).toString()
                hourlyWeatherModel.append({ "time": hour + " " + amPm, "temp": Math.round(hourly.temperature_2m[i]) + "°C" })
            }
            var dayNames = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
            dailyWeatherModel.clear()
            for (var j = 0; j < daily.time.length; j++) {
                var date = new Date(daily.time[j])
                dailyWeatherModel.append({
                    "day":     j === 0 ? "Today" : j === 1 ? "Tomorrow" : dayNames[date.getDay()],
                    "maxTemp": Math.round(daily.temperature_2m_max[j]) + "°C",
                    "minTemp": Math.round(daily.temperature_2m_min[j]) + "°C",
                    "uvIndex": daily.uv_index_max[j]
                })
            }
        }
        onCityNotFound:  function(city)    { cityInputHidden.text = ""; cityPlaceholder.visible = true }
        onNetworkError:  function(message) { cityInputHidden.text = ""; cityPlaceholder.visible = true }
    }

    // Auto-fetch when page loads or city changes
    onCityChanged: {
        if(city !== "" && weatherAPI) {
            weatherAPI.fetch(city)
            cityInputHidden.text = city
        }
    }
    
    Component.onCompleted: {
        if(root.city !== "") {
            cityInputHidden.text = root.city
            weatherAPI.fetch(root.city)
        }
    }
}