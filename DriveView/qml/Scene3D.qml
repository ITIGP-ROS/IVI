import QtCore
import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import QtQuick.Controls

import "../models_3d/audi_low_poly"

Item {
    id: root
    clip: true
    property bool topDownView: false
    // false until the initial view is applied in Component.onCompleted, so the
    // startup camera snaps into place instead of sweeping
    property bool viewReady: false

    property vector3d chaseOrigin:   Qt.vector3d(0, 0, 0)
    property vector3d chaseRotation: Qt.vector3d(-50, 0, 0)
    property real     chaseDistance: 1200

    property vector3d topOrigin:   Qt.vector3d(0, 0, 0)
    property vector3d topRotation: Qt.vector3d(-90, 0, 0)
    property real     topDistance: 1600

    // render the Tesla with its baked texture instead of the flat detection tint
    property bool useTeslaTexture: true

    // environment: road style (false = realistic asphalt, true = clean flat)
    property bool asphaltRoad: false
    // HDRI testing: -1 = flat background, 0..1 = cycle through the files
    property int hdriIndex: -1
    property real probeExposure: 1.0
    // master look: light = asphalt road + wide-street HDRI (0.3) + white fog,
    // dark = neon road + ferndale HDRI (0.1) + near-black fog. The theme
    // switch lives in the settings drawer and applies the preset via
    // applyTheme(), which writes the individual properties below.
    property bool darkTheme: true
    property var hdriList: [
        "qrc:/hdri/ferndale_studio_12_1k.hdr",
        "qrc:/hdri/wide_street_02_1k.hdr"
    ]

    anchors.fill: parent

    // ============================================================
    // THEME
    // ============================================================
    // Dark, because the road is. The panels used to be dark ink on a light
    // grey void; with a real road under them that reads as unlit text on unlit
    // tarmac, so the whole HUD is inverted rather than fighting the ground for
    // contrast.
    QtObject {
        id: fsd
        // Shows through where the road has faded out — this is the colour the
        // detection range ends in, so it wants to be near-black, not grey.
        property color bg:          Theme.base
        property color ego:         CarColors.ego
        property color detection:   "#a6a6a6"
        property color textPri:     Theme.textPrimary
        property color textSec:     Theme.textSecondary

        /*
         * The HUD's own colour, shared with the rest of the app.
         *
         * Deliberately NOT the car colour. The ego swatch, the legend and the
         * car itself already carry that, and it is user-settable — a driver who
         * picks red would otherwise repaint every border and every hover state
         * on the page red along with the paintwork.
         */
        property color accent:      Theme.accentBlue

        // Panel fill and border now live in HudPanel; these two remain for the
        // settings drawer, which is a full surface rather than a floating one.
        property color panelBg:     Qt.rgba(0.02, 0.04, 0.08, 0.80)
        property color panelBorder: Theme.glassBorder
    }

    /*
     * Everything the car-settings drawer can change, kept across restarts.
     *
     * The car colour itself is owned by CarColors (shared with the launcher
     * preview, which needs it from the first frame, before this scene is even
     * created), stored there as the three inputs the picker works in.
     *
     * QSettings is usable here because main.cpp sets the organisation and
     * application identifiers before the engine loads — without those it
     * refuses to initialise and every value is silently dropped.
     */
    Settings {
        id: driveSettings
        category: "DriveView"

        property bool darkTheme:    true
        property real carMetalness: 0.6
        property real carRoughness: 0.1
    }

    /*
     * Extra clearance at the top for the HUD panels only.
     *
     * The 3D view deliberately fills the whole page, so the road and sky run
     * underneath the floating window bar instead of leaving bare background
     * above it. The bar is not part of this component and knows nothing about
     * it, so anything anchored to the top here would slide under it — hence a
     * separate inset for the overlays rather than a margin on the scene.
     *
     * 0 by default: a Scene3D with no bar over it must not reserve space for
     * one. DriveViewPage sets it to clear the bar it draws.
     */
    property real topInset: 0

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
            id: sceneEnv
            backgroundMode: SceneEnvironment.Color
            clearColor: root.darkTheme ? "#0d0d12" : "#ffffff"
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
            // HDRI probe: one Texture per file, both loaded once at startup;
            // a theme switch only re-points the lightProbe reference. Loading
            // the .hdr from the compressed qrc on every toggle was the freeze
            // (decompress + HDR parse + env mipmaps on the GUI thread).
            lightProbe: root.hdriIndex == 0 ? ferndaleTex
                      : root.hdriIndex == 1 ? wideTex
                      : null
            probeExposure: root.probeExposure

            // distance haze: the far end of the city (and everything else
            // past ~40 m) melts into the light background. This is world-space
            // (per-fragment), so it is smooth and seamless — no per-row
            // opacity bands, and it hides the city's loop-wrap pop beyond
            // the road end.
            fog: Fog {
                enabled: true
                color: root.darkTheme ? "#101015" : "#ffffff"
                depthEnabled: true
                depthNear: 4000
                depthFar: 6800
            }

            Texture {
                id: ferndaleTex
                source: "qrc:/hdri/ferndale_studio_12_1k.hdr"
                mappingMode: Texture.Environment
                generateMipmaps: true
                mipFilter: Texture.Linear
            }
            Texture {
                id: wideTex
                source: "qrc:/hdri/wide_street_02_1k.hdr"
                mappingMode: Texture.Environment
                generateMipmaps: true
                mipFilter: Texture.Linear
            }
        }

        DirectionalLight { eulerRotation.x: -60; eulerRotation.y: 30;   brightness: 1.15; castsShadow: true }
        DirectionalLight { eulerRotation.x: -20; eulerRotation.y: -150; color: "#7799ff"; brightness: 0.5 }

        Environment3D {
            id: environment3D
            asphalt: root.asphaltRoad
            // m/s — the city scrolls at the car's own speed, frozen at standstill
            speed: carInfo.currVel
        }

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

        // View-switch glide for the orbit origin. The camera distance rides
        // its Behavior above; this animates the rig's rotation (and any pan
        // drift) with the same duration/easing so the pitch doesn't snap
        // while the camera glides. Manually from/to'd per switch because a
        // Behavior here would fight the OrbitCameraController, which writes
        // orbitOrigin every frame while dragging.
        ParallelAnimation {
            id: viewSwitchAnim
            Vector3dAnimation {
                id: viewPosAnim
                target: orbitOrigin
                property: "position"
                duration: 700
                easing.type: Easing.InOutCubic
            }
            Vector3dAnimation {
                id: viewRotAnim
                target: orbitOrigin
                property: "eulerRotation"
                duration: 700
                easing.type: Easing.InOutCubic
            }
        }

        MyOrbitCameraController {
            anchors.fill: parent; camera: camera; origin: orbitOrigin
            mouseEnabled: true; panEnabled: false; zoomEnabled: false; xSpeed: 0.05; ySpeed: 0.05
        }

        Node {
            id: egoVehicle
            // road top sits at floorY+0.5 = -141.5; tune ± if the mesh origin is centered
            position: Qt.vector3d(0, -141, 0)
            Audi_rs7_free__low_poly {
                id: egoCar
                scale: Qt.vector3d(137, 250, 137)
                eulerRotation: Qt.vector3d(0, -90, 0)
                carColor: fsd.ego; carMetalness: 0.6; carRoughness: 0.1
                // deg/s per m/s — wheels spin with the car, stop at standstill
                wheelSpeed: carInfo.currVel * 120
            }
        }

        Node {
            Model {
                source: "qrc:/meshes/plane__0_walkpose_mesh.mesh"
                instancing: planeInstancing
                castsShadows: false
                receivesShadows: false
                // Blend so the spawn/despawn fade in DetectionSmoother is
                // visible at all — it arrives as per-instance alpha, and an
                // Opaque material simply discards it.
                materials: PrincipledMaterial { baseColor: fsd.detection; metalness: 0.8; roughness: 0.5
                                                alphaMode: PrincipledMaterial.Blend }
            }
            Model {
                source: "#Cube"
                instancing: cubeInstancing
                castsShadows: false
                receivesShadows: false
                materials: PrincipledMaterial { baseColor: fsd.detection; metalness: 0.1; roughness: 0.5
                                                alphaMode: PrincipledMaterial.Blend }
            }
            Model {
                source: "qrc:/models_3d/tesla_low_poly/meshes/object_0_mesh.mesh"
                instancing: carInstancing
                castsShadows: false
                receivesShadows: false
                materials: PrincipledMaterial {
                    // White base when the map is active: the silver texture
                    // already carries the full tone range, so no double-darkening.
                    // Matte + no metal: flat, non-distracting detection look.
                    //
                    // Emissive is doing real work here, not decoration.
                    // Detections arrive at whatever yaw the detector reports, and
                    // the scene has a key light plus one weak fill but no ambient
                    // — the two lights sit at opposite yaws, so a face pointing
                    // between them catches almost nothing. Left to the lights
                    // alone a car turned away rendered its painted rear panels at
                    // ~0.6x the brightness of an identical car facing the camera,
                    // which is what made these read grey instead of silver.
                    //
                    // Feeding the same map back as emissive adds a constant floor
                    // to every face regardless of which way it points. Pulling the
                    // diffuse down to compensate was tried and made it worse — it
                    // dimmed everything without closing the gap, because the gap is
                    // additive, not proportional. Full diffuse plus a strong floor
                    // is what works.
                    //
                    // Note this does NOT make the whole rear silver, and should not:
                    // the rear window and glass roof are black in the texture by
                    // design, and from a raised chase camera they are most of what
                    // you see of a car driving away.
                    baseColor: root.useTeslaTexture ? Qt.rgba(1, 1, 1, 1) : fsd.detection
                    baseColorMap: root.useTeslaTexture ? teslaTex : null
                    emissiveMap: root.useTeslaTexture ? teslaTex : null
                    emissiveFactor: root.useTeslaTexture ? Qt.vector3d(0.65, 0.65, 0.65)
                                                         : Qt.vector3d(0, 0, 0)
                    metalness: 0.0; roughness: 0.9
                    // Deliberately left Opaque, i.e. the per-instance
                    // spawn/despawn alpha is discarded for cars. Blend was
                    // tried so they would fade in like the other classes and it
                    // wrecked them: this mesh is one concave body with the
                    // wheels as separate surfaces inside the arches, and a
                    // blended material sorts per object instead of per pixel —
                    // so the wheels drew over the bodywork and appeared to hang
                    // outside the car. Cars pop in instead. Do not add Blend
                    // back here without OpaquePrePassDepthDraw alongside it.
                }
            }
        }
    }

    Texture {
        id: teslaTex
        source: "qrc:/models_3d/tesla_low_poly/maps/textureData_silver.jpg"
        generateMipmaps: true
        mipFilter: Texture.Linear
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
        anchors.topMargin: _m + root.topInset
        width: root.width * 0.22
        spacing: _m * 0.6

        HudPanel {
            id: statusPanel
            width: parent.width
            height: _statusCol.implicitHeight + _m * 2
            cardRadius: _r * 1.3
            accent: fsd.accent
            showAccentBar: true
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
                    // Breathes while detections are arriving and sits still when
                    // they are not, so the panel says whether the pipeline is
                    // alive without spending a line of text on it.
                    Rectangle {
                        id: liveDot
                        width: _fSm * 0.75
                        height: _fSm * 0.75
                        radius: width / 2
                        color: detectionModel.detectCount > 0 ? Theme.success : fsd.textSec
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on color { ColorAnimation { duration: 250 } }

                        SequentialAnimation on opacity {
                            running: detectionModel.detectCount > 0
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutSine }
                            onStopped: liveDot.opacity = 1.0
                        }
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

        HudButton {
            id: settingsBtn
            width: _btnW
            height: _btnH
            cardRadius: _r
            accent: fsd.accent
            textColor: fsd.textPri
            fontSize: _fSm
            text: "⚙  SETTINGS"
            opacity: settingsDrawer.open ? 0.0 : 1.0
            visible: !settingsDrawer.open
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }
            onClicked: settingsDrawer.open = true
        }
    }

    // ============================================================
    // HUD — BOTTOM LEFT: Legend
    // ============================================================
    HudPanel {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: _m
        anchors.bottomMargin: _m
        width: parent.width * 0.13
        height: _legendCol.implicitHeight + _m * 1.6
        cardRadius: _r
        accent: fsd.accent
        // The one panel that may as well be see-through: two static swatches
        // that the driver reads once and then never again.
        inkAlpha: 0.62
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
    HudPanel {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: _m
        anchors.topMargin: _m + root.topInset
        width: parent.width * 0.17
        height: _camCol.implicitHeight + _m * 2
        cardRadius: _r * 1.3
        accent: fsd.accent
        // A telemetry dump, not something the driver acts on. Lighter ink than
        // the rest so it recedes instead of competing with the road.
        inkAlpha: 0.60
        // Hidden with the others when the drawer is open, which it was not —
        // it used to sit on top of the drawer's own panel.
        opacity: settingsDrawer.open ? 0.0 : 1.0
        visible: !settingsDrawer.open || opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }

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
    /*
     * The one number on this page the driver actually reads, so it is the one
     * thing allowed to look like an instrument: opaque enough to never fight
     * the road, ringed in the HUD accent, with the speed also stated as a bar
     * along the bottom of the pill.
     *
     * The bar is not decoration — a filling arc is readable from the corner of
     * an eye at a glance, which is the only kind of attention a moving car has
     * to spare for it.
     */
    HudPanel {
        id: speedPill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.05
        width: parent.width * 0.17
        height: parent.height * 0.115
        cardRadius: height / 2
        accent: fsd.accent
        inkAlpha: 0.82

        readonly property real kmh: carInfo.currVel * 3.6
        // 140 as full scale rather than the top speed of anything: past that the
        // bar would spend its whole life in the first third.
        readonly property real fraction: Math.max(0, Math.min(1, kmh / 140))

        Row {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -parent.height * 0.06
            spacing: _m * 0.4

            Text {
                id: _speedNum
                text: speedPill.kmh.toFixed(0)
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
                font.letterSpacing: 1.5
                font.family: "Segoe UI, Roboto, sans-serif"
                anchors.baseline: _speedNum.baseline
                width: implicitWidth
                height: implicitHeight
            }
        }

        // Track and fill, inset from the pill's rounded ends so neither runs
        // into the curve.
        Rectangle {
            id: speedTrack
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.16
            width: parent.width * 0.62
            height: 3
            radius: 1.5
            color: Qt.rgba(1, 1, 1, 0.14)

            Rectangle {
                width: parent.width * speedPill.fraction
                height: parent.height
                radius: parent.radius
                color: fsd.accent
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
            }
        }
    }

    // ============================================================
    // HUD — BOTTOM RIGHT: View buttons
    // ============================================================
    HudButton {
        id: viewToggle
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: _m
        anchors.bottomMargin: _m
        width: _btnW
        height: _btnH
        cardRadius: _r
        accent: fsd.accent
        textColor: fsd.textPri
        fontSize: _fSm
        text: topDownView ? "CHASE VIEW" : "TOP VIEW"
        onClicked: {
            topDownView = !topDownView
            topDownView ? applyTopView() : applyChaseView()
        }
    }

    HudButton {
        id: resetViewBtn
        anchors.right: viewToggle.left
        anchors.bottom: parent.bottom
        anchors.rightMargin: _m * 0.55
        anchors.bottomMargin: _m
        width: _btnW
        height: _btnH
        cardRadius: _r
        accent: fsd.accent
        textColor: fsd.textPri
        fontSize: _fSm
        text: "RESET VIEW"
        onClicked: resetCurrentView()
    }

    // ============================================================
    // LEFT DRAWER — Car Settings
    // ============================================================

    // Volume-style slider: same chrome as the WindowBar volume control, but the
    // fill and knob pick up the car colour like the theme toggle does.
    //
    // The track is a sunk well rather than a painted bar — the drawer is a
    // translucent surface, and a solid track on it reads as a seam.
    component StyledSlider: Slider {
        id: styled
        height: 30

        background: Rectangle {
            x: styled.leftPadding
            y: styled.topPadding + styled.availableHeight / 2 - height / 2
            width: styled.availableWidth
            height: 4
            radius: 2
            color: Qt.rgba(0, 0, 0, 0.40)

            Rectangle {
                width: styled.visualPosition * parent.width
                height: parent.height
                color: fsd.ego
                radius: 2
            }
        }

        handle: Rectangle {
            x: styled.leftPadding + styled.visualPosition * (styled.availableWidth - width)
            y: styled.topPadding + styled.availableHeight / 2 - height / 2
            width: styled.pressed ? 18 : 15
            height: width
            radius: width / 2
            color: styled.pressed ? "#ffffff" : fsd.ego
            border.color: "#ffffff"
            border.width: 1.5
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        }
    }

    /*
     * One control per setting: name on the left, live value on the right,
     * slider underneath.
     *
     * The value used to be glued onto the label ("Brightness: 1.00"), which
     * left the three numbers at three different x positions depending on how
     * long each word was — so they could not be compared or even easily found.
     * Right-aligned and monospaced, they form a column.
     */
    component SettingSlider: Column {
        id: sRow

        property string label: ""
        property alias  from:  sSlider.from
        property alias  to:    sSlider.to
        property alias  value: sSlider.value
        property int    decimals: 2

        signal moved(real v)

        spacing: _m * 0.12

        Item {
            width: parent.width
            height: _sLabel.implicitHeight

            Text {
                id: _sLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: sRow.label
                color: fsd.textSec
                font.pixelSize: _fSm
                font.letterSpacing: 0.8
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: sSlider.value.toFixed(sRow.decimals)
                color: fsd.textPri
                font.pixelSize: _fSm
                font.bold: true
                font.family: "monospace"
            }
        }

        StyledSlider {
            id: sSlider
            width: parent.width
            onValueChanged: sRow.moved(value)
        }
    }

    // Section heading. Small, spaced and quiet — it groups what follows without
    // competing with it, the same way the ambient-light page labels its blocks.
    component SectionLabel: Text {
        color: fsd.textSec
        font.pixelSize: _fSm * 0.92
        font.bold: true
        font.letterSpacing: 2.0
        opacity: 0.75
    }

    /*
     * Dims the scene while the drawer is out, and closes it on a tap anywhere
     * else. Before this the only way back was the Close button: a driver who
     * opened the drawer by accident had to find one specific target to undo it,
     * on a touchscreen, while moving.
     *
     * Hidden rather than transparent when shut — a full-page MouseArea left
     * lying over the scene would swallow every camera drag.
     */
    Rectangle {
        id: drawerScrim
        anchors.fill: parent
        z: 99
        color: Qt.rgba(0.01, 0.02, 0.04, 0.55)
        opacity: settingsDrawer.open ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }

        MouseArea {
            anchors.fill: parent
            onClicked: settingsDrawer.open = false
        }
    }

    Rectangle {
        id: settingsDrawer
        property bool open: false
        z: 100
        clip: true

        y: 0
        width: parent.width * 0.28
        height: parent.height

        x: open ? 0 : -width

        // OutCubic rather than InOutQuad: a panel that leaves the edge fast and
        // settles slowly reads as being pulled out, where a symmetric curve
        // reads as a slide show.
        Behavior on x {
            NumberAnimation {
                duration: 300; easing.type: Easing.OutCubic
                onRunningChanged: if (!running && settingsDrawer.open) colorWheel.requestPaint()
            }
        }
        onOpenChanged: if (open) colorWheel.requestPaint()

        // Nearly opaque. This one is a surface to read and aim at, not a window
        // onto the road, and it is the only panel with small hit targets on it.
        color: Qt.rgba(0.02, 0.04, 0.08, 0.94)

        // Only the free edge is rounded — the other three run off the screen,
        // and rounding those leaves slivers of scene in the corners.
        topRightRadius: _r * 2
        bottomRightRadius: _r * 2

        // Sheen across the panel rather than down it: the light in this scene
        // comes from above, and the HUD panels are lit the same way.
        Rectangle {
            anchors.fill: parent
            topRightRadius: parent.topRightRadius
            bottomRightRadius: parent.bottomRightRadius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.07) }
                GradientStop { position: 0.35; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.10) }
            }
        }

        // Lit edge where the panel meets the scene, in the car's own colour —
        // the drawer's whole subject is the car, so it is the one surface that
        // earns the paint colour rather than the HUD accent.
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 2
            color: fsd.ego
            opacity: 0.55
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Column {
            id: _drawerCol
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                margins: _m * 0.7
                // Clear the floating window bar. The panel itself still runs to
                // the top of the page, but its header used to sit behind the
                // bar — which draws above the whole scene — so the Close button
                // was covered by the home button and could not be tapped.
                topMargin: _m * 0.7 + root.topInset
            }
            // Tuned against the 1024×600 panel with the window bar's inset
            // already taken off the top: at 0.4 the last slider fell off the
            // bottom edge, and a control you cannot see is worse than a tight
            // one. The wheel below gives up height for the same reason.
            spacing: _m * 0.3

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

                /*
                 * Round, not a labelled pill.
                 *
                 * "× Close" spent a fifth of the drawer's width saying what the
                 * × already says, and it was the widest thing in the header. A
                 * circle is also a better touch target than a short wide box
                 * for a thumb coming in at an angle.
                 *
                 * U+00D7, for the reason spelled out in VirtualKeyboard: the
                 * prettier ✕ is a Dingbats glyph no font on the head unit
                 * carries, and it renders as nothing there.
                 */
                Rectangle {
                    id: closeBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: _btnH * 0.78
                    height: width
                    radius: width / 2
                    color: closeArea.containsMouse ? Qt.rgba(fsd.accent.r, fsd.accent.g, fsd.accent.b, 0.25)
                                                   : Qt.rgba(1, 1, 1, 0.06)
                    border.color: closeArea.containsMouse ? fsd.accent : Qt.rgba(1, 1, 1, 0.18)
                    border.width: 1
                    Behavior on color        { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: fsd.textPri
                        font.pixelSize: closeBtn.height * 0.62
                        font.bold: true
                        font.family: "Arial"
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: settingsDrawer.open = false
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Qt.rgba(1, 1, 1, 0.10)
            }

            SectionLabel { text: "ENVIRONMENT"; width: parent.width }

            // ---- Theme: same switch look as the ambient-light card ----
            Item {
                width: parent.width
                height: Math.max(themeTextCol.height, themeToggle.height)

                Column {
                    id: themeTextCol
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        text: darkTheme ? "Dark Theme" : "Light Theme"
                        color: fsd.textPri
                        font.pixelSize: _fSm
                        font.bold: true
                        height: implicitHeight
                    }
                    Text {
                        // Says what the switch does, rather than repeating the
                        // state the switch is already showing twice.
                        text: "Sky and ground"
                        color: fsd.textSec
                        font.pixelSize: _fSm * 0.88
                        height: implicitHeight
                    }
                }

                Rectangle {
                    id: themeToggle
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 26
                    radius: height / 2
                    color: darkTheme ? fsd.ego : Qt.rgba(1, 1, 1, 0.10)
                    border.color: darkTheme ? Qt.lighter(fsd.ego, 1.3) : Qt.rgba(1, 1, 1, 0.22)
                    border.width: 2
                    Behavior on color { ColorAnimation { duration: 200 } }

                    Rectangle {
                        width: parent.height * 0.72; height: width
                        radius: width / 2
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                        x: darkTheme ? parent.width - width - parent.height * 0.14
                                     : parent.height * 0.14
                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: darkTheme = !darkTheme
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Qt.rgba(1, 1, 1, 0.10)
            }

            // ---- Car Color ----
            SectionLabel { text: "PAINT"; width: parent.width }

            /*
             * The swatch, sitting in its own glow.
             *
             * A flat rectangle of colour states the value; the bloom behind it
             * shows what that paint does to the light around it, which is the
             * thing actually being chosen. The hex sits on top so the value is
             * still readable as a value.
             */
            Item {
                width: parent.width
                height: _m * 1.9

                Rectangle {
                    anchors.centerIn: swatch
                    width: swatch.width + _m * 0.5
                    height: swatch.height + _m * 0.5
                    radius: _r
                    color: fsd.ego
                    opacity: 0.28
                }

                Rectangle {
                    id: swatch
                    anchors.fill: parent
                    anchors.margins: _m * 0.14
                    radius: _r * 0.7
                    color: fsd.ego
                    border.color: Qt.rgba(1, 1, 1, 0.28)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: fsd.ego.toString().toUpperCase()
                        font.pixelSize: _fSm
                        font.bold: true
                        font.family: "monospace"
                        font.letterSpacing: 1.2
                        // Black on a pale car, white on a dark one — the paint
                        // covers the whole wheel, so neither works alone.
                        color: fsd.ego.hslLightness > 0.6 ? Qt.rgba(0, 0, 0, 0.75)
                                                          : Qt.rgba(1, 1, 1, 0.9)
                    }
                }
            }

            Canvas {
                id: colorWheel
                width: parent.width
                height: width * 0.54

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

            SettingSlider {
                id: brightnessSlider
                width: parent.width
                label: "Brightness"
                from: 0.05
                to: 1.0
                value: 1.0
                onMoved: {
                    colorWheel.pickedVal = value
                    applyColor()
                    colorWheel.requestPaint()
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Qt.rgba(1, 1, 1, 0.10)
            }

            SectionLabel { text: "FINISH"; width: parent.width }

            SettingSlider {
                id: metalSlider
                width: parent.width
                label: "Metalness"
                from: 0
                to: 1
                value: egoCar.carMetalness
                onMoved: {
                    egoCar.carMetalness = value
                    driveSettings.carMetalness = value
                }
            }

            SettingSlider {
                id: roughSlider
                width: parent.width
                label: "Roughness"
                from: 0
                to: 1
                value: egoCar.carRoughness
                onMoved: {
                    egoCar.carRoughness = value
                    driveSettings.carRoughness = value
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
        // Single funnel for every colour change — the wheel and the brightness
        // slider both come through here — so this is the only place the stored
        // copy has to be kept up to date. CarColors persists it from its own
        // Settings block and restores itself at boot, when the launcher
        // preview is created, so the persisted colour is visible from the
        // first frame.
        CarColors.setColor(colorWheel.pickedHue, colorWheel.pickedSat, brightnessSlider.value)
    }

    function applyChaseView() {
        if (!viewReady) {
            orbitOrigin.position = chaseOrigin
            orbitOrigin.eulerRotation = chaseRotation
            camera.position = Qt.vector3d(0, 0, chaseDistance)
            return
        }
        viewSwitchAnim.stop()
        viewPosAnim.from = orbitOrigin.position
        viewRotAnim.from = orbitOrigin.eulerRotation
        viewPosAnim.to = chaseOrigin
        viewRotAnim.to = chaseRotation
        camera.position = Qt.vector3d(0, 0, chaseDistance)
        viewSwitchAnim.start()
    }

    function applyTopView() {
        if (!viewReady) {
            orbitOrigin.position = topOrigin
            orbitOrigin.eulerRotation = topRotation
            camera.position = Qt.vector3d(0, 0, topDistance)
            return
        }
        viewSwitchAnim.stop()
        viewPosAnim.from = orbitOrigin.position
        viewRotAnim.from = orbitOrigin.eulerRotation
        viewPosAnim.to = topOrigin
        viewRotAnim.to = topRotation
        camera.position = Qt.vector3d(0, 0, topDistance)
        viewSwitchAnim.start()
    }

    function resetCurrentView() {
        if (topDownView)
            applyTopView()
        else
            applyChaseView()
    }

    function closeSettings() {
        settingsDrawer.open = false
    }

    // theme preset: writes the individual environment toggles. The theme
    // switch in the drawer is the only control left for these.
    function applyTheme() {
        asphaltRoad = !darkTheme        // light = asphalt, dark = neon
        hdriIndex = darkTheme ? 0 : 1   // ferndale / wide_street
        probeExposure = darkTheme ? 0.1 : 0.3
    }
    onDarkThemeChanged: {
        applyTheme()
        driveSettings.darkTheme = darkTheme
    }

    Component.onCompleted: {
        // Restore first: applyTheme() below reads darkTheme, and the colour
        // has to be rebuilt from the stored hue/sat/value before anything
        // paints, or the car flashes its default blue on every start.
        //
        // Assigning brightnessSlider.value fires its onValueChanged, which
        // calls applyColor() — so hue and saturation are set ahead of it.
        // The colour itself lives in CarColors (shared with the launcher
        // preview, restored at boot), so this scene only syncs its picker.
        root.darkTheme         = driveSettings.darkTheme
        colorWheel.pickedHue   = CarColors.carHue
        colorWheel.pickedSat   = CarColors.carSat
        colorWheel.pickedVal   = CarColors.carVal
        brightnessSlider.value = CarColors.carVal
        egoCar.carMetalness    = driveSettings.carMetalness
        egoCar.carRoughness    = driveSettings.carRoughness
        applyColor()
        colorWheel.requestPaint()

        applyChaseView()
        applyTheme()
        viewReady = true
    }
}
