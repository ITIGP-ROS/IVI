import QtQuick

Rectangle{
    id: card

    property color first: '#ffa845'
    property color second: '#ff7654'
    property color third: '#ff4545'
    
    property alias cardWidth: card.width
    property alias cardHeight: card.height
    property alias cardRadius: card.radius
    property alias cardOpacity: card.opacity
    property alias cardIcon: icon.source
    property alias cardText: cardText.text
    property alias cardColSpacing: col.spacing

    // Qt doesn't support aliasing past one level deep
    property color cardBorderColor: '#ffac7c'
    property real  cardBorderWidth: 3
    property real  cardTextFontSize: 28
    property string cardTextFontFamily: "Arial"
    property color cardTextColor: '#252525'
    property real cardIconWidth: card.width / 1.8
    property real cardIconHeight: card.height / 1.8

    signal cardClicked
    signal cardEntred
    signal cardExited

    gradient: Gradient {
        GradientStop {position: 0.0; color: card.first }
        GradientStop {position: 0.5; color: card.second }
        GradientStop {position: 1.0; color: card.third }
    }

    border.color: cardBorderColor
    border.width: cardBorderWidth

    Column{
        id: col
        anchors.centerIn: parent
        spacing: parent.height / 20
        Image{
            id: icon
            anchors.horizontalCenter: parent.horizontalCenter
            fillMode: Image.PreserveAspectFit
            smooth: true
            width: card.cardIconWidth
            height: card.cardIconHeight
        }
        Text{
            id: cardText
            color: card.cardTextColor
            font.pixelSize: card.cardTextFontSize
            font.family: card.cardTextFontFamily
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
    MouseArea{
        anchors.fill: parent
        hoverEnabled: true
        onClicked: card.cardClicked()
        onEntered: card.cardEntred()
        onExited: card.cardExited()
    }
}