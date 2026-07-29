import QtQuick
import QtQuick.Controls

Rectangle {
    id: btPage
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    color: "transparent"
    required property StackView stackView
    property bool updatingFromBackend: false

    property string connectingAddress:    ""
    property string disconnectingAddress: ""
    property var    connectedAddresses:   []

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
        target: BluetoothManager

        function onBluetoothEnabledChanged(enabled) {
            btPage.updatingFromBackend = true
            btSwitch.checked = enabled
            btPage.updatingFromBackend = false
            if (enabled && deviceListModel.count === 0)
                BluetoothManager.scanDevices()
        }
        function onScanStarted() {
            isScanning = true
        }
        function onScanFinished(devices) {
            isScanning = false
            var seenInScan = {}

            // devices is now a list of objects, not "name|addr|conn" strings —
            // a device named "Ehab | iPhone" used to corrupt the parse.
            for (var i = 0; i < devices.length; i++) {
                var d      = devices[i]
                var name   = d.name
                var addr   = d.address
                var isConn = d.connected
                seenInScan[addr] = true

                // Update in place if known (prevents delegate destruction)
                var exists = false
                for (var j = 0; j < deviceListModel.count; j++) {
                    if (deviceListModel.get(j).address === addr) {
                        exists = true
                        deviceListModel.setProperty(j, "name", name)
                        deviceListModel.setProperty(j, "paired", d.paired)
                        deviceListModel.setProperty(j, "rssi", d.rssi)
                        break
                    }
                }
                if (!exists) {
                    deviceListModel.append({ "name": name, "address": addr,
                                             "paired": d.paired, "rssi": d.rssi })
                }

                // Only ADD connected devices we didn't know about
                if (isConn && btPage.connectedAddresses.indexOf(addr) === -1) {
                    var addList = btPage.connectedAddresses.slice()
                    addList.push(addr)
                    btPage.connectedAddresses = addList
                }
            }

            // Remove from model only if idle (not connected / not in-progress)
            for (var k = deviceListModel.count - 1; k >= 0; k--) {
                var item = deviceListModel.get(k)
                if (!seenInScan[item.address]) {
                    var stillConnected = btPage.connectedAddresses.indexOf(item.address) !== -1
                    var inProgress     = (item.address === btPage.connectingAddress) ||
                                         (item.address === btPage.disconnectingAddress)
                    if (!stillConnected && !inProgress) {
                        deviceListModel.remove(k)
                    }
                }
            }
        }
        function onScanFailed(reason) {
            isScanning = false
            logStatus(reason)
        }
        function onPairSuccess(name) {
            btPage.connectingAddress = ""
            logStatus("Paired with " + name)
            BluetoothManager.scanDevices()      // refresh paired flags
        }
        function onPairFailed(reason) {
            btPage.connectingAddress = ""
            logStatus("Pair failed: " + reason)
        }

        function onPairingConfirmationRequested(deviceName, passkey) {
            pairingPopup.deviceName = deviceName
            pairingPopup.passkey    = passkey
            pairingPopup.open()
        }
        function onPairingPromptDismissed() {
            pairingPopup.close()
        }
        function onAdapterPresentChanged(present) {
            if (!present) {
                deviceListModel.clear()
                btPage.connectedAddresses   = []
                btPage.connectingAddress    = ""
                btPage.disconnectingAddress = ""
                logStatus("Bluetooth adapter removed")
            }
        }
        function onDiscoveringChanged(active) {
            btPage.isScanning = active
        }
        function onPowerChangeFailed(reason) {
            // Snap the toggle back — the adapter never changed state.
            btPage.updatingFromBackend = true
            btSwitch.checked = BluetoothManager.bluetoothEnabled
            btPage.updatingFromBackend = false
            logStatus("Power change failed: " + reason)
        }

        function onDeviceConnectionChanged(address, connected) {
            var list = btPage.connectedAddresses.slice()
            var idx  = list.indexOf(address)
            if (connected && idx === -1)
                list.push(address)
            else if (!connected && idx !== -1)
                list.splice(idx, 1)
            btPage.connectedAddresses = list

            if (address === btPage.connectingAddress)
                btPage.connectingAddress = ""
            if (address === btPage.disconnectingAddress)
                btPage.disconnectingAddress = ""
        }

        function onConnectSuccess(name) {
            var list = btPage.connectedAddresses.slice()
            if (list.indexOf(btPage.connectingAddress) === -1)
                list.push(btPage.connectingAddress)
            btPage.connectedAddresses = list
            btPage.connectingAddress  = ""
            logStatus("Connected to " + name)
        }
        function onConnectFailed(reason) {
            btPage.connectingAddress = ""
            logStatus(reason)
        }
        function onDisconnectSuccess(name) {
            // Safety cleanup in case onDeviceConnectionChanged was missed
            var list = btPage.connectedAddresses.slice()
            var idx  = list.indexOf(btPage.disconnectingAddress)
            if (idx !== -1)
                list.splice(idx, 1)
            btPage.connectedAddresses = list

            btPage.disconnectingAddress = ""
            logStatus("Disconnected from " + name)
        }
        function onDisconnectFailed(reason) {
            btPage.disconnectingAddress = ""
            logStatus("Disconnect failed: " + reason)
        }
    }

    property bool isScanning: false
    ListModel { id: deviceListModel }

    // Discovery is deliberately NOT on a repeating timer. Bluetooth inquiry
    // starves the ACL link, which audibly breaks up A2DP playback, so the radio
    // only scans when the driver asks. One scan on entry, then the Scan button.
    Component.onCompleted: {
        if (BluetoothManager.bluetoothEnabled)
            BluetoothManager.scanDevices()
    }

    // Leaving the page must stop the radio; otherwise a 6s inquiry keeps running
    // against whatever is playing.
    Component.onDestruction: BluetoothManager.stopScan()

    // Main Layout 
    Column {
        id: btPageCol
        anchors.fill: parent
        anchors.margins: btPage.width * 0.08
        anchors.topMargin: btPage.height * 0.09
        anchors.bottomMargin: btPage.height * 0.05
        spacing: btPage.height * 0.02

        // Header Row: Title + BT Toggle 
        Row {
            width: parent.width
            height: btPage.height / 14

            Text {
                id: btTitle
                text: "Bluetooth"
                font.pixelSize: btPage.width / 28
                color: "#e7f1ef"
                font.bold: true
                font.family: "Arial"
                anchors.verticalCenter: parent.verticalCenter
            }

            Item { width: parent.width - btTitle.width - btSwitchBg.width; height: 1 }

            Rectangle {
                id: btSwitchBg
                width: btPage.width / 14
                height: btPage.height / 22
                radius: height / 2
                color: btSwitch.checked ? "#D08831" : "#3D717E"
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 200 } }

                Rectangle {
                    id: btKnob
                    width: parent.height - 4
                    height: width
                    radius: width / 2
                    color: "#e7f1ef"
                    anchors.verticalCenter: parent.verticalCenter
                    x: btSwitch.checked ? parent.width - width - 2 : 2
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
                }

                MouseArea {
                    id: btSwitch
                    property bool checked: BluetoothManager.bluetoothEnabled
                    anchors.fill: parent
                    onClicked: {
                        if (!btPage.updatingFromBackend)
                            BluetoothManager.bluetoothEnabled = !checked
                    }
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
            height: btPage.height / 16
            radius: height / 2
            color: btPage.connectedAddresses.length > 0 ? "#5A3211" : "transparent"
            border.color: btPage.connectedAddresses.length > 0 ? "#D08831" : "transparent"
            border.width: 1
            visible: btSwitch.checked

            Row {
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: "#00ffaa"
                    anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on opacity {
                        running: btPage.connectedAddresses.length > 0
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    text: btPage.connectedAddresses.length > 0 ?  "Device connected" : "Not connected"
                    color: btPage.connectedAddresses.length > 0 ? "#D08831" : "#3D717E"
                    font.pixelSize: btPage.height * 0.03
                    font.family: "Arial"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Device List 
        // Section toolbar: label + count + manual scan
        Item {
            width: parent.width
            height: btPage.height * 0.055
            visible: btSwitch.checked

            Text {
                id: sectionLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Devices"
                color: "#e7f1ef"
                font.pixelSize: btPage.height * 0.028
                font.bold: true
                font.family: "Arial"
            }

            Rectangle {
                anchors.left: sectionLabel.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(height, countText.implicitWidth + 14)
                height: btPage.height * 0.034
                radius: height / 2
                color: "#10475E"
                border.color: "#3D717E"
                border.width: 1
                visible: deviceListModel.count > 0

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: deviceListModel.count
                    color: "#D08831"
                    font.pixelSize: parent.height * 0.55
                    font.bold: true
                    font.family: "Arial"
                }
            }

            Rectangle {
                id: scanBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: scanBtnText.implicitWidth + btPage.width * 0.05
                height: parent.height
                radius: height / 2
                color: !enabled ? "#1a3a4c"
                                : (scanBtnArea.containsMouse ? "#964405" : "#5A3211")
                border.color: enabled ? "#D08831" : "#3D717E"
                border.width: 1
                enabled: !btPage.isScanning
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    id: scanBtnText
                    anchors.centerIn: parent
                    text: btPage.isScanning ? "Scanning..." : "Scan"
                    color: scanBtn.enabled ? "#e7f1ef" : "#3D717E"
                    font.pixelSize: scanBtn.height * 0.38
                    font.bold: true
                    font.family: "Arial"
                }

                MouseArea {
                    id: scanBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: BluetoothManager.scanDevices()
                }
            }
        }

        Rectangle {
            width: parent.width
            height: btPage.height * 0.50
            radius: btPage.height * 0.02
            color: "#082839"
            border.color: "#3D717E"
            border.width: 1
            visible: btSwitch.checked

            //Scanning overlay
            Rectangle {
                anchors.fill: parent
                color: "#082839"
                opacity: 0.9
                visible: isScanning && deviceListModel.count === 0
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
                        font.pixelSize: btPage.height * 0.025
                        font.family: "Arial"
                        font.bold: true
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            // Empty state
            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: deviceListModel.count === 0 && !isScanning

                Text {
                    text: "🔵"
                    font.pixelSize: btPage.width / 20
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "No devices found"
                    color: "#3D717E"
                    font.pixelSize: btPage.height * 0.025
                    font.family: "Arial"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            ListView {
                id: deviceListView
                anchors.fill: parent
                anchors.margins: 10
                anchors.rightMargin: 18
                clip: true
                model: deviceListModel
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
                    id: devRow
                    required property string name
                    required property string address
                    required property bool   paired
                    width: deviceListView.width - 8
                    height: btPage.height / 12
                    radius: height / 4
                    color: rowHover.containsMouse ? "#964405" : (isConnected ? "#5A3211" : "#10475E")
                    border.color: isConnected ? "#D08831" : "#3D717E"
                    border.width: isConnected ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    property bool isConnecting:    address === btPage.connectingAddress
                    property bool isDisconnecting: address === btPage.disconnectingAddress
                    property bool isConnected:     btPage.connectedAddresses.indexOf(address) !== -1

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: parent.width * 0.04
                        anchors.rightMargin: parent.width * 0.04
                        spacing: parent.width * 0.03

                        Text {
                            text: devRow.isConnected ? "🔵" : "⬡"
                            font.pixelSize: parent.parent.height * 0.4
                            color: devRow.isConnected ? "#D08831" : "#e7f1ef"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                                   - actionBtn.width
                                   - parent.parent.height * 0.4
                                   - parent.spacing * 2
                            spacing: 2

                            Text {
                                text: devRow.name
                                font.pixelSize: parent.parent.parent.height * 0.32
                                color: devRow.isConnected ? "#D08831" : "#e7f1ef"
                                font.bold: true
                                font.family: "Arial"
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: devRow.address
                                font.pixelSize: parent.parent.parent.height * 0.22
                                color: "#3D717E"
                                font.family: "Arial"
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        Rectangle {
                            id: actionBtn
                            width: btPage.width * 0.16
                            height: parent.parent.height * 0.5
                            radius: height / 3
                            anchors.verticalCenter: parent.verticalCenter

                            color: {
                                if (devRow.isDisconnecting) return "#1a3a5c"
                                if (devRow.isConnected)
                                    return connArea.containsMouse ? "#ff4444" : "#aa2222" 
                                if (devRow.isConnecting) return "#1a4a7a"
                                return connArea.containsMouse ? "#964405" : "#5A3211"
                            }
                            border.color: devRow.isConnected ? "#ff4444" : "#D08831"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    if (devRow.isDisconnecting) return "..."
                                    if (devRow.isConnecting)    return "..."
                                    if (devRow.isConnected)     return "Disconnect"
                                    return devRow.paired ? "Connect" : "Pair"
                                }
                                font.pixelSize: parent.height * 0.5
                                color: "#ffffff"
                                font.bold: true
                                font.family: "Arial"
                            }

                            MouseArea {
                                id: connArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !devRow.isConnecting && !devRow.isDisconnecting
                                onClicked: {
                                    if (devRow.isConnected) {
                                        btPage.disconnectingAddress = devRow.address
                                        BluetoothManager.disconnectDevice(devRow.address)
                                    } else if (!devRow.paired) {
                                        // Pair first — this is what raises the agent
                                        // prompt. Connecting an unpaired device would
                                        // trigger it implicitly and read as a hang.
                                        btPage.connectingAddress = devRow.address
                                        BluetoothManager.pairDevice(devRow.address)
                                    } else {
                                        btPage.connectingAddress = devRow.address
                                        BluetoothManager.connectDevice(devRow.address)
                                    }
                                }
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

        // Spacer 
        Item {
            width: parent.width
            height: btPage.height * 0.05
        }
    }

    // Pairing confirmation — raised by the BlueZ agent (numeric comparison).
    // Without answering this, pairing with any modern phone cannot complete.
    Popup {
        id: pairingPopup
        width: parent.width * 0.6
        height: parent.height * 0.5
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose      // must be answered, not dismissed

        property string deviceName: ""
        property int    passkey: 0

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
            anchors.centerIn: parent
            width: parent.width - 40
            spacing: btPage.height * 0.028

            Text {
                text: "Pairing Request"
                color: "#D08831"
                font.pixelSize: btPage.height * 0.042
                font.bold: true
                font.family: "Arial"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: pairingPopup.deviceName
                color: "#e7f1ef"
                font.pixelSize: btPage.height * 0.032
                font.bold: true
                font.family: "Arial"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            // Numeric comparison code. 0 means Just Works — no code to show.
            Text {
                visible: pairingPopup.passkey > 0
                text: String(pairingPopup.passkey).padStart(6, "0")
                color: "#D08831"
                font.pixelSize: btPage.height * 0.075
                font.bold: true
                font.family: "Arial"
                font.letterSpacing: 6
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: pairingPopup.passkey > 0
                      ? "Confirm this code matches the one on your phone"
                      : "Allow this device to pair with the vehicle?"
                color: "#3D717E"
                font.pixelSize: btPage.height * 0.024
                font.family: "Arial"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: btPage.width * 0.03

                Rectangle {
                    width: btPage.width * 0.18
                    height: btPage.height * 0.075
                    radius: height / 3
                    color: rejectArea.containsMouse ? "#ff4444" : "#aa2222"
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Reject"
                        color: "#ffffff"
                        font.pixelSize: parent.height * 0.36
                        font.bold: true
                        font.family: "Arial"
                    }
                    MouseArea {
                        id: rejectArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            BluetoothManager.confirmPairing(false)
                            pairingPopup.close()
                        }
                    }
                }

                Rectangle {
                    width: btPage.width * 0.18
                    height: btPage.height * 0.075
                    radius: height / 3
                    color: acceptArea.containsMouse ? "#964405" : "#5A3211"
                    border.color: "#D08831"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Pair"
                        color: "#e7f1ef"
                        font.pixelSize: parent.height * 0.36
                        font.bold: true
                        font.family: "Arial"
                    }
                    MouseArea {
                        id: acceptArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            BluetoothManager.confirmPairing(true)
                            pairingPopup.close()
                        }
                    }
                }
            }
        }
    }

    // No on-screen status messages by design — connection state is shown by
    // the connected chip and the row highlight. Detail goes to the log only.
    function logStatus(message) {
        console.log("[bt-ui] " + message)
    }

    // Back Button 
    Rectangle {
        width: btPage.width / 8
        height: btPage.height / 16
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
            onClicked: btPage.stackView.pop()
        }
    }
}