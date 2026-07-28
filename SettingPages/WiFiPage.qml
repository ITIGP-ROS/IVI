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
                keyboard.revealText = false
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
            var conn = WifiManager.connectedSsid

            // Reconcile in place instead of clear()+append(). A rebuild destroys
            // every delegate, which snaps the ListView back to the top — and with
            // a scan every 3s that made the list impossible to scroll through.
            for (var i = networkListModel.count - 1; i >= 0; i--) {
                if (networks.indexOf(networkListModel.get(i).name) === -1)
                    networkListModel.remove(i)
            }
            for (var j = 0; j < networks.length; j++) {
                var at = -1
                for (var k = 0; k < networkListModel.count; k++) {
                    if (networkListModel.get(k).name === networks[j]) { at = k; break }
                }
                if (at === -1)
                    networkListModel.append({ "name": networks[j],
                                              "connected": networks[j] === conn })
                else
                    networkListModel.setProperty(at, "connected", networks[j] === conn)
            }
            promoteConnected()
        }
        function onScanFailed(reason) {
            isScanning = false
            logStatus("scan failed: " + reason)
        }
        function onConnectSuccess(ssid) {
            logStatus("connected to " + ssid)
            for (var i = 0; i < networkListModel.count; i++) {
                networkListModel.setProperty(i, "connected",
                    networkListModel.get(i).name === ssid)
            }
            promoteConnected()
        }
        function onPasswordRequired(ssid) {
            passwordPopupSsid.text = ssid
            keyboard.revealText = false
            passwordPopup.open()
        }
        function onConnectedSsidChanged(ssid) {
            for (var i = 0; i < networkListModel.count; i++) {
                networkListModel.setProperty(i, "connected",
                    networkListModel.get(i).name === ssid)
            }
            promoteConnected()
            if (ssid === "")
                logStatus("disconnected")
        }
        function onForgetSuccess(ssid) {
            logStatus("forgotten: " + ssid)
        }
        // Credential forwarding is a background handoff to the vehicle host —
        // deliberately silent on screen. Watch the [wifi-cred] log lines instead.

        function onConnectFailed(reason) {
            logStatus(reason)
            // If it failed, re-prompt for password after a short delay
            retryTimer.pendingSsid = reason.replace("Wrong password or could not connect to: ", "")
            retryTimer.start()
        }
    }

    property bool isScanning: false
    ListModel { id: networkListModel }

    // Keep the connected network pinned to the top. Only moves when it is not
    // already first, so a routine rescan never disturbs the scroll position.
    function promoteConnected() {
        var conn = WifiManager.connectedSsid
        if (conn === "") return
        for (var i = 0; i < networkListModel.count; i++) {
            if (networkListModel.get(i).name === conn) {
                if (i > 0) networkListModel.move(i, 0, 1)
                return
            }
        }
    }

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
            Behavior on color { ColorAnimation { duration: 300; easing.type: Easing.InOutQuad } }
            Behavior on border.color { ColorAnimation { duration: 300; easing.type: Easing.InOutQuad } }

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

        // Section toolbar: label + live count + hidden-network entry
        Item {
            width: parent.width
            height: wifiPage.height * 0.055
            visible: wifiSwitch.checked

            Text {
                id: sectionLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Available Networks"
                color: "#e7f1ef"
                font.pixelSize: wifiPage.height * 0.028
                font.bold: true
                font.family: "Arial"
            }

            Rectangle {
                anchors.left: sectionLabel.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(height, countText.implicitWidth + 14)
                height: wifiPage.height * 0.034
                radius: height / 2
                color: "#10475E"
                border.color: "#3D717E"
                border.width: 1
                visible: networkListModel.count > 0

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: networkListModel.count
                    color: "#D08831"
                    font.pixelSize: parent.height * 0.55
                    font.bold: true
                    font.family: "Arial"
                }
            }

            Rectangle {
                id: hiddenBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: hiddenBtnRow.implicitWidth + wifiPage.width * 0.04
                height: parent.height
                radius: height / 2
                color: hiddenBtnArea.containsMouse ? "#964405" : "#5A3211"
                border.color: "#D08831"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    id: hiddenBtnRow
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "+"
                        color: "#D08831"
                        font.pixelSize: hiddenBtn.height * 0.52
                        font.bold: true
                        font.family: "Arial"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Hidden Network"
                        color: "#e7f1ef"
                        font.pixelSize: hiddenBtn.height * 0.38
                        font.bold: true
                        font.family: "Arial"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: hiddenBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: openHiddenDialog()
                }
            }
        }

        // Network List
        Rectangle {
            width: parent.width
            height: wifiPage.height * 0.50
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
                    Behavior on border.color { ColorAnimation { duration: 300 } }

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

    // Hidden Network Dialog
    // The keyboard is a single-target component, so it is re-pointed between the
    // SSID and password fields as you tap them.
    property string hiddenField: "ssid"
    property string hiddenSecurity: "wpa-psk"
    // With no toast, a rejected Enter would be silent — mark the offending field
    // instead so the dialog is not a dead end.
    property string hiddenInvalid: ""

    function openHiddenDialog() {
        hiddenSsidField.text = ""
        hiddenPassField.text = ""
        hiddenSecurity = "wpa-psk"
        hiddenInvalid = ""
        hiddenKeyboard.revealText = false
        focusHiddenField("ssid")
        hiddenPopup.open()
    }

    function focusHiddenField(which) {
        hiddenField = which
        hiddenInvalid = ""
        if (which === "ssid") {
            hiddenKeyboard.passwordMode = false
            hiddenKeyboard.maxLength = 32
            hiddenKeyboard.targetItem = hiddenSsidField
            hiddenKeyboard.targetText = hiddenSsidField.text
        } else {
            hiddenKeyboard.passwordMode = true
            hiddenKeyboard.maxLength = 64
            hiddenKeyboard.targetItem = hiddenPassField
            hiddenKeyboard.targetText = hiddenPassField.text
        }
    }

    function submitHidden() {
        var ssid = hiddenSsidField.text
        var pass = hiddenPassField.text
        if (ssid.length === 0) {
            logStatus("hidden network: name is empty")
            focusHiddenField("ssid")
            hiddenInvalid = "ssid"
            return
        }
        if (hiddenSecurity !== "open" && pass.length < 8) {
            logStatus("hidden network: password under 8 characters")
            focusHiddenField("pass")
            hiddenInvalid = "pass"
            return
        }
        WifiManager.connectToHiddenNetwork(ssid, pass, hiddenSecurity)
        hiddenPopup.close()
    }

    Popup {
        id: hiddenPopup
        width: parent.width * 0.9
        height: parent.height * 0.88
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape

        // Dim the page behind the dialog — black at 0.6 leaves it showing at ~0.4.
        // (A MultiEffect blur is the nicer option and works on real GPU hardware;
        // see the note in git history before swapping it in.)
        Overlay.modal: Rectangle {
            color: "#000000"
            opacity: 0.6
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        background: Rectangle {
            color: "#082839"
            radius: 18
            border.color: "#D08831"
            border.width: 2
        }

        Column {
            anchors.fill: parent
            anchors.margins: wifiPage.height * 0.022
            spacing: wifiPage.height * 0.016

            // Title
            Item {
                width: parent.width
                height: wifiPage.height * 0.05

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add Hidden Network"
                    color: "#D08831"
                    font.pixelSize: wifiPage.height * 0.038
                    font.bold: true
                    font.family: "Arial"
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Not broadcast — enter the name exactly"
                    color: "#3D717E"
                    font.pixelSize: wifiPage.height * 0.022
                    font.family: "Arial"
                }
            }

            // SSID + password, side by side
            Row {
                width: parent.width
                spacing: parent.width * 0.02

                Rectangle {
                    id: ssidCard
                    width: (parent.width - parent.spacing) / 2
                    height: wifiPage.height * 0.075
                    radius: 10
                    color: "#10475E"
                    border.color: wifiPage.hiddenInvalid === "ssid" ? "#ff4444"
                                  : (wifiPage.hiddenField === "ssid" ? "#D08831" : "#3D717E")
                    border.width: wifiPage.hiddenField === "ssid" ? 2 : 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28
                        spacing: 2

                        Text {
                            text: "Network Name (SSID)"
                            color: "#3D717E"
                            font.pixelSize: wifiPage.height * 0.02
                            font.family: "Arial"
                        }
                        Text {
                            text: hiddenSsidField.text.length ? hiddenSsidField.text
                                                              : "Tap to enter"
                            color: hiddenSsidField.text.length ? "#e7f1ef" : "#2b5a68"
                            font.pixelSize: wifiPage.height * 0.028
                            font.bold: true
                            font.family: "Arial"
                            width: parent.width
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: focusHiddenField("ssid")
                    }
                }

                Rectangle {
                    id: passCard
                    width: (parent.width - parent.spacing) / 2
                    height: wifiPage.height * 0.075
                    radius: 10
                    color: "#10475E"
                    opacity: wifiPage.hiddenSecurity === "open" ? 0.4 : 1.0
                    border.color: wifiPage.hiddenInvalid === "pass" ? "#ff4444"
                                  : (wifiPage.hiddenField === "pass" ? "#D08831" : "#3D717E")
                    border.width: wifiPage.hiddenField === "pass" ? 2 : 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28
                        spacing: 2

                        Text {
                            text: wifiPage.hiddenSecurity === "open" ? "Password (not needed)"
                                                                     : "Password"
                            color: "#3D717E"
                            font.pixelSize: wifiPage.height * 0.02
                            font.family: "Arial"
                        }
                        Text {
                            text: hiddenPassField.text.length
                                  ? (hiddenKeyboard.revealText
                                     ? hiddenPassField.text
                                     : hiddenPassField.text.replace(/./g, "•"))
                                  : "Tap to enter"
                            color: hiddenPassField.text.length ? "#e7f1ef" : "#2b5a68"
                            font.pixelSize: wifiPage.height * 0.028
                            font.bold: true
                            font.family: "Arial"
                            width: parent.width
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: wifiPage.hiddenSecurity !== "open"
                        onClicked: focusHiddenField("pass")
                    }
                }
            }

            // Security selector
            Row {
                width: parent.width
                height: wifiPage.height * 0.05
                spacing: 10

                Text {
                    text: "Security"
                    color: "#3D717E"
                    font.pixelSize: wifiPage.height * 0.024
                    font.family: "Arial"
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    width: wifiPage.width * 0.16
                    height: parent.height * 0.8
                    radius: height / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: wifiPage.hiddenSecurity === "wpa-psk" ? "#5A3211" : "#10475E"
                    border.color: wifiPage.hiddenSecurity === "wpa-psk" ? "#D08831" : "#3D717E"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "WPA / WPA2"
                        color: wifiPage.hiddenSecurity === "wpa-psk" ? "#D08831" : "#e7f1ef"
                        font.pixelSize: parent.height * 0.42
                        font.bold: true
                        font.family: "Arial"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            wifiPage.hiddenSecurity = "wpa-psk"
                            focusHiddenField("pass")
                        }
                    }
                }

                Rectangle {
                    width: wifiPage.width * 0.10
                    height: parent.height * 0.8
                    radius: height / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: wifiPage.hiddenSecurity === "open" ? "#5A3211" : "#10475E"
                    border.color: wifiPage.hiddenSecurity === "open" ? "#D08831" : "#3D717E"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Open"
                        color: wifiPage.hiddenSecurity === "open" ? "#D08831" : "#e7f1ef"
                        font.pixelSize: parent.height * 0.42
                        font.bold: true
                        font.family: "Arial"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            wifiPage.hiddenSecurity = "open"
                            // The password field is inert now — keep typing on the name
                            focusHiddenField("ssid")
                        }
                    }
                }
            }

            // Backing fields — the keyboard writes into whichever is targeted
            TextInput { id: hiddenSsidField; visible: false }
            TextInput { id: hiddenPassField; visible: false; echoMode: TextInput.Password }

            VirtualKeyboard {
                id: hiddenKeyboard
                width: parent.width
                targetItem: hiddenSsidField

                // Enter advances name -> password, then submits
                onAccepted: {
                    if (wifiPage.hiddenField === "ssid"
                        && hiddenSsidField.text.length > 0
                        && wifiPage.hiddenSecurity !== "open")
                        focusHiddenField("pass")
                    else
                        submitHidden()
                }
                onCancelled: hiddenPopup.close()
            }
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

        Overlay.modal: Rectangle {
            color: "#000000"
            opacity: 0.6
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }

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
                        // The counter below already turns red under 8 characters
                        logStatus("password under 8 characters")
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
    
    // No on-screen status messages by design — connection state is already shown
    // by the connected chip and the row highlight. Detail goes to the log only.
    function logStatus(message) {
        console.log("[wifi-ui] " + message)
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