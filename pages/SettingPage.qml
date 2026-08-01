import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
pragma ComponentBehavior: Bound

Item {
    id: root
    signal goBack()
    property real fontSize: (width + height) / 60
    property string preferredCity
    property color accentColor: "#D08831"

    // Cards are sized from how many there are rather than a fixed fraction of
    // the width. Five at the old root.width/5.5 overflowed the screen; deriving
    // it means the next one added cannot silently do that again.
    readonly property int  cardCount:   5
    readonly property real cardSpacing: root.width / 28
    readonly property real cardWidth:
        (root.width * 0.88 - cardSpacing * (cardCount - 1)) / cardCount

    /*
     * Jump straight to one sub-page.
     *
     * Set as an initial property when the page is pushed from elsewhere (the
     * status icons in the window bar), or called directly when Settings is
     * already on screen. Either way it starts from the settings menu, so
     * tapping the same icon twice does not stack duplicates.
     */
    property string pendingSection: ""

    function showSection(section) {
        stackView.pop(null)
        if (section === "wifi")
            stackView.push(wifiPageComponent)
        else if (section === "bluetooth")
            stackView.push(bluetoothPageComponent)
        else if (section === "ambient")
            stackView.push(ambientPageComponent)
    }

    Component.onCompleted: {
        if (pendingSection !== "")
            showSection(pendingSection)
    }

    WindowBar {
        id: titleBar
        z: 2
        window: mainWindow
        titleName: "Settings"
        showBackButton: true
        onBackRequested: root.goBack()
        color0: '#082839'
        color1: '#10475E'
        color2: '#3D717E'

        // Bind to your existing global properties
        brightnessValue: mainWindow.appBrightness
        volumeValue: systemVolume.volume
        volumeMax: systemVolume.maxVolume
        volumeMuted: systemVolume.muted

        onBrightnessChanged: (value) => mainWindow.appBrightness = value
        onVolumeChanged: (value) => systemVolume.volume = value
        onVolumeMuteToggled: systemVolume.toggleMute()

        onWifiRequested:      root.showSection("wifi")
        onBluetoothRequested: root.showSection("bluetooth")
    }

    // BACKGROUND — autumn dark navy
    Rectangle {
        id: background
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

        StackView {
            id: stackView
            anchors.fill: parent
            initialItem: mainPageComponent

            Component {
                id: mainPageComponent
                Item {
                    id: app
                    anchors.top: parent.top
                    anchors.topMargin: parent.height * 0.3

                    Row {
                        id: cardRow
                        spacing: root.cardSpacing
                        anchors.horizontalCenter: parent.horizontalCenter

                        // WI-FI CARD — glass morphism
                        Item {
                            id: wifiCard
                            width: root.cardWidth
                            height: root.height / 2.5

                            Rectangle {
                                id: wifiGlass
                                anchors.fill: parent
                                radius: height * 0.06
                                color: "#3D717E"
                                border.width: 1
                                border.color: "#50FFFFFF"
                                visible: false
                            }

                            InnerShadow {
                                id: wifiInner
                                anchors.fill: wifiGlass
                                source: wifiGlass
                                horizontalOffset: -3
                                verticalOffset: -3
                                radius: 10
                                samples: 20
                                color: "#80FFFFFF"
                                visible: false
                            }

                            DropShadow {
                                anchors.fill: wifiGlass
                                source: wifiInner
                                horizontalOffset: 6
                                verticalOffset: 6
                                radius: 14
                                samples: 28
                                color: "#50000000"
                            }

                            // Glow on hover
                            Rectangle {
                                anchors.fill: parent
                                radius: height * 0.06
                                color: "transparent"
                                border.color: root.accentColor
                                border.width: 2
                                opacity: wifiHover.hovered ? 0.55 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }

                            // Top Accent Bar
                            Rectangle {
                                width: parent.width * 0.4
                                height: 3
                                radius: 2
                                color: root.accentColor
                                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                                opacity: 0.85
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: parent.height * 0.06

                                Rectangle {
                                    width: parent.parent.height * 0.32
                                    height: width
                                    radius: width / 2
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15)
                                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.5)
                                    border.width: 1
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Image {
                                        source: "qrc:/assets/icons/wifi.png"
                                        anchors.centerIn: parent
                                        width: parent.width * 0.55
                                        height: parent.height * 0.55
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }

                                Text {
                                    text: qsTr("Wi-Fi")
                                    color: "#ffffff"
                                    font { bold: true; family: "Arial"; pixelSize: root.fontSize }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: qsTr("Manage connections")
                                    color: "#8899bb"
                                    font { family: "Arial"; pixelSize: root.fontSize * 0.55 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }

                            scale: wifiHover.hovered ? 1.03 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                            HoverHandler { id: wifiHover }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: stackView.push(wifiPageComponent)
                            }
                        }

                        // BLUETOOTH CARD — glass morphism
                        Item {
                            id: bluetoothCard
                            width: root.cardWidth
                            height: root.height / 2.5

                            Rectangle {
                                id: btGlass
                                anchors.fill: parent
                                radius: height * 0.06
                                color: "#3D717E"
                                border.width: 1
                                border.color: "#50FFFFFF"
                                visible: false
                            }

                            InnerShadow {
                                id: btInner
                                anchors.fill: btGlass
                                source: btGlass
                                horizontalOffset: -3
                                verticalOffset: -3
                                radius: 10
                                samples: 20
                                color: "#80FFFFFF"
                                visible: false
                            }

                            DropShadow {
                                anchors.fill: btGlass
                                source: btInner
                                horizontalOffset: 6
                                verticalOffset: 6
                                radius: 14
                                samples: 28
                                color: "#50000000"
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: height * 0.06
                                color: "transparent"
                                border.color: root.accentColor
                                border.width: 2
                                opacity: btHover.hovered ? 0.55 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }

                            Rectangle {
                                width: parent.width * 0.4
                                height: 3
                                radius: 2
                                color: root.accentColor
                                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                                opacity: 0.85
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: parent.height * 0.06

                                Rectangle {
                                    width: parent.parent.height * 0.32
                                    height: width
                                    radius: width / 2
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15)
                                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.5)
                                    border.width: 1
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Image {
                                        source: "qrc:/assets/icons/bt.png"
                                        anchors.centerIn: parent
                                        width: parent.width * 0.55
                                        height: parent.height * 0.55
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }

                                Text {
                                    text: qsTr("Bluetooth")
                                    color: "#ffffff"
                                    font { bold: true; family: "Arial"; pixelSize: root.fontSize - 2 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: qsTr("Pair your devices")
                                    color: "#8899bb"
                                    font { family: "Arial"; pixelSize: root.fontSize * 0.6 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }

                            scale: btHover.hovered ? 1.03 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                            HoverHandler { id: btHover }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: stackView.push(bluetoothPageComponent)
                            }
                        }

                        // AMBIENT LIGHT CARD — glass morphism
                        Item {
                            id: ambientCard
                            width: root.cardWidth
                            height: root.height / 2.5

                            Rectangle {
                                id: ambGlass
                                anchors.fill: parent
                                radius: height * 0.06
                                color: "#3D717E"
                                border.width: 1
                                border.color: "#50FFFFFF"
                                visible: false
                            }

                            InnerShadow {
                                id: ambInner
                                anchors.fill: ambGlass
                                source: ambGlass
                                horizontalOffset: -3
                                verticalOffset: -3
                                radius: 10
                                samples: 20
                                color: "#80FFFFFF"
                                visible: false
                            }

                            DropShadow {
                                anchors.fill: ambGlass
                                source: ambInner
                                horizontalOffset: 6
                                verticalOffset: 6
                                radius: 14
                                samples: 28
                                color: "#50000000"
                            }

                            // Glow on hover
                            Rectangle {
                                anchors.fill: parent
                                radius: height * 0.06
                                color: "transparent"
                                border.color: root.accentColor
                                border.width: 2
                                opacity: ambHover.hovered ? 0.55 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }

                            // Top Accent Bar
                            Rectangle {
                                width: parent.width * 0.4
                                height: 3
                                radius: 2
                                color: root.accentColor
                                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                                opacity: 0.85
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: parent.height * 0.1

                                /*
                                 * The current colour itself, rather than an icon.
                                 * There is no ambient-light asset to use, and this
                                 * says more than a glyph would — the card shows what
                                 * the cabin is actually set to.
                                 *
                                 * Ringed and haloed so that "off" reads as an unlit
                                 * lamp rather than as a hole punched in the card.
                                 */
                                Item {
                                    width: parent.parent.height * 0.32
                                    height: width
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 1.45
                                        height: width
                                        radius: width / 2
                                        color: AmbientLight.color
                                        opacity: AmbientLight.on ? 0.22 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 250 } }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: AmbientLight.on ? AmbientLight.color
                                                               : "#2a5a6d"
                                        border.color: AmbientLight.on
                                                      ? Qt.lighter(AmbientLight.color, 1.4)
                                                      : "#4d8298"
                                        border.width: 2
                                        Behavior on color { ColorAnimation { duration: 250 } }
                                    }
                                }

                                Text {
                                    text: qsTr("Ambient Light")
                                    color: "#ffffff"
                                    font { bold: true; family: "Arial"; pixelSize: root.fontSize * 0.7 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: AmbientLight.on ? qsTr("On")
                                                          : qsTr("Cabin lighting")
                                    color: "#8899bb"
                                    font { family: "Arial"; pixelSize: root.fontSize * 0.6 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }

                            scale: ambHover.hovered ? 1.03 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                            HoverHandler { id: ambHover }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: stackView.push(ambientPageComponent)
                            }
                        }

                        // VOLUME CARD — glass morphism
                        Item {
                            id: volumeCard
                            width: root.cardWidth
                            height: root.height / 2.5

                            Rectangle {
                                id: volGlass
                                anchors.fill: parent
                                radius: height * 0.06
                                color: "#3D717E"
                                border.width: 1
                                border.color: "#50FFFFFF"
                                visible: false
                            }

                            InnerShadow {
                                id: volInner
                                anchors.fill: volGlass
                                source: volGlass
                                horizontalOffset: -3
                                verticalOffset: -3
                                radius: 10
                                samples: 20
                                color: "#80FFFFFF"
                                visible: false
                            }

                            DropShadow {
                                anchors.fill: volGlass
                                source: volInner
                                horizontalOffset: 6
                                verticalOffset: 6
                                radius: 14
                                samples: 28
                                color: "#50000000"
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: height * 0.06
                                color: "transparent"
                                border.color: root.accentColor
                                border.width: 2
                                opacity: volumeHover.hovered ? 0.55 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }

                            Rectangle {
                                width: parent.width * 0.4
                                height: 3
                                radius: 2
                                color: root.accentColor
                                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                                opacity: 0.85
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: parent.height * 0.03
                                width: parent.width

                                Rectangle {
                                    width: parent.parent.height * 0.3
                                    height: width
                                    radius: width / 2
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15)
                                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.5)
                                    border.width: 1
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Image {
                                        source: "qrc:/assets/icons/volume.png"
                                        anchors.centerIn: parent
                                        width: parent.width * 0.55
                                        height: parent.height * 0.55
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    color: "transparent"
                                }

                                Item {
                                    width: parent.parent.width * 0.75
                                    height: root.fontSize * 0.8
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Text {
                                        text: qsTr("Volume")
                                        font { pixelSize: root.fontSize * 0.6; bold: true; family: "Arial" }
                                        color: '#ffffff'
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Slider {
                                    id: volumeSlider
                                    width: parent.parent.width * 0.75
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    from: 0
                                    to: systemVolume.maxVolume
                                    stepSize: 1
                                    live: true
                                    value: systemVolume.volume
                                    
                                    onValueChanged: {
                                        if (pressed && systemVolume.volume !== value) {
                                            systemVolume.volume = value
                                        }
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
                                            color: root.accentColor
                                            radius: 3
                                        }
                                    }

                                    handle: Rectangle {
                                        x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                                        y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 16
                                        implicitHeight: 16
                                        radius: 8
                                        color: volumeSlider.pressed ? '#ffffff' : root.accentColor
                                        border.color: '#ffffff'
                                        border.width: 1.5
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    color: "transparent"
                                }
                                
                                Rectangle {
                                    width: parent.parent.width * 0.5
                                    height: parent.parent.height * 0.12
                                    radius: height * 0.3
                                    color: muteArea.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15) : "transparent"
                                    border.color: root.accentColor
                                    border.width: 1
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: systemVolume.muted ? qsTr("Unmute") : qsTr("Mute")
                                        font { pixelSize: root.fontSize * 0.55; family: "Arial"; bold: true }
                                        color: '#ffffff'
                                    }

                                    MouseArea {
                                        id: muteArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: systemVolume.toggleMute()
                                    }
                                }
                            }

                            scale: volumeHover.hovered ? 1.03 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                            HoverHandler { id: volumeHover }
                        }

                        // WEATHER CITY CARD — glass morphism
                                                // WEATHER CITY CARD — glass morphism
                        Item {
                            id: weatherCard
                            width: root.cardWidth
                            height: root.height / 2.5

                            Rectangle {
                                id: weatherGlass
                                anchors.fill: parent
                                radius: height * 0.06
                                color: "#3D717E"
                                border.width: 1
                                border.color: "#50FFFFFF"
                                visible: false
                            }

                            InnerShadow {
                                id: weatherInner
                                anchors.fill: weatherGlass
                                source: weatherGlass
                                horizontalOffset: -3
                                verticalOffset: -3
                                radius: 10
                                samples: 20
                                color: "#80FFFFFF"
                                visible: false
                            }

                            DropShadow {
                                anchors.fill: weatherGlass
                                source: weatherInner
                                horizontalOffset: 6
                                verticalOffset: 6
                                radius: 14
                                samples: 28
                                color: "#50000000"
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: height * 0.06
                                color: "transparent"
                                border.color: root.accentColor
                                border.width: 2
                                opacity: weatherHover.hovered ? 0.55 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }

                            Rectangle {
                                width: parent.width * 0.4
                                height: 3
                                radius: 2
                                color: root.accentColor
                                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                                opacity: 0.85
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: parent.height * 0.03
                                width: parent.width

                                Rectangle {
                                    width: parent.parent.height * 0.3
                                    height: width
                                    radius: width / 2
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15)
                                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.5)
                                    border.width: 1
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Image {
                                        source: "qrc:/assets/icons/weather.png"
                                        anchors.centerIn: parent
                                        width: parent.width * 0.55
                                        height: parent.height * 0.55
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    color: "transparent"
                                }

                                Text {
                                    text: qsTr("Weather City")
                                    font { pixelSize: root.fontSize * 0.6; bold: true; family: "Arial" }
                                    color: '#ffffff'
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                // Hidden input — syncs with VirtualKeyboard
                                TextInput {
                                    id: cityInput
                                    visible: false
                                    text: root.preferredCity || ""
                                }

                                // Visual display (replaces TextField)
                                Rectangle {
                                    id: cityInputDisplay
                                    width: parent.parent.width * 0.75
                                    height: parent.parent.height * 0.13
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    radius: height * 0.25
                                    color: '#082839'
                                    border.color: cityInputMouse.containsMouse ? root.accentColor : Qt.rgba(1,1,1,0.1)
                                    border.width: 1.5

                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        text: cityInput.text
                                        color: '#ffffff'
                                        font.pixelSize: root.fontSize * 0.4
                                        elide: Text.ElideRight
                                        visible: cityInput.text !== ""
                                    }

                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        text: "Enter city..."
                                        color: "#8899bb"
                                        font.pixelSize: root.fontSize * 0.4
                                        visible: cityInput.text === ""
                                    }

                                    MouseArea {
                                        id: cityInputMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: keyboardPopup.open()
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    color: "transparent"
                                }

                                Rectangle {
                                    width: parent.parent.width * 0.5
                                    height: parent.parent.height * 0.12
                                    radius: height * 0.3
                                    color: saveArea.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15) : "transparent"
                                    border.color: root.accentColor
                                    border.width: 1
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: qsTr("Save")
                                        font { pixelSize: root.fontSize * 0.55; family: "Arial"; bold: true }
                                        color: '#ffffff'
                                    }

                                    MouseArea {
                                        id: saveArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: weatherCard.saveCity()
                                    }
                                }
                            }

                            scale: weatherHover.hovered ? 1.03 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                            function saveCity() {
                                var newCity = cityInput.text.trim()
                                if (newCity.length > 0) {
                                    root.preferredCity = newCity
                                    cityInput.focus = false
                                }
                            }
                            HoverHandler { id: weatherHover }

                            // Virtual Keyboard Popup — parented to Overlay so it isn't clipped
                            Popup {
                                id: keyboardPopup
                                parent: Overlay.overlay
                                width: root.width * 0.6
                                height: root.height * 0.7
                                anchors.centerIn: Overlay.overlay
                                modal: true
                                focus: true
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                                // Dim the page behind the dialog, same as the Wi-Fi popups
                                Overlay.modal: Rectangle {
                                    color: "#000000"
                                    opacity: 0.6
                                    Behavior on opacity { NumberAnimation { duration: 180 } }
                                }

                                background: Rectangle {
                                    color: "#082839"
                                    radius: 16
                                    border.color: root.accentColor
                                    border.width: 2
                                }

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 20
                                    spacing: 16

                                    Text {
                                        text: "Enter City"
                                        font.pixelSize: root.fontSize * 0.7
                                        color: root.accentColor
                                        font.bold: true
                                        font.family: "Arial"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    VirtualKeyboard {
                                        id: keyboard
                                        width: parent.width
                                        targetItem: cityInput
                                        passwordMode: false
                                        maxLength: 32

                                        onAccepted: {
                                            weatherCard.saveCity()
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
                                    keyboard.targetText = cityInput.text
                                }
                            }
                        }
                    }
                }
            }
        }

        Component {
            id: wifiPageComponent
            WiFiPage {
                id: wifiPage
                stackView: stackView
            }
        }

        Component {
            id: bluetoothPageComponent
            BluetoothPage {
                id: btPage
                stackView: stackView
            }
        }

        Component {
            id: ambientPageComponent
            AmbientLightPage {
                id: ambientPage
                stackView: stackView
            }
        }
    }
}