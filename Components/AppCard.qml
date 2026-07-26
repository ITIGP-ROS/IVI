import QtQuick
import QtQuick.Controls

Item {
    id: card

    property string title:       "App"
    property string subtitle:    ""
    property string emoji:       "📦"
    property color  accentColor: "#4fc3f7"
    property real   cardWidth:   220
    property real   cardHeight:  300

    signal clicked()

    width:  cardWidth
    height: cardHeight

    // Card body
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: cardHeight * 0.06
        color: "#101e36"
        border.color: Qt.rgba(
            card.accentColor.r,
            card.accentColor.g,
            card.accentColor.b,
            0.35
        )
        border.width: 1.5

        // Glow layer
        Rectangle {
            anchors.fill: parent
            radius: bg.radius
            color: "transparent"
            border.color: card.accentColor
            border.width: 2
            opacity: bg.glowOpacity
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }

        property real glowOpacity: 0.0

        Behavior on scale   { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        Behavior on opacity { NumberAnimation { duration: 150 } }

        // Top accent bar
        Rectangle {
            width: parent.width * 0.4
            height: 3
            radius: 2
            color: card.accentColor
            anchors { top: parent.top; topMargin: 0; horizontalCenter: parent.horizontalCenter }
            opacity: 0.85
        }

        // Card content
        Column {
            anchors.centerIn: parent
            spacing: cardHeight * 0.055

            // Big emoji icon
            Rectangle {
                width: cardHeight * 0.32
                height: cardHeight * 0.32
                radius: width / 2
                color: Qt.rgba(
                    card.accentColor.r,
                    card.accentColor.g,
                    card.accentColor.b,
                    0.12
                )
                border.color: Qt.rgba(
                    card.accentColor.r,
                    card.accentColor.g,
                    card.accentColor.b,
                    0.4
                )
                border.width: 1
                anchors.horizontalCenter: parent.horizontalCenter

                Text {
                    anchors.centerIn: parent
                    text: card.emoji
                    font.pointSize: cardHeight * 0.15
                }
            }

            // Title
            Text {
                text: card.title
                color: "#ffffff"
                font { bold: true; family: "Arial"; pointSize: cardHeight * 0.065 }
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Subtitle
            Text {
                text: card.subtitle
                color: "#8899bb"
                font { family: "Arial"; pointSize: cardHeight * 0.045 }
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                width: card.cardWidth * 0.75
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            propagateComposedEvents: true
            onEntered: { bg.scale = 1.03; bg.glowOpacity = 0.55 }
            onExited:  { bg.scale = 1.0;  bg.glowOpacity = 0.0  }
            onClicked: {
                console.log("Application Card Clicked");
                card.clicked() 
            }
        }
    }
}
