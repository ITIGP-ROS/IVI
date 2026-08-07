import QtQuick

/*
 * Home-screen ambient lighting card.
 *
 * The quick controls only — power, mode, and the fixed palette. Brightness,
 * zone masking and the free colour picker stay on the Settings page: this sits
 * on the launcher where it may well be used while moving, and a hue wheel is
 * not something to hand a driver at speed.
 *
 * Drives the same AmbientLight object as the settings page, so the two are
 * always showing the same state rather than each keeping their own copy.
 */
Rectangle {
    id: card

    radius: 28
    color: Qt.rgba(1,1,1,0.05)
    border.color: Qt.rgba(1,1,1,0.12)
    border.width: 1

    // ------------------------------------------------------------- model
    readonly property var modes: [
        { name: "Static",  value: 1 },
        { name: "Breathe", value: 2 },
        { name: "Chase",   value: 3 },
        { name: "Scanner", value: 4 },
        { name: "Rainbow", value: 5 }
    ]

    /*
     * Fixed palette, same eight as the settings page.
     *
     * No alternating red/blue anywhere in here: that pattern imitates emergency
     * vehicles and is illegal on a road vehicle in most places. Single static
     * colours are fine, which is all these are.
     */
    readonly property var presets: [
        "#ffd7a0", "#ff8000", "#ff2020", "#ff30a0",
        "#8040ff", "#2060ff", "#00d0d0", "#30d040"
    ]

    readonly property bool live: AmbientLight.available
    // Rainbow generates its own colours, so the swatches have nothing to act on.
    readonly property bool colorApplies: AmbientLight.mode !== 5

    /*
     * One mode pill. Declared once because the two rows below are 3 + 2 rather
     * than a Grid: a Grid left-aligns its last row, which left Scanner and
     * Rainbow hanging off to one side with a gap where the third would be.
     */
    component ModePill: Rectangle {
        id: pill

        // modelData has to be declared required as well, not just read: once a
        // delegate root declares any required property, the Repeater injects
        // strictly by name and the implicit context property is gone.
        required property var  modelData
        required property real cellW

        readonly property bool current: AmbientLight.mode === modelData.value

        width: cellW
        height: Math.round(card.height * 0.13)
        radius: height / 2
        color: current ? Qt.rgba(1,1,1,0.16) : Qt.rgba(1,1,1,0.05)
        border.color: current ? Qt.rgba(1,1,1,0.42) : Qt.rgba(1,1,1,0.12)
        border.width: 1
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: pill.modelData.name
            color: pill.current ? "#ffffff" : "#8899bb"
            font {
                pixelSize: Math.max(9, card.height * 0.058)
                bold: pill.current
                family: "Arial"
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: card.live && AmbientLight.on
            onClicked: AmbientLight.mode = pill.modelData.value
        }
    }

    // ------------------------------------------------------------- chrome
    Rectangle {
        anchors.fill: parent; radius: parent.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1,1,1,0.08) }
            GradientStop { position: 0.5; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0,0,0,0.08) }
        }
    }
    // Glow picks up the selected colour, so the card itself reads as lit.
    Rectangle {
        anchors.fill: parent; radius: parent.radius
        anchors.margins: -2; z: -1
        color: AmbientLight.on ? AmbientLight.color : "#8040ff"
        opacity: AmbientLight.on ? 0.10 : 0.05
        Behavior on color   { ColorAnimation  { duration: 250 } }
        Behavior on opacity { NumberAnimation { duration: 250 } }
    }

    // ------------------------------------------------------------ content
    // Centred rather than filled: the three rows come to a bit less than the
    // card, and splitting the slack top and bottom reads as deliberate where
    // pinning to the top leaves it all pooled under the swatches.
    Column {
        id: body
        anchors.centerIn: parent
        width: parent.width - Math.round(card.width * 0.12)
        spacing: Math.round(card.height * 0.075)

        // ---- title + power ------------------------------------------
        Item {
            width: parent.width
            // Whichever side is taller. Sizing this to the toggle alone let the
            // two-line title overhang into the row below it.
            height: Math.max(powerToggle.height, titleCol.height)

            Column {
                id: titleCol
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    text: "Ambient Lighting"
                    color: "#ffffff"
                    font { pixelSize: Math.max(14, card.height * 0.082); bold: true; family: "Arial" }
                }
                Text {
                    // Says which of the three states it is in, because "off" and
                    // "no ECU on the bus" look identical on an unlit strip.
                    text: !card.live      ? "No ECU"
                        : AmbientLight.on ? card.modes[AmbientLight.mode - 1].name
                                          : "Off"
                    color: !card.live ? "#dd9c4d" : AmbientLight.on ? "#8899bb" : "#66738a"
                    font { pixelSize: Math.max(10, card.height * 0.06); family: "Arial" }
                }
            }

            Rectangle {
                id: powerToggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(card.height * 0.25)
                height: Math.round(width * 0.6)
                radius: height / 2
                color: AmbientLight.on ? AmbientLight.color : Qt.rgba(1,1,1,0.10)
                border.color: AmbientLight.on ? Qt.lighter(AmbientLight.color, 1.3)
                                              : Qt.rgba(1,1,1,0.22)
                border.width: 2
                opacity: card.live ? 1.0 : 0.35
                Behavior on color { ColorAnimation { duration: 200 } }

                Rectangle {
                    width: parent.height * 0.72; height: width
                    radius: width / 2
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                    x: AmbientLight.on ? parent.width - width - parent.height * 0.14
                                       : parent.height * 0.14
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: card.live
                    onClicked: AmbientLight.on = !AmbientLight.on
                }
            }
        }

        // ---- modes ----------------------------------------------------
        Column {
            id: modeBox
            width: parent.width
            spacing: Math.round(card.width * 0.028)
            opacity: card.live && AmbientLight.on ? 1.0 : 0.4

            // Cells stay a third of the width in both rows, so the two on the
            // bottom row line up with the ones above rather than stretching.
            readonly property real cellW: (width - spacing * 2) / 3

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: modeBox.spacing
                Repeater {
                    model: card.modes.slice(0, 3)
                    delegate: ModePill { cellW: modeBox.cellW }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: modeBox.spacing
                Repeater {
                    model: card.modes.slice(3)
                    delegate: ModePill { cellW: modeBox.cellW }
                }
            }
        }


        // ---- colours --------------------------------------------------
        Row {
            id: swatchRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(card.width * 0.025)

            // Dimmed rather than hidden under Rainbow: the swatches vanishing
            // and the row collapsing every time that mode is picked is a worse
            // surprise than a row that is visibly not accepting input.
            opacity: card.live && AmbientLight.on && card.colorApplies ? 1.0 : 0.3

            Repeater {
                model: card.presets
                delegate: Rectangle {
                    // Qt.colorEqual, not ===: AmbientLight.color comes back as
                    // a QColor and the preset is a string, so === is never true
                    // and no swatch would ever show as selected.
                    readonly property bool current:
                        Qt.colorEqual(AmbientLight.color, modelData)

                    width: (swatchRow.parent.width - swatchRow.spacing * 7) / 8
                    height: width
                    radius: width / 2
                    color: modelData
                    border.color: current ? "#ffffff" : Qt.rgba(1,1,1,0.18)
                    border.width: current ? 2 : 1

                    scale: current ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                    MouseArea {
                        anchors.fill: parent
                        enabled: card.live && AmbientLight.on && card.colorApplies
                        onClicked: AmbientLight.color = modelData
                    }
                }
            }
        }
    }
}
