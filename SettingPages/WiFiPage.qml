import QtQuick
import QtQuick.Controls

Rectangle {
    id: wifiPage
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    color: "transparent"
    required property StackView stackView

    Timer {
        id: retryTimer
        interval: 1500
        property string pendingSsid: ""
        onTriggered: {
            if (pendingSsid !== "") {
                passwordPopupSsid.text = pendingSsid
                passwordPopup.open()
                pendingSsid = ""
            }
        }
    }

    // Background
    Rectangle {
        z: -1
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
    }

    // Backend Connections 
    Connections {
        target: WifiManager

        function onWifiEnabledChanged(enabled) {
            wifiSwitch.checked = enabled
            if (enabled && networkListModel.count === 0)
                WifiManager.scanNetworks()
        }
        function onScanStarted() {
            isScanning = true
        }
        function onScanFinished(networks) {
            isScanning = false
            networkListModel.clear()
            for (var i = 0; i < networks.length; i++)
                networkListModel.append({ "name": networks[i], "connected": false })
            var conn = WifiManager.connectedSsid
            for (var j = 0; j < networkListModel.count; j++) {
                if (networkListModel.get(j).name === conn)
                    networkListModel.setProperty(j, "connected", true)
            }
        }
        function onScanFailed(reason) {
            isScanning = false
            showToast("Scan failed: " + reason, true)
        }
        function onConnectSuccess(ssid) {
            showToast("Connected to " + ssid, false)
            for (var i = 0; i < networkListModel.count; i++) {
                networkListModel.setProperty(i, "connected",
                    networkListModel.get(i).name === ssid)
            }
        }
        function onPasswordRequired(ssid) {
            passwordPopupSsid.text = ssid
            passwordPopup.open()
        }
        function onConnectedSsidChanged(ssid) {
            for (var i = 0; i < networkListModel.count; i++) {
                networkListModel.setProperty(i, "connected",
                    networkListModel.get(i).name === ssid)
            }
            if (ssid === "")
                showToast("Disconnected", false)
        }
        function onForgetSuccess(ssid) {
            showToast("Forgotten: " + ssid, false)
        }

        function onConnectFailed(reason) {
            showToast(reason, true)
            // If it failed, re-prompt for password after a short delay
            retryTimer.pendingSsid = reason.replace("Wrong password or could not connect to: ", "")
            retryTimer.start()
        }
    }

    property bool isScanning: false
    ListModel { id: networkListModel }

    // Auto-scan timer every 3 seconds when WiFi is on
    Timer {
        id: scanTimer
        interval: 3000
        running: wifiSwitch.checked
        repeat: true
        onTriggered: {
            if (!isScanning)
                WifiManager.scanNetworks()
        }
    }

    // Initial scan on startup
    Component.onCompleted: {
        if(WifiManager.wifiEnabled)
            WifiManager.scanNetworks()
    }

    // Main Layout
    Column {
        id: mainCol
        anchors.fill: parent
        anchors.margins: wifiPage.width * 0.08
        anchors.topMargin: wifiPage.height * 0.09
        anchors.bottomMargin: wifiPage.height * 0.05
        spacing: wifiPage.height * 0.02

        // Header Row: Title + WiFi Toggle
        Row {
            width: parent.width
            height: wifiPage.height / 14

            Text {
                id: wifiTitle
                text: "Wi-Fi"
                font.pixelSize: wifiPage.width / 28
                color: "#e7f1ef"
                font.bold: true
                font.family: "Arial"
                anchors.verticalCenter: parent.verticalCenter
            }

            Item { width: parent.width - wifiTitle.width - wifiSwitchBg.width; height: 1 }

            Rectangle {
                id: wifiSwitchBg
                width: wifiPage.width / 14
                height: wifiPage.height / 22
                radius: height / 2
                color: wifiSwitch.checked ? "#D08831" : "#3D717E"
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 200 } }

                Rectangle {
                    id: wifiKnob
                    width: parent.height - 4
                    height: width
                    radius: width / 2
                    color: "#e7f1ef"
                    anchors.verticalCenter: parent.verticalCenter
                    x: wifiSwitch.checked ? parent.width - width - 2 : 2
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
                }

                MouseArea {
                    id: wifiSwitch
                    property bool checked: WifiManager.wifiEnabled
                    anchors.fill: parent
                    onClicked: WifiManager.wifiEnabled = !checked
                }
            }
        }

        // Divider
        Rectangle {
            width: parent.width
            height: 1
            color: "#3D717E"
            opacity: 0.5
        }

        // Connected Status Chip
        Rectangle {
            width: parent.width
            height: wifiPage.height / 16
            radius: height / 2
            color: WifiManager.connectedSsid !== "" ? "#5A3211" : "transparent"
            border.color: WifiManager.connectedSsid !== "" ? "#D08831" : "transparent"
            border.width: 1
            visible: wifiSwitch.checked

            Row {
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: "#00ffaa"
                    anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on opacity {
                        running: WifiManager.connectedSsid !== ""
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    text: WifiManager.connectedSsid !== "" ? "Connected: " + WifiManager.connectedSsid : "Not connected"
                    color: WifiManager.connectedSsid !== "" ? "#D08831" : "#3D717E"
                    font.pixelSize: wifiPage.height * 0.03
                    font.family: "Arial"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Network List
        Rectangle {
            width: parent.width
            height: wifiPage.height * 0.55
            radius: wifiPage.height * 0.02
            color: "#082839"
            border.color: "#3D717E"
            border.width: 1
            visible: wifiSwitch.checked

            // Scanning overlay
            Rectangle {
                anchors.fill: parent
                color: "#082839"
                opacity: 0.9
                visible: isScanning && networkListModel.count === 0
                radius: parent.radius
                z: 5

                Column {
                    anchors.centerIn: parent
                    spacing: 12

                    Rectangle {
                        width: 40; height: 40
                        color: "transparent"
                        border.color: "#D08831"
                        border.width: 3
                        radius: width / 2
                        anchors.horizontalCenter: parent.horizontalCenter

                        Rectangle {
                            width: 6; height: 6
                            color: "#082839"
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        RotationAnimation on rotation {
                            running: parent.visible
                            loops: Animation.Infinite
                            duration: 800
                            from: 0; to: 360
                        }
                    }

                    Text {
                        text: "Scanning..."
                        color: "#D08831"
                        font.pixelSize: wifiPage.height * 0.025
                        font.family: "Arial"
                        font.bold: true
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            // Empty state (when no networks and not scanning)
            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: networkListModel.count === 0 && !isScanning

                Text {
                    text: "📡"
                    font.pixelSize: wifiPage.width / 20
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "No networks found"
                    color: "#3D717E"
                    font.pixelSize: wifiPage.height * 0.025
                    font.family: "Arial"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            ListView {
                id: networkListView
                anchors.fill: parent
                anchors.margins: 10
                anchors.rightMargin: 18
                clip: true
                model: networkListModel
                spacing: 6

                ScrollBar.vertical: ScrollBar {
                    width: 6
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: parent.pressed ? "#964405" : "#D08831"
                        opacity: 0.8
                    }
                    background: Rectangle {
                        implicitWidth: 6
                        color: "#082839"
                        radius: 3
                        opacity: 0.3
                    }
                }

                delegate: Rectangle {
                    id: netRow
                    required property string name
                    required property bool connected
                    width: networkListView.width - 8
                    height: wifiPage.height / 12
                    radius: height / 4
                    color: rowHover.containsMouse ? "#964405" : (connected ? "#5A3211" : "#10475E")
                    border.color: connected ? "#D08831" : "#3D717E"
                    border.width: connected ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: parent.width * 0.04
                        anchors.rightMargin: parent.width * 0.04
                        spacing: parent.width * 0.03

                        Text {
                            text: connected ? "📶" : "📡"
                            font.pixelSize: parent.parent.height * 0.4
                            color: connected ? "#D08831" : "#e7f1ef"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: netRow.name
                            font.pixelSize: parent.parent.height * 0.38
                            color: connected ? "#D08831" : "#e7f1ef"
                            font.bold: true
                            font.family: "Arial"
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                                   - (connected ? disconnectBtn.width * 2 + 5 : connectBtn.width)
                                   - parent.parent.height * 0.4
                                   - parent.spacing * 2
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: connectBtn
                            visible: !netRow.connected
                            width: wifiPage.width * 0.16
                            height: parent.parent.height * 0.5
                            radius: height / 3
                            color: btnArea.containsMouse ? "#964405" : "#5A3211"
                            border.color: "#D08831"
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: "Connect"
                                font.pixelSize: parent.height * 0.5
                                color: "#e7f1ef"
                                font.bold: true
                                font.family: "Arial"
                            }

                            MouseArea {
                                id: btnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: WifiManager.connectToSelectedNetwork(netRow.name)
                            }
                        }

                        Rectangle {
                            id: forgetBtn
                            visible: netRow.connected
                            width: wifiPage.width * 0.14
                            height: parent.parent.height * 0.5
                            radius: height / 3
                            color: forgetArea.containsMouse ? "#774400" : "#3d2200"
                            anchors.verticalCenter: parent.verticalCenter
                            border.color: "#D08831"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: "Forget"
                                font.pixelSize: parent.height * 0.45
                                color: "#D08831"
                                font.bold: true
                                font.family: "Arial"
                            }

                            MouseArea {
                                id: forgetArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    WifiManager.forgetNetwork(netRow.name)
                                    WifiManager.disconnectFromNetwork()
                                }
                            }
                        }

                        Rectangle {
                            id: disconnectBtn
                            visible: netRow.connected
                            width: wifiPage.width * 0.16
                            height: parent.parent.height * 0.5
                            radius: height / 3
                            color: discArea.containsMouse ? "#ff4444" : "#aa2222"
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: "Disconnect"
                                font.pixelSize: parent.height * 0.5
                                color: "#ffffff"
                                font.bold: true
                                font.family: "Arial"
                            }

                            MouseArea {
                                id: discArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: WifiManager.disconnectFromNetwork()
                            }
                        }
                    }

                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        propagateComposedEvents: true
                        z: -1
                        onClicked: (mouse) => mouse.accepted = false
                    }
                }
            }
        }

        // Spacer to push Back button down
        Item {
            width: parent.width
            height: wifiPage.height * 0.05
        }
    }

