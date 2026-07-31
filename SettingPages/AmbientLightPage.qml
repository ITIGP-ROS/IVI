import QtQuick
import QtQuick.Controls

Rectangle {
    id: ambientPage
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    color: "transparent"
    required property StackView stackView

    // ---------------------------------------------------------------- model
    readonly property var modes: [
        { name: "Static",  value: 1 },
        { name: "Breathe", value: 2 },
        { name: "Chase",   value: 3 },
        { name: "Scanner", value: 4 },
        { name: "Rainbow", value: 5 }
    ]

    /*
     * No alternating red/blue anywhere in here: that pattern imitates emergency
     * vehicles and is illegal on a road vehicle in most places. Single static
     * colours are fine, which is all these are.
     */
    readonly property var presets: [
        "#ffd7a0", "#ff8000", "#ff2020", "#ff30a0",
        "#8040ff", "#2060ff", "#00d0d0", "#30d040"
    ]

    readonly property real gutter: width * 0.05

    /*
     * Hue survives desaturation.
     *
     * QColor reports hsvHue as -1 for white and greys, because a colour with no
     * saturation has no hue to report. Reading the hue handle straight off the
     * colour therefore snapped it back to red the moment saturation reached
     * zero, which is why the saturation bar used to stop 5% short of its own
     * left edge. Remembering the last real hue lets white be selected properly.
     */
    property real lastHue: 0
    Connections {
        target: AmbientLight
        function onColorChanged() {
            if (AmbientLight.color.hsvHue >= 0)
                ambientPage.lastHue = AmbientLight.color.hsvHue
        }
    }
    readonly property real level:  AmbientLight.brightness / 255

    // Rainbow generates its own colours, so the colour controls have nothing to
    // act on while it is running.
    readonly property bool colorApplies: AmbientLight.mode !== 5

    /*
     * Drives the preview only. The ESP32 renders the real strip from the same
     * rules; this exists so the driver can see what an effect looks like before
     * committing to it, without staring at the ceiling.
     */
    property int phase: 0
    Timer {
        running: AmbientLight.on && AmbientLight.mode > 1
        interval: 420 - AmbientLight.speed * 34
        repeat: true
        onTriggered: ambientPage.phase++
    }

    function ledColor(i) {
        if (!AmbientLight.on || (AmbientLight.zoneMask & (1 << i)) === 0)
            return "#0e2a36"

        const c = AmbientLight.color
        const p = ambientPage.phase

        switch (AmbientLight.mode) {
        case 2: {   // breathe — triangle wave so it never sits fully dark
            const t = (p % 20) / 20
            const k = (t < 0.5 ? t * 2 : (1 - t) * 2) * 0.8 + 0.2
            return Qt.rgba(c.r * ambientPage.level * k,
                           c.g * ambientPage.level * k,
                           c.b * ambientPage.level * k, 1)
        }
        case 3:     // chase
            return (p % 6) === i ? Qt.rgba(c.r * ambientPage.level,
                                           c.g * ambientPage.level,
                                           c.b * ambientPage.level, 1)
                                 : "#0e2a36"
        case 4: {   // scanner — bounce across and back
            const pos = p % 10
            const at  = pos < 6 ? pos : 10 - pos
            return at === i ? Qt.rgba(c.r * ambientPage.level,
                                      c.g * ambientPage.level,
                                      c.b * ambientPage.level, 1)
                            : "#0e2a36"
        }
        case 5:     // rainbow — hue spread across the strip, drifting
            return Qt.hsva(((i / 6) + (p % 40) / 40) % 1, 1, ambientPage.level, 1)
        default:    // static
            return Qt.rgba(c.r * ambientPage.level,
                           c.g * ambientPage.level,
                           c.b * ambientPage.level, 1)
        }
    }

    // Background
    Rectangle {
        z: -1
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#071f2c" }
            GradientStop { position: 0.5; color: "#0d3446" }
            GradientStop { position: 1.0; color: "#071f2c" }
        }
    }

    // ==================================================== HEADER
    Item {
        id: header
        anchors {
            left: parent.left;   leftMargin:  ambientPage.gutter
            right: parent.right; rightMargin: ambientPage.gutter
            // Clears the window bar, which is 38 high at a 10 top margin and is
            // drawn over this page rather than above it.
            top: parent.top;     topMargin:   ambientPage.height * 0.085
        }
        height: ambientPage.height * 0.085

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: ambientPage.height * 0.006

            Text {
                text: qsTr("Ambient Light")
                color: "#ffffff"
                font { bold: true; family: "Arial"
                       pixelSize: ambientPage.height * 0.048 }
            }
            Text {
                text: AmbientLight.available
                      ? (AmbientLight.on ? qsTr("Cabin lighting on")
                                         : qsTr("Cabin lighting off"))
                      : qsTr("⚠  No CAN link to the lighting ECU — check can0")
                color: AmbientLight.available ? "#7fa3b8" : "#dd9c4d"
                font { family: "Arial"; pixelSize: ambientPage.height * 0.022 }
            }
        }

        Rectangle {
            id: powerToggle
            width: ambientPage.height * 0.11
            height: ambientPage.height * 0.055
            radius: height / 2
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            color: AmbientLight.on ? AmbientLight.color : "#12374a"
            border.color: AmbientLight.on ? Qt.lighter(AmbientLight.color, 1.3)
                                          : "#2c5a70"
            border.width: 2
            opacity: AmbientLight.available ? 1.0 : 0.35
            Behavior on color { ColorAnimation { duration: 200 } }

            Rectangle {
                width: parent.height * 0.76
                height: width
                radius: width / 2
                color: "#ffffff"
                anchors.verticalCenter: parent.verticalCenter
                x: AmbientLight.on ? parent.width - width - parent.height * 0.12
                                   : parent.height * 0.12
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
            }

            MouseArea {
                anchors.fill: parent
                enabled: AmbientLight.available
                onClicked: AmbientLight.on = !AmbientLight.on
            }
        }
    }

    // ==================================================== LIVE PREVIEW / ZONES
    /*
     * The six physical LEDs, animated exactly as the effect will run, and each
     * one is its own zone toggle — tapping a lamp drops it out of the mask.
     * Folding the zone control into the preview means there is no second row of
     * abstract checkboxes to map back onto the strip in your head.
     */
    Rectangle {
        id: preview
        anchors {
            left: parent.left;   leftMargin:  ambientPage.gutter
            right: parent.right; rightMargin: ambientPage.gutter
            top: header.bottom;  topMargin:   ambientPage.height * 0.028
        }
        height: ambientPage.height * 0.15
        radius: 20
        color: "#061922"
        border.color: "#173d4e"
        border.width: 1

        Text {
            anchors { left: parent.left; leftMargin: parent.width * 0.02
                      top: parent.top;   topMargin:  parent.height * 0.1 }
            text: qsTr("TAP A LAMP TO INCLUDE OR EXCLUDE IT")
            color: "#3f6d85"
            font { bold: true; family: "Arial"
                   pixelSize: ambientPage.height * 0.017; letterSpacing: 1 }
        }

        Row {
            id: ledRow
            anchors.centerIn: parent
            anchors.verticalCenterOffset: parent.height * 0.08
            readonly property real dotSize: preview.height * 0.38
            readonly property real span:    preview.width * 0.86
            spacing: (span - 6 * dotSize) / 5

            Repeater {
                model: 6

                Item {
                    id: lamp
                    required property int index
                    width: ledRow.dotSize
                    height: width

                    readonly property bool enabled: (AmbientLight.zoneMask & (1 << index)) !== 0
                    readonly property color shade: ambientPage.ledColor(index)

                    // Halo: stacked fades rather than a Glow effect, so this
                    // needs no extra QML module on the target image.
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            anchors.centerIn: parent
                            // Capped so the widest ring still fits inside the
                            // panel — they used to spill out of its bottom edge.
                            width: parent.width * (1.3 + index * 0.45)
                            height: width
                            radius: width / 2
                            color: lamp.shade
                            opacity: lamp.enabled && AmbientLight.on ? 0.17 / (index + 1) : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: lamp.shade
                        border.color: lamp.enabled ? Qt.lighter(lamp.shade, 1.5)
                                                   : "#16303d"
                        border.width: 2
                        // Excluded lamps read as absent, not merely dark, so the
                        // mask is legible at a glance even while the strip is off.
                        opacity: lamp.enabled ? 1.0 : 0.35
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: AmbientLight.available
                        onClicked: AmbientLight.zoneMask =
                                   AmbientLight.zoneMask ^ (1 << lamp.index)
                    }
                }
            }
        }
    }

    // ==================================================== MODE
    Text {
        id: modeLabel
        text: qsTr("MODE")
        color: "#7fa3b8"
        font { bold: true; family: "Arial"
               pixelSize: ambientPage.height * 0.021; letterSpacing: 2 }
        anchors { left: preview.left; top: preview.bottom
                  topMargin: ambientPage.height * 0.032 }
    }

    Row {
        id: modeRow
        anchors { left: preview.left; top: modeLabel.bottom
                  topMargin: ambientPage.height * 0.018 }
        spacing: ambientPage.width * 0.014

        Repeater {
            model: ambientPage.modes

            Rectangle {
                id: modeChip
                required property var modelData
                readonly property bool selected: AmbientLight.mode === modeChip.modelData.value

                width: ambientPage.width * 0.115
                height: ambientPage.height * 0.062
                radius: height / 2
                color: selected ? AmbientLight.color : "transparent"
                border.color: selected ? Qt.lighter(AmbientLight.color, 1.3) : "#2c5a70"
                border.width: 2
                opacity: AmbientLight.available ? 1.0 : 0.35
                Behavior on color { ColorAnimation { duration: 160 } }

                Text {
                    anchors.centerIn: parent
                    text: modeChip.modelData.name
                    // Dark text once the chip is filled with a pale colour.
                    color: modeChip.selected
                           ? (AmbientLight.color.hslLightness > 0.6 ? "#071f2c" : "#ffffff")
                           : "#9fc0d0"
                    font { bold: true; family: "Arial"
                           pixelSize: ambientPage.height * 0.026 }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: AmbientLight.available
                    onClicked: {
                        AmbientLight.mode = modeChip.modelData.value
                        if (!AmbientLight.on)
                            AmbientLight.on = true
                    }
                }
            }
        }
    }

    // ==================================================== COLOUR (left column)
    Item {
        id: colourColumn
        anchors { left: preview.left; top: modeRow.bottom
                  topMargin: ambientPage.height * 0.04 }
        width: preview.width * 0.58
        height: ambientPage.height * 0.30
        opacity: ambientPage.colorApplies ? 1.0 : 0.35
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            id: colourLabel
            text: ambientPage.colorApplies ? qsTr("COLOUR")
                                           : qsTr("COLOUR — SET BY RAINBOW")
            color: "#7fa3b8"
            font { bold: true; family: "Arial"
                   pixelSize: ambientPage.height * 0.021; letterSpacing: 2 }
        }

        Row {
            id: presetRow
            anchors { left: parent.left; top: colourLabel.bottom
                      topMargin: ambientPage.height * 0.022 }
            spacing: (colourColumn.width - 8 * chip) / 7
            readonly property real chip: ambientPage.height * 0.062

            Repeater {
                model: ambientPage.presets

                Rectangle {
                    id: chipItem
                    required property var modelData
                    width: presetRow.chip
                    height: width
                    radius: width / 2
                    color: chipItem.modelData
                    scale: chipHover.hovered ? 1.1 : 1.0
                    Behavior on scale { NumberAnimation { duration: 130 } }

                    // Ring sits outside the chip so it never eats into the
                    // colour being judged.
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 1.36
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.color: "#ffffff"
                        border.width: 2
                        opacity: Qt.colorEqual(AmbientLight.color, chipItem.modelData) ? 0.9 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    HoverHandler { id: chipHover }
                    MouseArea {
                        anchors.fill: parent
                        enabled: AmbientLight.available && ambientPage.colorApplies
                        onClicked: {
                            AmbientLight.color = chipItem.modelData
                            if (!AmbientLight.on)
                                AmbientLight.on = true
                        }
                    }
                }
            }
        }

        /*
         * Freeform picker as two bars rather than a wheel or a shader.
         *
         * Hue and saturation only — value is deliberately absent, because on an
         * LED strip "how bright" is the brightness control, and offering both
         * would give two ways to dim with different results on the wire.
         *
         * Built from gradient stops, so it needs no Canvas, no shader and no
         * extra QML module on the target image.
         */
        Text {
            id: hueLabel
            anchors { left: parent.left; top: presetRow.bottom
                      topMargin: ambientPage.height * 0.035 }
            text: qsTr("HUE")
            color: "#5c88a0"
            font { bold: true; family: "Arial"; pixelSize: ambientPage.height * 0.019 }
        }

        Rectangle {
            id: hueBar
            anchors { left: parent.left; right: parent.right
                      top: hueLabel.bottom; topMargin: ambientPage.height * 0.012 }
            height: ambientPage.height * 0.038
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.000; color: "#ff0000" }
                GradientStop { position: 0.167; color: "#ffff00" }
                GradientStop { position: 0.333; color: "#00ff00" }
                GradientStop { position: 0.500; color: "#00ffff" }
                GradientStop { position: 0.667; color: "#0000ff" }
                GradientStop { position: 0.833; color: "#ff00ff" }
                GradientStop { position: 1.000; color: "#ff0000" }
            }

            readonly property real hue: AmbientLight.color.hsvHue >= 0
                                        ? AmbientLight.color.hsvHue
                                        : ambientPage.lastHue
            readonly property real sat: AmbientLight.color.hsvSaturation

            Rectangle {
                width: parent.height * 1.25
                height: width
                radius: width / 2
                y: (parent.height - height) / 2
                x: Math.max(0, Math.min(parent.width - width,
                                        hueBar.hue * parent.width - width / 2))
                color: "transparent"
                border.color: "#ffffff"
                border.width: 3
            }

            MouseArea {
                anchors.fill: parent
                enabled: AmbientLight.available && ambientPage.colorApplies
                function pick(mx) {
                    const h = Math.max(0, Math.min(1, mx / width))
                    // Reaching for a hue while sitting on white plainly means
                    // "give me that colour", so this takes saturation with it
                    // rather than leaving the bar looking broken.
                    const s = hueBar.sat < 0.05 ? 1.0 : hueBar.sat
                    AmbientLight.color = Qt.hsva(h, s, 1, 1)
                    if (!AmbientLight.on)
                        AmbientLight.on = true
                }
                onPressed: (m) => pick(m.x)
                onPositionChanged: (m) => { if (pressed) pick(m.x) }
            }
        }

        Text {
            id: satLabel
            anchors { left: parent.left; top: hueBar.bottom
                      topMargin: ambientPage.height * 0.022 }
            text: qsTr("SATURATION")
            color: "#5c88a0"
            font { bold: true; family: "Arial"; pixelSize: ambientPage.height * 0.019 }
        }

        Rectangle {
            id: satBar
            anchors { left: parent.left; right: parent.right
                      top: satLabel.bottom; topMargin: ambientPage.height * 0.012 }
            height: ambientPage.height * 0.038
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#ffffff" }
                GradientStop { position: 1.0; color: Qt.hsva(hueBar.hue, 1, 1, 1) }
            }

            Rectangle {
                width: parent.height * 1.25
                height: width
                radius: width / 2
                y: (parent.height - height) / 2
                x: Math.max(0, Math.min(parent.width - width,
                                        hueBar.sat * parent.width - width / 2))
                color: "transparent"
                border.color: "#0b2836"
                border.width: 3
            }

            MouseArea {
                anchors.fill: parent
                enabled: AmbientLight.available && ambientPage.colorApplies
                function pick(mx) {
                    // Full range: 0 is pure white, which the bar draws at its
                    // left end and is a perfectly reasonable cabin colour.
                    const s = Math.max(0, Math.min(1, mx / width))
                    AmbientLight.color = Qt.hsva(hueBar.hue, s, 1, 1)
                    if (!AmbientLight.on)
                        AmbientLight.on = true
                }
                onPressed: (m) => pick(m.x)
                onPositionChanged: (m) => { if (pressed) pick(m.x) }
            }
        }
    }

    // ==================================================== LEVELS (right column)
    Item {
        id: levelColumn
        anchors { right: preview.right; top: modeRow.bottom
                  topMargin: ambientPage.height * 0.04 }
        width: preview.width * 0.36
        height: colourColumn.height

        Text {
            id: levelLabel
            text: qsTr("LEVELS")
            color: "#7fa3b8"
            font { bold: true; family: "Arial"
                   pixelSize: ambientPage.height * 0.021; letterSpacing: 2 }
        }

        // ---- Brightness
        Text {
            id: brightCaption
            anchors { left: parent.left; top: levelLabel.bottom
                      topMargin: ambientPage.height * 0.022 }
            text: qsTr("Brightness")
            color: "#9fc0d0"
            font { family: "Arial"; pixelSize: ambientPage.height * 0.024 }
        }
        Text {
            anchors { right: parent.right; verticalCenter: brightCaption.verticalCenter }
            text: Math.round(ambientPage.level * 100) + "%"
            color: "#ffffff"
            font { bold: true; family: "Arial"; pixelSize: ambientPage.height * 0.028 }
        }

        Slider {
            id: brightnessSlider
            anchors { left: parent.left; right: parent.right
                      top: brightCaption.bottom; topMargin: ambientPage.height * 0.012 }
            height: ambientPage.height * 0.05
            from: 10          // 0 here would only be a second off switch
            to: 255
            stepSize: 1
            enabled: AmbientLight.available
            value: AmbientLight.brightness

            // The manager coalesces, so writing on every frame of a drag is
            // safe — it becomes a steady 20 Hz on the bus, not a flood.
            onMoved: {
                AmbientLight.brightness = value
                if (!AmbientLight.on)
                    AmbientLight.on = true
            }

            background: Rectangle {
                x: brightnessSlider.leftPadding
                y: brightnessSlider.topPadding
                   + brightnessSlider.availableHeight / 2 - height / 2
                width: brightnessSlider.availableWidth
                height: ambientPage.height * 0.013
                radius: height / 2
                color: "#0e2a36"

                Rectangle {
                    width: brightnessSlider.visualPosition * parent.width
                    height: parent.height
                    radius: height / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.darker(AmbientLight.color, 2.4) }
                        GradientStop { position: 1.0; color: AmbientLight.color }
                    }
                }
            }

            handle: Rectangle {
                x: brightnessSlider.leftPadding
                   + brightnessSlider.visualPosition
                     * (brightnessSlider.availableWidth - width)
                y: brightnessSlider.topPadding
                   + brightnessSlider.availableHeight / 2 - height / 2
                width: ambientPage.height * 0.044
                height: width
                radius: width / 2
                color: "#ffffff"
                border.color: AmbientLight.color
                border.width: 3
                scale: brightnessSlider.pressed ? 1.15 : 1.0
                Behavior on scale { NumberAnimation { duration: 120 } }
            }
        }

        // ---- Speed
        Text {
            id: speedCaption
            anchors { left: parent.left; top: brightnessSlider.bottom
                      topMargin: ambientPage.height * 0.03 }
            text: qsTr("Speed")
            // Static has nothing to animate, so the control says so instead of
            // sitting there accepting input that changes nothing.
            color: AmbientLight.mode === 1 ? "#4d7a90" : "#9fc0d0"
            font { family: "Arial"; pixelSize: ambientPage.height * 0.024 }
        }
        Text {
            anchors { right: parent.right; verticalCenter: speedCaption.verticalCenter }
            text: AmbientLight.mode === 1 ? qsTr("—") : AmbientLight.speed
            color: "#ffffff"
            font { bold: true; family: "Arial"; pixelSize: ambientPage.height * 0.028 }
        }

        Slider {
            id: speedSlider
            anchors { left: parent.left; right: parent.right
                      top: speedCaption.bottom; topMargin: ambientPage.height * 0.012 }
            height: ambientPage.height * 0.05
            from: 1
            to: 10
            stepSize: 1
            enabled: AmbientLight.available && AmbientLight.mode !== 1
            opacity: enabled ? 1.0 : 0.35
            value: AmbientLight.speed
            onMoved: AmbientLight.speed = value

            background: Rectangle {
                x: speedSlider.leftPadding
                y: speedSlider.topPadding + speedSlider.availableHeight / 2 - height / 2
                width: speedSlider.availableWidth
                height: ambientPage.height * 0.013
                radius: height / 2
                color: "#0e2a36"

                Rectangle {
                    width: speedSlider.visualPosition * parent.width
                    height: parent.height
                    radius: height / 2
                    color: "#4fc3d9"
                }
            }

            handle: Rectangle {
                x: speedSlider.leftPadding
                   + speedSlider.visualPosition * (speedSlider.availableWidth - width)
                y: speedSlider.topPadding + speedSlider.availableHeight / 2 - height / 2
                width: ambientPage.height * 0.044
                height: width
                radius: width / 2
                color: "#ffffff"
                border.color: "#4fc3d9"
                border.width: 3
                scale: speedSlider.pressed ? 1.15 : 1.0
                Behavior on scale { NumberAnimation { duration: 120 } }
            }
        }
    }

    // ==================================================== BACK
    Rectangle {
        width: ambientPage.width * 0.11
        height: ambientPage.height * 0.065
        radius: height / 2
        anchors { left: parent.left; leftMargin: ambientPage.gutter
                  bottom: parent.bottom; bottomMargin: ambientPage.height * 0.035 }
        color: backArea.containsMouse ? "#17465b" : "transparent"
        border.color: "#2c5a70"
        border.width: 2
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            text: qsTr("Back")
            font.pixelSize: parent.height * 0.42
            color: "#e7f1ef"
            font.bold: true
            font.family: "Arial"
            anchors.centerIn: parent
        }

        MouseArea {
            id: backArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: ambientPage.stackView.pop()
        }
    }
}
