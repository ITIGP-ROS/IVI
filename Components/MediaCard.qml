import QtQuick
import Qt5Compat.GraphicalEffects

Rectangle {
    id: card

    // —— Properties ——
    property alias cardWidth: card.width
    property alias cardHeight: card.height
    property alias cardRadius: card.radius
    property alias cardOpacity: card.opacity
    property alias cardIcon: icon.source
    property alias cardText: cardText.text
    property alias cardColSpacing: col.spacing

    property color cardBorderColor: "#50FFFFFF"
    property real  cardBorderWidth: 1
    property real  cardTextFontSize: 28
    property string cardTextFontFamily: "Arial"
    property color cardTextColor: "#ffffff"
    property real cardIconWidth: card.width / 1.8
    property real cardIconHeight: card.height / 1.8

    // Accent color for liquid glass highlights
    property color accentColor: "#D08831"

    signal cardClicked
    signal cardEntred
    signal cardExited

    width: cardWidth
    height: cardHeight
    radius: height * 0.06
    color: "#3D717E"
    border.color: cardBorderColor
    border.width: cardBorderWidth
    opacity: cardOpacity

    // Glass Layers
    Rectangle {
        id: glassBase
        anchors.fill: parent
        radius: parent.radius
        color: "#3D717E"
        border.width: 1
        border.color: "#50FFFFFF"
        visible: false
    }

    InnerShadow {
        id: innerShadow
        anchors.fill: glassBase
        source: glassBase
        horizontalOffset: -3
        verticalOffset: -3
        radius: 10
        samples: 20
        color: "#80FFFFFF"
        visible: false
    }

    DropShadow {
        anchors.fill: glassBase
        source: innerShadow
        horizontalOffset: 6
        verticalOffset: 6
        radius: 14
        samples: 28
        color: "#50000000"
    }

    // Hover Glow Border
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.color: card.accentColor
        border.width: 2
        opacity: hoverHandler.hovered ? 0.55 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // Top Accent Bar
    Rectangle {
        width: parent.width * 0.4
        height: 3
        radius: 2
        color: card.accentColor
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
        opacity: 0.85
    }

    // Content
    Column {
        id: col
        anchors.centerIn: parent
        spacing: parent.height * 0.06

        // Circular icon container
        Rectangle {
            width: parent.parent.height * 0.45
            height: width
            radius: width / 2
            color: Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.15)
            border.color: Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.5)
            border.width: 1
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
                id: icon
                anchors.centerIn: parent
                width: parent.width * 0.65
                height: parent.height * 0.65
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
        }

        Text {
            id: cardText
            color: card.cardTextColor
            font.pixelSize: card.cardTextFontSize
            font.family: card.cardTextFontFamily
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // —— Interaction ——
    HoverHandler { id: hoverHandler }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: card.cardClicked()
        onEntered: {
            card.cardEntred()
        }
        onExited: {
            card.cardExited()
        }
    }

    scale: hoverHandler.hovered ? 1.03 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutQuad
        }
    }
}