// Password Popup with Virtual Keyboard
    Popup {
        id: passwordPopup
        width: parent.width * 0.85
        height: parent.height * 0.75
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: "#082839"
            radius: 16
            border.color: "#D08831"
            border.width: 2
        }

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            // Header
            Text {
                id: passwordPopupSsid
                font.pixelSize: wifiPage.height * 0.04
                color: "#D08831"
                font.bold: true
                font.family: "Arial"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "Enter Wi-Fi Password"
                font.pixelSize: wifiPage.height * 0.025
                color: "#3D717E"
                font.family: "Arial"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Hidden TextInput (for backend compatibility, but invisible)
            TextInput {
                id: popupPassField
                visible: false
                text: keyboard.targetText
                echoMode: TextInput.Password
            }

            // Virtual Keyboard
            VirtualKeyboard {
                id: keyboard
                width: parent.width
                targetItem: popupPassField
                passwordMode: true
                maxLength: 64

                onAccepted: {
                    if (popupPassField.text.length >= 8) {
                        WifiManager.connectToNetwork(passwordPopupSsid.text, popupPassField.text)
                        keyboard.clear()
                        passwordPopup.close()
                    } else {
                        showToast("Password must be 8+ characters", true)
                    }
                }

                onCancelled: {
                    keyboard.clear()
                    passwordPopup.close()
                }
            }

            // Password strength hint
            Text {
                text: popupPassField.text.length + " / 64 characters"
                color: popupPassField.text.length < 8 ? "#ff8a7a" : "#3D717E"
                font.pixelSize: 14
                font.family: "Arial"
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
    
    // Status Toast
    Rectangle {
        id: statusToast
        width: parent.width * 0.4
        height: parent.height * 0.07
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.085
        radius: height / 2
        color: statusToast.isError ? "#3d0a00" : "#082839"
        border.color: statusToast.isError ? "#ff4444" : "#D08831"
        border.width: 1
        opacity: 0
        visible: opacity > 0
        z: 20
        property bool isError: false
        Behavior on opacity { NumberAnimation { duration: 400 } }

        Text {
            id: toastText
            anchors.centerIn: parent
            font.pixelSize: parent.height * 0.5
            color: statusToast.isError ? "#ff8a7a" : "#D08831"
            font.family: "Arial"
            font.bold: true
        }
        Timer {
            id: toastTimer
            interval: 3000
            onTriggered: statusToast.opacity = 0
        }
    }

    function showToast(message, isError) {
        toastText.text = message
        statusToast.isError = isError
        statusToast.opacity = 1
        toastTimer.restart()
    }

    // Back Button
    Rectangle {
        width: wifiPage.width / 8
        height: wifiPage.height / 16
        color: backBtnArea.containsMouse ? "#964405" : "#5A3211"
        radius: height / 4
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: parent.height * 0.04
        anchors.leftMargin: parent.width * 0.08
        border.color: "#D08831"
        border.width: 1
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            text: "Back"
            font.pixelSize: parent.height * 0.45
            color: "#e7f1ef"
            font.bold: true
            font.family: "Arial"
            anchors.centerIn: parent
        }

        MouseArea {
            id: backBtnArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: wifiPage.stackView.pop()
        }
    }
}