import QtQuick
import QtQuick3D

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

    View3D {
        id: view
        anchors.fill: parent

        environment: SceneEnvironment {
            // Transparent so the tile's own glass gradient shows through and
            // the preview reads as part of the card, not a video pasted on it.
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            // Medium, not High: this renders continuously behind the whole
            // launcher, so it gets the cheaper setting of the two.
            antialiasingQuality: SceneEnvironment.Medium
        }

        DirectionalLight { eulerRotation.x: -60; eulerRotation.y: 30;   brightness: 1.1 }
        DirectionalLight { eulerRotation.x: -20; eulerRotation.y: -150; color: "#7799ff"; brightness: 0.5 }

        // Fixed chase view — same angle the full page opens on, just pulled
        // back further to suit the tile.
        Node {
            id: orbitOrigin
            eulerRotation: Qt.vector3d(-42, 0, 0)

            PerspectiveCamera {
                id: camera
                position: Qt.vector3d(0, 0, 1250)
                fieldOfView: 60
                clipNear: 1
                clipFar: 100000
            }
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

        // The three detection classes, sharing the C++ instancing tables with
        // the full-screen scene — no extra subscription, no second copy.
        Node {
            Model {
                source: "qrc:/meshes/plane__0_mesh.mesh"
                instancing: planeInstancing
                materials: PrincipledMaterial { baseColor: "#c8ccd2"; metalness: 0.1; roughness: 0.5 }
            }
            Model {
                source: "#Cube"
                instancing: cubeInstancing
                materials: PrincipledMaterial { baseColor: "#c8ccd2"; metalness: 0.1; roughness: 0.5 }
            }
            Model {
                source: "qrc:/meshes/car_mesh.mesh"
                instancing: carInstancing
                materials: PrincipledMaterial { baseColor: "#c8ccd2"; metalness: 0.1; roughness: 0.5 }
            }
        }
    }
}
