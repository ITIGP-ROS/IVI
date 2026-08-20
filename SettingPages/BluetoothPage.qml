import QtQuick
import QtQuick.Controls

Rectangle {
    id: btPage
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    color: "transparent"
    required property StackView stackView

    // Identity colour for this sub-page, matching the card it opens from.
    readonly property color accent: Theme.accentBlue

    /*
     * List geometry, in one place.
     *
     * The container is sized to a whole number of rows rather than to a
     * fraction of the page: at 0.50 it came out at five rows plus four pixels,
     * and the sliver of a sixth row against the bottom edge read as a clipping
     * bug rather than as "there is more below".
     */
    readonly property real rowHeight:   height / 12
    readonly property int  rowSpacing:  6
    readonly property int  listPadding: 10
    readonly property int  visibleRows: 6
    readonly property real listHeight:
        visibleRows * rowHeight + (visibleRows - 1) * rowSpacing + listPadding * 2
    property bool updatingFromBackend: false

    property string connectingAddress:    ""
    property string disconnectingAddress: ""
    property var    connectedAddresses:   []

    // Background — the home screen's, drawn by the shared component so the
    // sub-page and the settings menu it was pushed from cannot drift apart.
    GlassBackground {
        z: -1
        anchors.fill: parent
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
            BluetoothManager.fetchKnownDevices()
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

        /*
         * Header: title, connection status, power toggle.
         *
         * The status used to be a full-width chip on a line of its own. It is
         * one short phrase, and giving it a row cost the list an entire device
         * — the thing this page exists to show. Between the title and the
         * switch there is dead space it fits in for free.
         */
        Item {
            width: parent.width
            height: btPage.height / 14

            Text {
                id: btTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Bluetooth"
                font.pixelSize: btPage.width / 28
                color: Theme.textPrimary
                font.bold: true
                font.family: "Arial"
            }

            Text {
                // Centred on the header, not in the gap between the title and
                // the switch: the title is far the wider of the two, so centring
                // in what is left of the row pushed the status visibly right of
                // the page's middle.
                //
                // Width is capped by whichever side is wider, applied to both,
                // which keeps the text centred and clear of both ends at once.
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                       - 2 * Math.max(btTitle.width, btSwitchBg.width)
                       - btPage.width * 0.06
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: btSwitch.checked
                text: btPage.connectedAddresses.length > 0 ? "Device connected"
                                                           : "Not connected"
                color: btPage.connectedAddresses.length > 0 ? btPage.accent
                                                            : Theme.textSecondary
                font.pixelSize: btPage.height * 0.03
                font.family: "Arial"
                Behavior on color { ColorAnimation { duration: 300 } }
            }

            Rectangle {
                id: btSwitchBg
                anchors.right: parent.right
                width: btPage.width / 14
                height: btPage.height / 22
                radius: height / 2
                color: btSwitch.checked ? btPage.accent : Theme.glassBorder
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 200 } }

                Rectangle {
                    id: btKnob
                    width: parent.height - 4
                    height: width
                    radius: width / 2
                    color: Theme.textPrimary
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
            color: Theme.glassBorder
            opacity: 0.5
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
                color: Theme.textPrimary
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
                color: Theme.glassFill
                border.color: Theme.glassBorder
                border.width: 1
                visible: deviceListModel.count > 0

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: deviceListModel.count
                    color: btPage.accent
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
                color: !enabled ? Theme.glassFill
                                : (scanBtnArea.containsMouse ? Theme.tint(btPage.accent, 0.32) : Theme.tint(btPage.accent, 0.18))
                border.color: enabled ? btPage.accent : Theme.glassBorder
                border.width: 1
                enabled: !btPage.isScanning
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    id: scanBtnText
                    anchors.centerIn: parent
                    text: btPage.isScanning ? "Scanning..." : "Scan"
                    color: scanBtn.enabled ? Theme.textPrimary : Theme.textSecondary
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
            height: btPage.listHeight
            radius: btPage.height * 0.02
            color: Theme.glassFill
            border.color: Theme.glassBorder
            border.width: 1
            visible: btSwitch.checked

            //Scanning overlay
            Rectangle {
                anchors.fill: parent
                color: Theme.surface
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
                        border.color: btPage.accent
                        border.width: 3
                        radius: width / 2
                        anchors.horizontalCenter: parent.horizontalCenter

                        Rectangle {
                            width: 6; height: 6
                            color: Theme.surface
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
                        color: btPage.accent
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
                    color: Theme.textSecondary
                    font.pixelSize: btPage.height * 0.025
                    font.family: "Arial"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            ListView {
                id: deviceListView
                anchors.fill: parent
                anchors.margins: btPage.listPadding
                anchors.rightMargin: 18
                clip: true
                model: deviceListModel
                spacing: btPage.rowSpacing

                ScrollBar.vertical: ScrollBar {
                    width: 6
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: parent.pressed ? Theme.tint(btPage.accent, 0.32) : btPage.accent
                        opacity: 0.8
                    }
                    background: Rectangle {
                        implicitWidth: 6
                        color: Theme.surface
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
                    height: btPage.rowHeight
                    radius: height / 4
                    color: rowHover.containsMouse ? Theme.tint(btPage.accent, 0.32) : (isConnected ? Theme.tint(btPage.accent, 0.18) : Theme.glassFill)
                    border.color: isConnected ? btPage.accent : Theme.glassBorder
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

                        BluetoothGlyph {
                            id: devGlyph
                            width: devRow.height * 0.62
                            height: width
                            connected: devRow.isConnected
                            accent: btPage.accent
                            idleColor: Theme.textSecondary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            // Measured off the glyph rather than re-deriving it
                            // from the row height, which is how the old text
                            // icon and this column drifted apart whenever the
                            // icon was resized.
                            width: parent.width
                                   - actionBtn.width
                                   - devGlyph.width
                                   - parent.spacing * 2
                            spacing: 2

                            Text {
                                text: devRow.name
                                font.pixelSize: parent.parent.parent.height * 0.32
                                color: devRow.isConnected ? btPage.accent : Theme.textPrimary
                                font.bold: true
                                font.family: "Arial"
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: devRow.address
                                font.pixelSize: parent.parent.parent.height * 0.22
                                color: Theme.textSecondary
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
                                if (devRow.isDisconnecting) return Theme.glassFill
                                if (devRow.isConnected)
                                    return connArea.containsMouse ? Theme.danger : Theme.tint(Theme.danger, 0.35) 
                                if (devRow.isConnecting) return Theme.glassFill
                                return connArea.containsMouse ? Theme.tint(btPage.accent, 0.32) : Theme.tint(btPage.accent, 0.18)
                            }
                            border.color: devRow.isConnected ? Theme.danger : btPage.accent
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
            color: Theme.scrim
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        background: Rectangle {
            color: Theme.surface
            radius: 18
            border.color: btPage.accent
            border.width: 2
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - 40
            spacing: btPage.height * 0.028

            Text {
                text: "Pairing Request"
                color: btPage.accent
                font.pixelSize: btPage.height * 0.042
                font.bold: true
                font.family: "Arial"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: pairingPopup.deviceName
                color: Theme.textPrimary
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
                color: btPage.accent
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
                color: Theme.textSecondary
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
                    color: rejectArea.containsMouse ? Theme.danger : Theme.tint(Theme.danger, 0.35)
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
                    color: acceptArea.containsMouse ? Theme.tint(btPage.accent, 0.32) : Theme.tint(btPage.accent, 0.18)
                    border.color: btPage.accent
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Pair"
                        color: Theme.textPrimary
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
        color: backBtnArea.containsMouse ? Theme.tint(btPage.accent, 0.32) : Theme.tint(btPage.accent, 0.18)
        radius: height / 4
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: parent.height * 0.04
        anchors.leftMargin: parent.width * 0.08
        border.color: btPage.accent
        border.width: 1
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            text: "Back"
            font.pixelSize: parent.height * 0.45
            color: Theme.textPrimary
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