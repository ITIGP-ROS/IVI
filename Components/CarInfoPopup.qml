// CarInfoPopup.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: popupRoot
    anchors.fill: parent
    color: Qt.rgba(0.02, 0.04, 0.08, 0.85)   // slightly darker for better contrast
    z: 100

    signal closePopup()

    opacity: 0
    Behavior on opacity { NumberAnimation { duration: 200 } }
    Component.onCompleted: opacity = 1

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: popupRoot.closePopup()
    }

    // Card
    Rectangle {
        id: card
        width: 440
        height: 340
        anchors.centerIn: parent
        radius: 24
        color: "#0d1117"
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1

        // Subtle top accent
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 3
            radius: 2
            color: "#f79b55"
            opacity: 0.6
        }

        // Close X
        Rectangle {
            width: 32; height: 32; radius: 16
            anchors.top: parent.top; anchors.right: parent.right
            anchors.margins: 16
            color: closeMa.containsMouse ? Qt.rgba(1, 0.2, 0.2, 0.2) : "transparent"
            border.color: closeMa.containsMouse ? "#ff4444" : Qt.rgba(1, 1, 1, 0.15)
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "×"
                color: closeMa.containsMouse ? "#ff4444" : "#8899bb"
                font { pixelSize: 16; bold: true }
            }

            MouseArea {
                id: closeMa
                anchors.fill: parent
                hoverEnabled: true
                onClicked: popupRoot.closePopup()
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            anchors.topMargin: 36
            spacing: 0

            // Header row: small icon + text
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                Image {
                    source: "qrc:/assets/images/mercedes.png"
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.maximumWidth: 40
                    Layout.maximumHeight: 40
                    fillMode: Image.PreserveAspectFit
                }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Mercedes-Benz"
                        color: "#ffffff"
                        font { pixelSize: 20; bold: true; family: "Arial" }
                    }
                    Text {
                        text: "EQS 580 4MATIC"
                        color: "#f79b55"
                        font { pixelSize: 12; family: "Arial" }
                    }
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 20
                Layout.bottomMargin: 20
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }

            // Info grid — 2x3
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 40
                rowSpacing: 16

                Repeater {
                    model: [
                        { label: "VIN", value: "W1K2973XXXXXX" },
                        { label: "Software", value: "MBUX v2.3.1" },
                        { label: "Battery", value: "107.8 kWh" },
                        { label: "Range", value: "~680 km" },
                        { label: "Odometer", value: "12,450 km" },
                        { label: "Service", value: "Mar 2026" }
                    ]

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: modelData.label
                            color: "#6677aa"
                            font { pixelSize: 11; family: "Arial" }
                        }
                        Text {
                            text: modelData.value
                            color: "#ffffff"
                            font { pixelSize: 13; bold: true; family: "Arial" }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // Status pill
            Rectangle {
                Layout.fillWidth: true
                height: 36
                radius: 10
                color: Qt.rgba(0.13, 0.81, 0.64, 0.1)
                border.color: "#21cfa4"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "● All Systems Operational"
                    color: "#21cfa4"
                    font { pixelSize: 12; bold: true; family: "Arial" }
                }
            }
        }
    }
}