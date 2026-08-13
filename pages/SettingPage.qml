import QtQuick
import QtQuick.Controls
pragma ComponentBehavior: Bound

Item {
    id: root
    signal goBack()
    property real fontSize: (width + height) / 60
    property string preferredCity

    /*
     * Primary accent for the page chrome (window bar, shared controls). The
     * cards no longer share one colour — each carries its own, the way the home
     * screen's tiles do, so a card is identifiable by its glow before its label
     * is readable.
     */
    property color accentColor: Theme.accentBlue

    // Cards are sized from how many there are rather than a fixed fraction of
    // the width. Five at the old root.width/5.5 overflowed the screen; deriving
    // it means the next one added cannot silently do that again.
    readonly property int  cardCount:   5
    readonly property real cardSpacing: root.width / 32
    readonly property real cardWidth:
        (root.width * 0.90 - cardSpacing * (cardCount - 1)) / cardCount
    readonly property real cardHeight: root.height / 2.3

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

        // Ends of the bar carry the page's own gradient, so it reads as part of
        // the backdrop rather than as a strip laid across it.
        color0: Theme.gradientTop
        color1: Theme.gradientMid
        color2: Theme.gradientBot
        accent: root.accentColor
        titleColor: Theme.textPrimary
        surface: Theme.surface

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

    // BACKGROUND — same one the home screen uses
    GlassBackground {
        id: background
        anchors.fill: parent

        StackView {
            id: stackView
            anchors.fill: parent
            initialItem: mainPageComponent

            Component {
                id: mainPageComponent
                Item {
                    id: app
                    anchors.fill: parent
                    // Clears the window bar. Anchoring the row to the centre of
                    // what is left keeps the grid balanced at any height instead
                    // of at the one the fixed 30% margin happened to suit.
                    anchors.topMargin: 48

                    Row {
                        id: cardRow
                        spacing: root.cardSpacing
                        anchors.centerIn: parent

                        // WI-FI
                        GlassCard {
                            width: root.cardWidth
                            height: root.cardHeight
                            accent: Theme.accentCyan
                            floatAmplitude: 4
                            floatPhase: 0
                            onClicked: stackView.push(wifiPageComponent)

                            Column {
                                anchors.centerIn: parent
                                spacing: parent.height * 0.06

                                IconWell {
                                    accent: Theme.accentCyan
                                    diameter: root.cardHeight * 0.32
                                    source: "qrc:/assets/icons/wifi.png"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: qsTr("Wi-Fi")
                                    color: Theme.textPrimary
                                    font { bold: true; family: "Arial"; pixelSize: root.fontSize }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: WifiManager.connectedSsid !== "" ? WifiManager.connectedSsid
                                                                           : qsTr("Manage connections")
                                    // Live state rather than a fixed caption: the
                                    // card is the only place in Settings that can
                                    // say what you are actually on without opening
                                    // the sub-page.
                                    color: WifiManager.connectedSsid !== "" ? Theme.textOnAccent
                                                                            : Theme.textSecondary
                                    font { family: "Arial"; pixelSize: root.fontSize * 0.55 }
                                    width: root.cardWidth * 0.8
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }

                        // BLUETOOTH
                        GlassCard {
                            width: root.cardWidth
                            height: root.cardHeight
                            accent: Theme.accentBlue
                            floatAmplitude: 4
                            floatPhase: 700
                            onClicked: stackView.push(bluetoothPageComponent)

                            Column {
                                anchors.centerIn: parent
                                spacing: parent.height * 0.06

                                IconWell {
                                    accent: Theme.accentBlue
                                    diameter: root.cardHeight * 0.32
                                    source: "qrc:/assets/icons/bt.png"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: qsTr("Bluetooth")
                                    color: Theme.textPrimary
                                    font { bold: true; family: "Arial"; pixelSize: root.fontSize - 2 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: BluetoothManager.anyDeviceConnected ? qsTr("Connected")
                                                                              : qsTr("Pair your devices")
                                    color: BluetoothManager.anyDeviceConnected ? Theme.textOnAccent
                                                                               : Theme.textSecondary
                                    font { family: "Arial"; pixelSize: root.fontSize * 0.6 }
                                    width: root.cardWidth * 0.8
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }

                        // AMBIENT LIGHT
                        GlassCard {
                            id: ambientCard
                            width: root.cardWidth
                            height: root.cardHeight
                            // Follows the cabin. The one card whose accent is not
                            // fixed — its glow *is* the setting it controls.
                            accent: AmbientLight.on ? AmbientLight.color : Theme.accentViolet
                            floatAmplitude: 4
                            floatPhase: 1400
                            onClicked: stackView.push(ambientPageComponent)

                            Behavior on accent { ColorAnimation { duration: 250 } }

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
                                    width: root.cardHeight * 0.32
                                    height: width
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 1.5
                                        height: width
                                        radius: width / 2
                                        color: AmbientLight.color
                                        opacity: AmbientLight.on ? 0.28 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 250 } }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        // Off is a lamp that is not lit, not a
                                        // hole: it keeps a fill and a rim, both
                                        // just bright enough to hold their shape
                                        // against the card behind them.
                                        color: AmbientLight.on ? AmbientLight.color
                                                               : Qt.rgba(1, 1, 1, 0.10)
                                        border.color: AmbientLight.on
                                                      ? Qt.lighter(AmbientLight.color, 1.4)
                                                      : Qt.rgba(1, 1, 1, 0.28)
                                        border.width: 2
                                        Behavior on color { ColorAnimation { duration: 250 } }
                                    }
                                }

                                Text {
                                    text: qsTr("Ambient Light")
                                    color: Theme.textPrimary
                                    font { bold: true; family: "Arial"; pixelSize: root.fontSize * 0.7 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: AmbientLight.on ? qsTr("On")
                                                          : qsTr("Cabin lighting")
                                    color: AmbientLight.on ? Theme.textOnAccent : Theme.textSecondary
                                    font { family: "Arial"; pixelSize: root.fontSize * 0.6 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }

                        // VOLUME
                        GlassCard {
                            width: root.cardWidth
                            height: root.cardHeight
                            accent: Theme.accentMint
                            floatAmplitude: 4
                            floatPhase: 2100
                            // A control panel, not a door: no push, but it still
                            // lights on hover so the row behaves as one surface.
                            onClicked: {}

                            Column {
                                anchors.centerIn: parent
                                spacing: parent.height * 0.05
                                width: parent.width

                                IconWell {
                                    accent: Theme.accentMint
                                    diameter: root.cardHeight * 0.30
                                    source: "qrc:/assets/icons/volume.png"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: qsTr("Volume")
                                    font { pixelSize: root.fontSize * 0.6; bold: true; family: "Arial" }
                                    color: Theme.textPrimary
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Slider {
                                    id: volumeSlider
                                    width: parent.width * 0.72
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
                                        // Sunk, not filled: a dark well under a
                                        // translucent card still reads as a track,
                                        // where a white one glows through it.
                                        color: Qt.rgba(0, 0, 0, 0.35)

                                        Rectangle {
                                            width: volumeSlider.visualPosition * parent.width
                                            height: parent.height
                                            color: Theme.accentMint
                                            radius: 3
                                        }
                                    }

                                    handle: Rectangle {
                                        x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                                        y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 16
                                        implicitHeight: 16
                                        radius: 8
                                        color: volumeSlider.pressed ? Theme.textPrimary : Theme.accentMint
                                        border.color: Theme.textPrimary
                                        border.width: 1.5
                                    }
                                }

                                GlassButton {
                                    accent: Theme.accentMint
                                    text: systemVolume.muted ? qsTr("Unmute") : qsTr("Mute")
                                    fontSize: root.fontSize * 0.55
                                    width: parent.width * 0.5
                                    height: root.cardHeight * 0.12
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    onClicked: systemVolume.toggleMute()
                                }
                            }
                        }

                        // WEATHER CITY
                        GlassCard {
                            id: weatherCard
                            width: root.cardWidth
                            height: root.cardHeight
                            accent: Theme.accentAmber
                            floatAmplitude: 4
                            floatPhase: 2800
                            onClicked: {}

                            function saveCity() {
                                var newCity = cityInput.text.trim()
                                if (newCity.length > 0) {
                                    root.preferredCity = newCity
                                    cityInput.focus = false
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: parent.height * 0.05
                                width: parent.width

                                IconWell {
                                    accent: Theme.accentAmber
                                    diameter: root.cardHeight * 0.30
                                    source: "qrc:/assets/icons/weather.png"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: qsTr("Weather City")
                                    font { pixelSize: root.fontSize * 0.6; bold: true; family: "Arial" }
                                    color: Theme.textPrimary
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
                                    width: parent.width * 0.72
                                    height: root.cardHeight * 0.13
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    radius: height * 0.35
                                    color: Qt.rgba(0, 0, 0, 0.30)
                                    border.color: cityInputMouse.containsMouse
                                                  ? Theme.tint(Theme.accentAmber, 0.7)
                                                  : Theme.glassBorder
                                    border.width: 1.5
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        text: cityInput.text
                                        color: Theme.textPrimary
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
                                        text: qsTr("Enter city...")
                                        color: Theme.textMuted
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

                                GlassButton {
                                    accent: Theme.accentAmber
                                    text: qsTr("Save")
                                    fontSize: root.fontSize * 0.55
                                    width: parent.width * 0.5
                                    height: root.cardHeight * 0.12
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    onClicked: weatherCard.saveCity()
                                }
                            }

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
                                    color: Theme.scrim
                                    Behavior on opacity { NumberAnimation { duration: 180 } }
                                }

                                background: Rectangle {
                                    color: Theme.surface
                                    radius: Theme.dialogRadius
                                    border.color: Theme.tint(Theme.accentAmber, 0.35)
                                    border.width: 1
                                }

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 20
                                    spacing: 16

                                    Text {
                                        text: qsTr("Enter City")
                                        font.pixelSize: root.fontSize * 0.7
                                        color: Theme.accentAmber
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
                                        accent: Theme.accentAmber
                                        keyColor: Theme.glassFill
                                        keyTextColor: Theme.textPrimary
                                        fieldColor: Qt.rgba(0, 0, 0, 0.30)

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
