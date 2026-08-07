import QtQuick
import QtQuick3D
import QtQuick.Effects

import "../models_3d/audi_low_poly"

/*
 * Home-screen preview of the Drive View scene.
 *
 * Same ego car and same instancing tables as Scene3D, so it shows the live
 * detections rather than a mock-up — but with none of the HUD, no orbit
 * controller and no settings drawer. Leaving the controller out is deliberate:
 * the tile below has to stay clickable, and a drag on the home screen should
 * scroll the launcher, not spin a camera.
 */
Item {
    id: root

    // detectCount is uninitialised garbage until the first message arrives,
    // which is what the > 1000 guard in Scene3D is working around. Same guard
    // here, but exposed as a flag so the tile can say "OFFLINE" instead of
    // printing a nonsense number.
    readonly property bool hasSignal: detectionModel.detectCount >= 0
                                      && detectionModel.detectCount < 1000

    property color accent: "#4a9eff"

    // Corner radius of the card this sits in. A View3D renders a plain
    // rectangle, so without masking the road spills out past the card's rounded
    // corners and the tile is the only square one on the launcher.
    property real cornerRadius: 28

    // Drawn in QML rather than loaded as an image on purpose: a bitmap mask gets
    // stretched to the item, so a round corner in the file comes out as an
    // ellipse on a card that is not square. A Rectangle's radius stays a radius.
    Item {
        id: edgeMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: "white"
        }
    }

    View3D {
        id: view
        anchors.fill: parent

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: edgeMask
            // Cuts at the halfway point of the mask's own antialiased edge, so
            // the corners come out as crisp as the cards either side rather
            // than fading into them.
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.1
        }

        environment: SceneEnvironment {
            // Transparent so the tile's own glass gradient shows through and
            // the preview reads as part of the card, not a video pasted on it.
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            // Medium, not High: this renders continuously behind the whole
            // launcher, so it gets the cheaper setting of the two.
            antialiasingQuality: SceneEnvironment.Medium
            // See Scene3D — kills the specular glitter on the road's grooves,
            // which MSAA cannot touch because it is a shading artefact.
            specularAAEnabled: true
        }

        DirectionalLight { eulerRotation.x: -60; eulerRotation.y: 30;   brightness: 1.1 }
        DirectionalLight { eulerRotation.x: -20; eulerRotation.y: -150; color: "#7799ff"; brightness: 0.5 }

        // Fixed chase view — same angle the full page opens on, just pulled
        // back further to suit the tile.
        //
        // The pivot sits 3 m ahead of the car rather than on it, which drops
        // the car below centre and hands the extra frame to the road in front.
        // What is ahead matters more than what is behind.
        Node {
            id: orbitOrigin
            position: Qt.vector3d(0, 0, -300)
            eulerRotation: Qt.vector3d(-42, 0, 0)

            PerspectiveCamera {
                id: camera
                position: Qt.vector3d(0, 0, 1250)
                fieldOfView: 60
                clipNear: 1
                clipFar: 100000
            }
        }

        // Same road as the full page, but much wider than it.
        //
        // The card wants to be full of road, not to hold a small pool of it, so
        // the range fade is pushed out past the frame and only shows up as a
        // gentle dimming towards the far end. The border feather is the mask's
        // job instead — a radial world-space fade cannot square up with a
        // rectangular card anyway, because the top of the frame is 35 m away
        // while the bottom is 6 m.
        //
        // Offset forward for the same reason as the pivot: it puts the centre
        // of the fade ahead of the car, so the road stays strong further up the
        // frame and dims off behind.
        GroundPlane {
            y: -100
            z: -1200
            size: 12000
        }

        Node {
            position: Qt.vector3d(0, -100, 0)
            Audi_rs7_free__low_poly {
                scale: Qt.vector3d(137, 250, 137)
                eulerRotation: Qt.vector3d(0, -90, 0)
                carColor: root.accent
                carMetalness: 0.3
                carRoughness: 0.15
            }
        }

        // The detection classes, sharing the C++ instancing tables with
        // the full-screen scene — no extra subscription, no second copy.
        Node {
            Model {
                source: "qrc:/meshes/plane__0_walkpose_mesh.mesh"
                instancing: planeInstancing
                castsShadows: false
                receivesShadows: false
                materials: PrincipledMaterial { baseColor: "#c8ccd2"; metalness: 0.1; roughness: 0.5 }
            }
            Model {
                source: "#Cube"
                instancing: cubeInstancing
                castsShadows: false
                receivesShadows: false
                materials: PrincipledMaterial { baseColor: "#c8ccd2"; metalness: 0.1; roughness: 0.5 }
            }
            Model {
                source: "qrc:/models_3d/tesla_low_poly/meshes/object_0_mesh.mesh"
                instancing: carInstancing
                castsShadows: false
                receivesShadows: false
                materials: PrincipledMaterial {
                    // same silver texture as the full scene
                    // Same split as the full scene: mostly emissive so a car
                    // turned away from the key light still reads silver rather
                    // than grey. See Scene3D.qml for the numbers.
                    baseColor: Qt.rgba(1, 1, 1, 1)
                    baseColorMap: teslaTex
                    emissiveMap: teslaTex
                    emissiveFactor: Qt.vector3d(0.65, 0.65, 0.65)
                    metalness: 0.0; roughness: 0.9
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
}
