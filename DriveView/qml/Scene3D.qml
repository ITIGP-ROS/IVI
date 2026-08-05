import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import QtQuick.Controls

import "../models_3d/audi_low_poly"

Item {
    id: root
    clip: true

    property bool topDownView: false

    property vector3d chaseOrigin:   Qt.vector3d(0, 0, 0)
    property vector3d chaseRotation: Qt.vector3d(-50, 0, 0)
    property real     chaseDistance: 960

    property vector3d topOrigin:   Qt.vector3d(0, 0, 0)
    property vector3d topRotation: Qt.vector3d(-90, 0, 0)
    property real     topDistance: 1600

    anchors.fill: parent

    // ============================================================
    // THEME
    // ============================================================
    QtObject {
        id: fsd
        property color bg:          "#e6eaeb"
        property color ego:         "#0066cc"
        property color detection:   "#a6a6a6"
        property color textPri:     "#1a1a1a"
        property color textSec:     "#555555"
        property color panelBg:     "#18000000"
        property color panelBorder: "#25000000"
    }

    // ---- Responsive scale helpers ----
    readonly property real _m:    width * 0.022
    readonly property real _r:    width * 0.012
    readonly property real _fSm:  Math.max(11, height * 0.019)
    readonly property real _fMd:  Math.max(13, height * 0.024)
    readonly property real _fLg:  Math.max(16, height * 0.030)
    readonly property real _fXl:  Math.max(26, height * 0.052)
    readonly property real _btnW: width  * 0.125
    readonly property real _btnH: height * 0.058

    // ============================================================
    // 3D VIEW
    // ============================================================
    View3D {
        id: view
        anchors.fill: parent
        camera: camera

        // DEBUG: render stats (remove after benchmarking)
        Component.onCompleted: view.renderStats.extendedDataCollectionEnabled = true

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: fsd.bg
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
        }

        DirectionalLight { eulerRotation.x: -60; eulerRotation.y: 30;   brightness: 1;   castsShadow: true }
        DirectionalLight { eulerRotation.x: -20; eulerRotation.y: -150; color: "#7799ff"; brightness: 0.4  }

        Node {
            id: orbitOrigin
            PerspectiveCamera {
                id: camera
                position: Qt.vector3d(0, 0, 960)
                fieldOfView: 70; clipNear: 1; clipFar: 100000
                Behavior on position      { Vector3dAnimation { duration: 700; easing.type: Easing.InOutCubic } }
                Behavior on eulerRotation { Vector3dAnimation { duration: 700; easing.type: Easing.InOutCubic } }
            }
        }

        OrbitCameraController {
            anchors.fill: parent; camera: camera; origin: orbitOrigin
            mouseEnabled: true; panEnabled: true; xSpeed: 0.05; ySpeed: 0.05
        }

        MouseArea {
            anchors.fill: parent; acceptedButtons: Qt.MiddleButton; propagateComposedEvents: true
            property real lastX: 0; property real lastY: 0
            onPressed: (mouse) => {
                           if (mouse.button === Qt.MiddleButton) { lastX = mouse.x; lastY = mouse.y; mouse.accepted = true }
                           else mouse.accepted = false
                       }
            onPositionChanged: (mouse) => {
                                   if (pressedButtons & Qt.MiddleButton) {
                                       let dx = mouse.x-lastX, dy = mouse.y-lastY; lastX = mouse.x; lastY = mouse.y
                                       let s = camera.position.length() * 0.001
                                       camera.position      = Qt.vector3d(camera.position.x - dx*s,      camera.position.y,      camera.position.z - dy*s)
                                       orbitOrigin.position = Qt.vector3d(orbitOrigin.position.x - dx*s, orbitOrigin.position.y, orbitOrigin.position.z - dy*s)
                                   }
                               }
        }

        Node {
            id: egoVehicle
            position: Qt.vector3d(0, -100, 0)
            Audi_rs7_free__low_poly {
                id: egoCar
                scale: Qt.vector3d(137, 250, 137)
                eulerRotation: Qt.vector3d(0, -90, 0)
                carColor: fsd.ego; carMetalness: 0.3; carRoughness: 0.1
            }
        }

        Node {
            Model {
                source: "qrc:/meshes/plane__0_mesh.mesh"
                instancing: planeInstancing
                materials: PrincipledMaterial { baseColor: fsd.detection; metalness: 0.1; roughness: 0.5 }
            }
            Model {
                source: "#Cube"
                instancing: cubeInstancing
                materials: PrincipledMaterial { baseColor: fsd.detection; metalness: 0.1; roughness: 0.5 }
            }
            Model {
                source: "qrc:/meshes/car_mesh.mesh"
                instancing: carInstancing
                materials: PrincipledMaterial { baseColor: fsd.detection; metalness: 0.1; roughness: 0.5 }
            }
        }
    }

    // DEBUG: log render stats every second (remove after benchmarking)
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: console.log("[stats] fps=" + view.renderStats.fps +
            " frame=" + view.renderStats.frameTime.toFixed(2) +
            " max=" + view.renderStats.maxFrameTime.toFixed(2) +
            " render=" + view.renderStats.renderTime.toFixed(2) +
            " sync=" + view.renderStats.syncTime.toFixed(2) +
            " draws=" + view.renderStats.drawCallCount +
            " verts=" + view.renderStats.drawVertexCount +
            " passes=" + view.renderStats.renderPassCount)
    }

    // ============================================================
    // HUD — TOP LEFT: Settings Button + Status Panel (stacked)
    // ============================================================
    Column {
        id: leftHudColumn
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: _m
        anchors.topMargin: _m
        width: root.width * 0.22
        spacing: _m * 0.6

        Rectangle {
            id: statusPanel
            width: parent.width
            height: _statusCol.implicitHeight + _m * 2
            radius: _r * 1.3
            color: fsd.panelBg
            border.color: fsd.panelBorder
            border.width: 1
            opacity: settingsDrawer.open ? 0.0 : 1.0
            visible: !settingsDrawer.open || opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }

            Column {
                id: _statusCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: _m }
                spacing: _m * 0.55

                Row {
                    spacing: _m * 0.55
                    width: parent.width
                    Rectangle {
                        width: _fSm * 0.75
                        height: _fSm * 0.75
                        radius: width / 2
                        color: fsd.ego
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Visualizer BETA"
                        color: fsd.textPri
                        font.pixelSize: _fMd
                        font.bold: true
                        font.family: "Segoe UI, Roboto, sans-serif"
                        width: parent.width - _fSm * 0.75 - parent.spacing
                        height: implicitHeight
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 8
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Text {
                    text: "Proof of concept"
                    color: fsd.textPri
                    font.pixelSize: _fSm
                    font.family: "Segoe UI, Roboto, sans-serif"
                    width: parent.width
                    height: implicitHeight
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 8
                }
                Rectangle { width: parent.width; height: 1; color: fsd.panelBorder }
                Text {
                    text: "Detections: " + (Math.abs(detectionModel.detectCount) > 1000 ? "-" : detectionModel.detectCount)
                    color: fsd.textSec
                    font.pixelSize: _fSm
                    font.family: "monospace"
                    width: parent.width
                    height: implicitHeight
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 8
                }
                Text {
                    text: "View: " + (topDownView ? "TOP" : "CHASE")
                    color: fsd.textSec
                    font.pixelSize: _fSm
                    font.family: "monospace"
                    width: parent.width
                    height: implicitHeight
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 8
                }
            }
        }

        Rectangle {
            id: settingsBtn
            width: _btnW
            height: _btnH
            radius: _r
            color: fsd.panelBg
            border.color: fsd.panelBorder
            border.width: 1
            opacity: settingsDrawer.open ? 0.0 : 0.95
            visible: !settingsDrawer.open
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }

            Text {
                anchors.centerIn: parent
                text: "⚙  SETTINGS"
                color: fsd.textPri
                font.pixelSize: _fSm
                font.letterSpacing: 1.2
                font.family: "monospace"
                width: parent.width * 0.9
                height: implicitHeight
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 8
                horizontalAlignment: Text.AlignHCenter
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: parent.opacity = 1.0
                onExited: parent.opacity = 0.95
                onClicked: settingsDrawer.open = true
            }
        }
    }

    // ============================================================
    // HUD — BOTTOM LEFT: Legend
    // ============================================================
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: _m
        anchors.bottomMargin: _m
        width: parent.width * 0.13
        height: _legendCol.implicitHeight + _m * 1.6
        radius: _r
        color: fsd.panelBg
        border.color: fsd.panelBorder
        border.width: 1
        opacity: settingsDrawer.open ? 0.0 : 1.0
        visible: !settingsDrawer.open || opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }

        Column {
            id: _legendCol
            anchors { fill: parent; margins: _m * 0.85 }
            spacing: _m * 0.55

            Text {
                text: "LEGEND"
                color: fsd.textPri
                font.pixelSize: _fSm
                font.bold: true
                font.family: "monospace"
                width: parent.width
                height: implicitHeight
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 8
            }
            Row {
                spacing: _m * 0.5
                width: parent.width
                Rectangle {
                    width: _fSm * 0.85
                    height: _fSm * 0.85
                    radius: 2
                    color: fsd.ego
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "Ego"
                    color: fsd.textSec
                    font.pixelSize: _fSm
                    font.family: "monospace"
                    width: parent.width - _fSm * 0.85 - parent.spacing
                    height: implicitHeight
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 8
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Row {
                spacing: _m * 0.5
                width: parent.width
                Rectangle {
                    width: _fSm * 0.85
                    height: _fSm * 0.85
                    radius: 2
                    color: fsd.detection
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "Detection"
                    color: fsd.textSec
                    font.pixelSize: _fSm
                    font.family: "monospace"
                    width: parent.width - _fSm * 0.85 - parent.spacing
                    height: implicitHeight
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 8
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ============================================================
    // HUD — TOP RIGHT: Camera Telemetry
    // ============================================================
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: _m
        anchors.topMargin: _m
        width: parent.width * 0.17
        height: _camCol.implicitHeight + _m * 2
        radius: _r * 1.3
        color: fsd.panelBg
        border.color: fsd.panelBorder
        border.width: 1

        Column {
            id: _camCol
            anchors { fill: parent; margins: _m }
            spacing: _m * 0.45

            Text {
                text: "CAMERA"
                color: fsd.textPri
                font.pixelSize: _fMd
                font.bold: true
                font.family: "monospace"
                width: parent.width
                height: implicitHeight
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 8
            }
            Text {
                width: parent.width
                height: implicitHeight
                color: fsd.textSec
                font.pixelSize: _fSm
                font.family: "monospace"
                lineHeight: 1.4
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 8
                text: "POS\n  X: " + camera.position.x.toFixed(1) +
                      "\n  Y: " + camera.position.y.toFixed(1) +
                      "\n  Z: " + camera.position.z.toFixed(1) +
                      "\n\nROT\n  X: " + camera.eulerRotation.x.toFixed(1) +
                      "\n  Y: " + camera.eulerRotation.y.toFixed(1) +
                      "\n  Z: " + camera.eulerRotation.z.toFixed(1)
            }
        }
    }

    // ============================================================
    // HUD — BOTTOM CENTER: Speed Pill
    // ============================================================
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.05
        width: parent.width * 0.15
        height: parent.height * 0.10
        radius: height / 2
        color: fsd.panelBg
        border.color: fsd.panelBorder
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: _m * 0.4
            Text {
                id: _speedNum
                text: (carInfo.currVel * 3.6).toFixed(0)
                color: fsd.textPri
                font.pixelSize: _fXl
                font.bold: true
                font.family: "Segoe UI, Roboto, sans-serif"
                width: implicitWidth
                height: implicitHeight
            }
            Text {
                text: "KM/H"
                color: fsd.textSec
                font.pixelSize: _fSm
                font.family: "Segoe UI, Roboto, sans-serif"
                anchors.baseline: _speedNum.baseline
                width: implicitWidth
                height: implicitHeight
            }
        }
    }

    // ============================================================
    // HUD — BOTTOM RIGHT: View buttons
    // ============================================================
    Rectangle {
        id: viewToggle
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: _m
        anchors.bottomMargin: _m
        width: _btnW
        height: _btnH
        radius: _r
        color: fsd.panelBg
        border.color: fsd.panelBorder
        border.width: 1
        opacity: 0.95

        Text {
            anchors.centerIn: parent
            text: topDownView ? "CHASE VIEW" : "TOP VIEW"
            color: fsd.textPri
            font.pixelSize: _fSm
            font.letterSpacing: 1.2
            font.family: "monospace"
            width: parent.width * 0.9
            height: implicitHeight
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 8
            horizontalAlignment: Text.AlignHCenter
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: parent.opacity = 1.0
            onExited: parent.opacity = 0.95
            onClicked: {
                topDownView = !topDownView
                topDownView ? applyTopView() : applyChaseView()
            }
        }
    }

    Rectangle {
        anchors.right: viewToggle.left
        anchors.bottom: parent.bottom
        anchors.rightMargin: _m * 0.55
        anchors.bottomMargin: _m
        width: _btnW
        height: _btnH
        radius: _r
        color: fsd.panelBg
        border.color: fsd.panelBorder
        border.width: 1
        opacity: 0.95

        Text {
            anchors.centerIn: parent
            text: "RESET VIEW"
            color: fsd.textPri
            font.pixelSize: _fSm
            font.letterSpacing: 1.2
            font.family: "monospace"
            width: parent.width * 0.9
            height: implicitHeight
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 8
            horizontalAlignment: Text.AlignHCenter
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: parent.opacity = 1.0
            onExited: parent.opacity = 0.95
            onClicked: resetCurrentView()
        }
    }

    // ============================================================
    // LEFT DRAWER — Car Settings
    // ============================================================
    Rectangle {
        id: settingsDrawer
        property bool open: false
        z: 100

        y: 0
        width: parent.width * 0.26
        height: parent.height

        x: open ? 0 : -width

        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }

        color: fsd.panelBg
        border.color: fsd.panelBorder
        border.width: 1

        Flickable {
            anchors.fill: parent
            contentHeight: _drawerCol.implicitHeight + _m * 3
            clip: true

            Column {
                id: _drawerCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: _m * 1.1 }
                spacing: _m * 0.8

                Item { width: 1; height: _m * 0.4 }

                // ---- Header: title + close button (anchored, no overlap) ----
                Item {
                    width: parent.width
                    height: Math.max(_drawerTitle.implicitHeight, closeBtn.height)

                    Text {
                        id: _drawerTitle
                        anchors.left: parent.left
                        anchors.right: closeBtn.left
                        anchors.rightMargin: _m * 0.5
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Car Settings"
                        font.pixelSize: _fLg
                        font.bold: true
                        color: fsd.textPri
                        height: implicitHeight
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 8
                        horizontalAlignment: Text.AlignLeft
                    }

                    Rectangle {
                        id: closeBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: _btnW * 0.85
                        height: _btnH * 0.78
                        radius: _r * 0.8
                        color: fsd.panelBg
                        border.color: fsd.panelBorder
                        border.width: 1
                        opacity: 0.95

                        Text {
                            anchors.fill: parent
                            anchors.margins: 6
                            text: "✕ Close"
                            color: fsd.textPri
                            font.pixelSize: _fSm
                            minimumPixelSize: 9
                            fontSizeMode: Text.Fit
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.letterSpacing: 0.8
                            font.family: "monospace"
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: parent.opacity = 1.0
                            onExited: parent.opacity = 0.95
                            onClicked: settingsDrawer.open = false
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: fsd.panelBorder }

                // ---- Car Color ----
                Text {
                    text: "Car Color"
                    color: fsd.textSec
                    font.pixelSize: _fSm
                    width: parent.width
                    height: implicitHeight
                }

                Rectangle {
                    width: parent.width
                    height: _m * 2.4
                    radius: _r * 0.7
                    color: fsd.ego
                    border.color: fsd.panelBorder
                    border.width: 1
                }

                Canvas {
                    id: colorWheel
                    width: parent.width
                    height: width

                    property real pickedHue: 0.583
                    property real pickedSat: 1.0
                    property real pickedVal: 1.0

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        var cx = width/2, cy = height/2, r = Math.min(cx,cy) - 4
                        for (var i = 0; i < 360; i++) {
                            var a1 = (i/360)*2*Math.PI - Math.PI/2
                            var a2 = ((i+1)/360)*2*Math.PI - Math.PI/2
                            var g = ctx.createRadialGradient(cx,cy,0, cx,cy,r)
                            g.addColorStop(0, "white")
                            g.addColorStop(1, "hsl("+i+",100%,50%)")
                            ctx.beginPath(); ctx.moveTo(cx,cy); ctx.arc(cx,cy,r,a1,a2); ctx.closePath()
                            ctx.fillStyle = g; ctx.fill()
                        }
                        if (pickedVal < 1.0) {
                            var alpha = (1 - pickedVal).toString()
                            var ov = ctx.createRadialGradient(cx,cy,0,cx,cy,r)
                            ov.addColorStop(0, "rgba(0,0,0,"+alpha+")")
                            ov.addColorStop(1, "rgba(0,0,0,"+alpha+")")
                            ctx.beginPath(); ctx.arc(cx,cy,r,0,2*Math.PI); ctx.fillStyle = ov; ctx.fill()
                        }
                        var sa = pickedHue*2*Math.PI - Math.PI/2
                        var sx = cx + pickedSat*r*Math.cos(sa), sy = cy + pickedSat*r*Math.sin(sa)
                        ctx.beginPath(); ctx.arc(sx,sy,8,0,2*Math.PI); ctx.strokeStyle="white";          ctx.lineWidth=3;   ctx.stroke()
                        ctx.beginPath(); ctx.arc(sx,sy,8,0,2*Math.PI); ctx.strokeStyle="rgba(0,0,0,0.4)"; ctx.lineWidth=1.2; ctx.stroke()
                    }

                    function pick(mx, my) {
                        var cx=width/2, cy=height/2, r=Math.min(cx,cy)-4
                        var dx=mx-cx, dy=my-cy, dist=Math.sqrt(dx*dx+dy*dy)
                        if (dist>r) { dx*=r/dist; dy*=r/dist; dist=r }
                        var angle = Math.atan2(dy,dx)+Math.PI/2
                        if (angle<<0) angle+=2*Math.PI
                        if (angle>=2*Math.PI) angle-=2*Math.PI
                        pickedHue = angle/(2*Math.PI); pickedSat = dist/r
                        applyColor(); requestPaint()
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPressed:         colorWheel.pick(mouseX, mouseY)
                        onPositionChanged: if (pressed) colorWheel.pick(mouseX, mouseY)
                    }
                }

                Text {
                    text: "Brightness: " + brightnessSlider.value.toFixed(2)
                    color: fsd.textSec
                    font.pixelSize: _fSm
                    width: parent.width
                    height: implicitHeight
                }
                Slider {
                    id: brightnessSlider
                    width: parent.width
                    from: 0.05
                    to: 1.0
                    value: 1.0
                    onValueChanged: {
                        colorWheel.pickedVal = value
                        applyColor()
                        colorWheel.requestPaint()
                    }
                }

                Rectangle { width: parent.width; height: 1; color: fsd.panelBorder }

                Text {
                    text: "Metalness: " + metalSlider.value.toFixed(2)
                    color: fsd.textSec
                    font.pixelSize: _fSm
                    width: parent.width
                    height: implicitHeight
                }
                Slider {
                    id: metalSlider
                    width: parent.width
                    from: 0
                    to: 1
                    value: egoCar.carMetalness
                    onValueChanged: egoCar.carMetalness = value
                }

                Text {
                    text: "Roughness: " + roughSlider.value.toFixed(2)
                    color: fsd.textSec
                    font.pixelSize: _fSm
                    width: parent.width
                    height: implicitHeight
                }
                Slider {
                    id: roughSlider
                    width: parent.width
                    from: 0
                    to: 1
                    value: egoCar.carRoughness
                    onValueChanged: egoCar.carRoughness = value
                }
            }
        }
    }

    // ============================================================
    // HELPERS
    // ============================================================
    function hsvToRgb(h, s, v) {
        var r, g, b, i=Math.floor(h*6), f=h*6-i
        var p=v*(1-s), q=v*(1-f*s), t=v*(1-(1-f)*s)
        switch (i%6) {
        case 0: r=v; g=t; b=p; break;  case 1: r=q; g=v; b=p; break
                                       case 2: r=p; g=v; b=t; break;  case 3: r=p; g=q; b=v; break
                                                                      case 4: r=t; g=p; b=v; break;  case 5: r=v; g=p; b=q; break
        }
        return Qt.rgba(r, g, b, 1.0)
    }

    function applyColor() {
        fsd.ego = hsvToRgb(colorWheel.pickedHue, colorWheel.pickedSat, brightnessSlider.value)
    }

    function applyChaseView() {
        orbitOrigin.position = chaseOrigin
        orbitOrigin.eulerRotation = chaseRotation
        camera.position = Qt.vector3d(0, 0, chaseDistance)
    }

    function applyTopView() {
        orbitOrigin.position = topOrigin
        orbitOrigin.eulerRotation = topRotation
        camera.position = Qt.vector3d(0, 0, topDistance)
    }

    function resetCurrentView() {
        if (topDownView)
            applyTopView()
        else
            applyChaseView()
    }

    Component.onCompleted: applyChaseView()
}
