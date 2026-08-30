import QtQuick
import QtQuick3D

Node {
    id: node

    // Resources
    property url textureData: "qrc:/audi/models_3d/audi_low_poly/maps/textureData.png"
    property url textureData63: "qrc:/audi/models_3d/audi_low_poly/maps/textureData63.png"
    property url textureData53: "qrc:/audi/models_3d/audi_low_poly/maps/textureData53.jpg"
    property url textureData69: "qrc:/audi/models_3d/audi_low_poly/maps/textureData69.png"
    property url textureData47: "qrc:/audi/models_3d/audi_low_poly/maps/textureData47.jpg"

    // car user modifiable properties
    property color carColor: "#0039da"
    property real carMetalness: 0.37638211250305176
    property real carRoughness: 0.1

    // wheel spin: wheelSpeed is the angular velocity in deg/s (driven by the
    // car's velocity from outside); wheelAngle accumulates it while moving
    property real wheelSpeed: 0
    property real wheelAngle: 0

    // Integrated on real frame time, like the city scroll in Environment3D —
    // a fixed-step Timer let the wheels run slow under load (a skid on a busy
    // Jetson). frameTime is capped so a hitch resumes smoothly instead of
    // snapping the spin.
    FrameAnimation {
        running: Math.abs(node.wheelSpeed) > 0.01
        onTriggered: {
            const a = node.wheelAngle
                    + node.wheelSpeed * Math.min(frameTime, 0.1)
            // Wrap to 0..360. Visually identical, but eulerRotation is float:
            // an angle left to grow reaches ~3e6 degrees after an hour at speed,
            // where the float step is a quarter of a degree and the spin visibly
            // stutters. Math.floor rather than %, so it also wraps in reverse.
            node.wheelAngle = a - Math.floor(a / 360) * 360
        }
    }

    Texture {
        id: _0_texture
        generateMipmaps: true
        mipFilter: Texture.Linear
        source: node.textureData47
    }
    Texture {
        id: _4_texture
        generateMipmaps: true
        mipFilter: Texture.Linear
        source: node.textureData
    }
    Texture {
        id: _3_texture
        generateMipmaps: true
        mipFilter: Texture.Linear
        source: node.textureData69
    }
    Texture {
        id: _1_texture
        generateMipmaps: true
        mipFilter: Texture.Linear
        source: node.textureData53
    }
    Texture {
        id: _2_texture
        generateMipmaps: true
        mipFilter: Texture.Linear
        source: node.textureData63
    }
    PrincipledMaterial {
        id: material_15_material
        objectName: "material_15"
        baseColorMap: _3_texture
        metalness: 0.5775255560874939
        roughness: 0.19085468351840973
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_002_material
        objectName: "Material.002"
        baseColorMap: _2_texture
        metalness: 0.5775255560874939
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Mask
        depthDrawMode: PrincipledMaterial.OpaquePrePassDepthDraw
        alphaCutoff: 0.7177164554595947
    }
    PrincipledMaterial {
        id: node3_002_material
        objectName: "3.002"
        baseColor: "#ff3c3c3c"
        metalness: 1
        roughness: 0.3127598166465759
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_17_material
        objectName: "material_17"
        baseColor: "#ff2c2c2c"
        baseColorMap: _4_texture
        metalness: 0.6628591418266296
        roughness: 0.09333056956529617
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Mask
        depthDrawMode: PrincipledMaterial.OpaquePrePassDepthDraw
        alphaCutoff: 0.13866709172725677
    }
    PrincipledMaterial {
        id: material_18_material
        objectName: "material_18"
        metalness: 0.37028685212135315
        roughness: 0.032378003001213074
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_19_material
        objectName: "material_19"
        baseColor: "#ff000000"
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: diffuseGrey_material
        objectName: "DiffuseGrey"
        baseColor: "#ff525151"
        roughness: 1
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: node2232_material
        objectName: "2232"
        baseColor: "#ffa0a0a0"
        metalness: 1
        roughness: 0.2788580060005188
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_22_material
        objectName: "material_22"
        baseColor: "#ff000000"
        roughness: 1
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_7_material
        objectName: "material_7"
        baseColor: "#ffa2a2a2"
        metalness: 1
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_material
        objectName: "material"
        baseColor: carColor
        metalness: carMetalness
         // metalness: 0.6
         roughness: carRoughness
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: node3_001_material
        objectName: "3.001"
        baseColor: "#ff343434"
        metalness: 1
        roughness: 0.30933427810668945
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_2_material
        objectName: "material_2"
        baseColor: "#ff242323"
        metalness: 1
        roughness: 0.3737123906612396
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_3_material
        objectName: "material_3"
        baseColor: "#ff414141"
        metalness: 1
        roughness: 0.08114005625247955
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_4_material
        objectName: "material_4"
        baseColor: "#ff272727"
        metalness: 0.412953644990921
        roughness: 0.7699040770530701
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_5_material
        objectName: "material_5"
        metalness: 1
        roughness: 0.1786641627550125
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_6_material
        objectName: "material_6"
        baseColor: "#ff484848"
        metalness: 1
        roughness: 0.3737123906612396
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_8_material
        objectName: "material_8"
        baseColor: "#ffc5c5c5"
        metalness: 1
        roughness: 0.09942582994699478
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_9_material
        objectName: "material_9"
        baseColor: "#ff212121"
        roughness: 1
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: glass_001_material
        objectName: "Glass.001"
        baseColor: "#ff7a7a7a"
        metalness: 1
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_11_material
        objectName: "material_11"
        baseColorMap: _0_texture
        roughness: 0.8211145401000977
        emissiveMap: _0_texture
        emissiveFactor: Qt.vector3d(1, 1, 1)
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: material_001_material
        objectName: "Material.001"
        baseColorMap: _1_texture
        metalness: 1
        emissiveMap: _1_texture
        emissiveFactor: Qt.vector3d(1, 1, 1)
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: glaaa_material
        objectName: "glaaa"
        baseColor: "#87ffffff"
        metalness: 1
        roughness: 0.050663772970438004
        emissiveMap: _1_texture
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Blend
    }

    // Nodes:
    Node {
        id: sketchfab_model
        objectName: "Sketchfab_model"
        rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
        Node {
            id: rs7_fbx
            objectName: "rs7.fbx"
            rotation: Qt.quaternion(0.707107, 0.707107, 0, 0)
            scale: Qt.vector3d(0.01, 0.01, 0.01)
            Node {
                id: rootNode
                objectName: "RootNode"
                Node {
                    id: plane
                    objectName: "Plane"
                    rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
                    scale: Qt.vector3d(100, 100, 100)
                    Model {
                        id: plane__________________0
                        objectName: "Plane_����������������_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane__________________0_mesh.mesh"
                        materials: [
                            material_material
                        ]
                    }
                    Model {
                        id: plane_3_001_0
                        objectName: "Plane_3.001_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_3_001_0_mesh.mesh"
                        materials: [
                            node3_001_material
                        ]
                    }
                    Model {
                        id: plane_2_0
                        objectName: "Plane_2_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_2_0_mesh.mesh"
                        materials: [
                            material_2_material
                        ]
                    }
                    Model {
                        id: plane_1_0
                        objectName: "Plane_1_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_1_0_mesh.mesh"
                        materials: [
                            material_3_material
                        ]
                    }
                    Model {
                        id: plane______________0
                        objectName: "Plane_������������_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane______________0_mesh.mesh"
                        materials: [
                            material_4_material
                        ]
                    }
                    Model {
                        id: plane___________________0
                        objectName: "Plane_������ ����������_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane___________________0_mesh.mesh"
                        materials: [
                            material_5_material
                        ]
                    }
                    Model {
                        id: plane_____________1_0
                        objectName: "Plane_������������1_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_____________1_0_mesh.mesh"
                        materials: [
                            material_6_material
                        ]
                    }
                    Model {
                        id: plane________________0
                        objectName: "Plane_��������������_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane________________0_mesh.mesh"
                        materials: [
                            material_7_material
                        ]
                    }
                    Model {
                        id: plane______________029
                        objectName: "Plane_������������_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane______________0_mesh30.mesh"
                        materials: [
                            material_8_material
                        ]
                    }
                    Model {
                        id: plane____________0
                        objectName: "Plane_����������_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane____________0_mesh.mesh"
                        materials: [
                            material_9_material
                        ]
                    }
                }
                Node {
                    id: plane_002
                    objectName: "Plane.002"
                    rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
                    scale: Qt.vector3d(100, 100, 100)
                    Model {
                        id: plane_002_Glass_001_0
                        objectName: "Plane.002_Glass.001_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_002_Glass_001_0_mesh.mesh"
                        materials: [
                            glass_001_material
                        ]
                    }
                }
                Node {
                    id: circle
                    objectName: "Circle"
                    position: Qt.vector3d(-193.856, 48.8515, 7.45915)
                    rotation: Qt.quaternion(0.579228, -0.579228, -0.40558, 0.40558)
                    scale: Qt.vector3d(101.877, 101.877, 101.877)
                    Model {
                        id: circle______________0
                        objectName: "Circle_������������_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/circle______________0_mesh.mesh"
                        materials: [
                            material_8_material
                        ]
                    }
                }
                Node {
                    id: plane_001
                    objectName: "Plane.001"
                    rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
                    scale: Qt.vector3d(100, 100, 100)
                    Model {
                        id: plane_001_______________________0
                        objectName: "Plane.001_������������ ��������_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_001_______________________0_mesh.mesh"
                        materials: [
                            material_11_material
                        ]
                    }
                }
                Node {
                    id: plane_004
                    objectName: "Plane.004"
                    rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
                    scale: Qt.vector3d(100, 100, 100)
                    Model {
                        id: plane_004_Material_001_0
                        objectName: "Plane.004_Material.001_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_004_Material_001_0_mesh.mesh"
                        materials: [
                            material_001_material
                        ]
                    }
                }
                Node {
                    id: plane_005
                    objectName: "Plane.005"
                    rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
                    scale: Qt.vector3d(100, 100, 100)
                    Model {
                        id: plane_005_glaaa_0
                        objectName: "Plane.005_glaaa_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_005_glaaa_0_mesh.mesh"
                        materials: [
                            glaaa_material
                        ]
                    }
                }
                Node {
                    id: plane_006
                    objectName: "Plane.006"
                    position: Qt.vector3d(-1.14343, 0, 0)
                    rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
                    scale: Qt.vector3d(100, 100, 100)
                    Model {
                        id: plane_006_Material_002_0
                        objectName: "Plane.006_Material.002_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_006_Material_002_0_mesh.mesh"
                        materials: [
                            material_002_material
                        ]
                    }
                }
                Node {
                    id: plane_007
                    objectName: "Plane.007"
                    position: Qt.vector3d(-192.907, 46.3621, -18.3771)
                    rotation: Qt.quaternion(0.500483, -0.499516, 0.499517, -0.500483)
                    scale: Qt.vector3d(100, 100, 100)
                    Model {
                        id: plane_007_rs7_0
                        objectName: "Plane.007_rs7_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_007_rs7_0_mesh.mesh"
                        materials: [
                            material_15_material
                        ]
                    }
                }
                Node {
                    id: plane_008
                    objectName: "Plane.008"
                    rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
                    scale: Qt.vector3d(100, 100, 100)
                    Model {
                        id: plane_008_3_002_0
                        objectName: "Plane.008_3.002_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_008_3_002_0_mesh.mesh"
                        materials: [
                            node3_002_material
                        ]
                    }
                }
                Node {
                    id: plane_009
                    objectName: "Plane.009"
                    rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
                    scale: Qt.vector3d(100, 100, 100)
                    Model {
                        id: plane_009________________0
                        objectName: "Plane.009_��������������_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_009________________0_mesh.mesh"
                        materials: [
                            material_17_material
                        ]
                    }
                }
                Node {
                    id: plane_010
                    objectName: "Plane.010"
                    rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
                    scale: Qt.vector3d(100, 100, 100)
                    Model {
                        id: plane_010____________0
                        objectName: "Plane.010_����������_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/plane_010____________0_mesh.mesh"
                        materials: [
                            material_9_material
                        ]
                    }
                }
                Node {
                    id: object_4
                    objectName: "Object_4"
                    position: Qt.vector3d(107.919, 28.4113, 70.9414)
                    rotation: Qt.quaternion(0.5, -0.5, -0.5, -0.5)
                    scale: Qt.vector3d(57.3952, 45.6906, 45.6906)
                    Model {
                        id: object_4_________1_0
                        objectName: "Object_4_��������1_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/object_4_________1_0_mesh.mesh"
                        eulerRotation.x: -node.wheelAngle
                        materials: [
                            material_18_material
                        ]
                    }
                    Model {
                        id: object_4_________2_0
                        objectName: "Object_4_��������2_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/object_4_________2_0_mesh.mesh"
                        eulerRotation.x: -node.wheelAngle
                        materials: [
                            material_19_material
                        ]
                    }
                    Model {
                        id: object_4_DiffuseGrey_0
                        objectName: "Object_4_DiffuseGrey_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/object_4_DiffuseGrey_0_mesh.mesh"
                        eulerRotation.x: -node.wheelAngle
                        materials: [
                            diffuseGrey_material
                        ]
                    }
                    Model {
                        id: object_4_2232_0
                        objectName: "Object_4_2232_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/object_4_2232_0_mesh.mesh"
                        eulerRotation.x: -node.wheelAngle
                        materials: [
                            node2232_material
                        ]
                    }
                    Model {
                        id: object_4__________0
                        objectName: "Object_4_��������_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/object_4__________0_mesh.mesh"
                        eulerRotation.x: -node.wheelAngle
                        materials: [
                            material_22_material
                        ]
                    }
                }
                Node {
                    id: object_4_001
                    objectName: "Object_4.001"
                    position: Qt.vector3d(-124.468, 28.3065, 70.9414)
                    rotation: Qt.quaternion(0.5, -0.5, -0.5, -0.5)
                    scale: Qt.vector3d(56.2971, 44.8164, 44.8164)
                    Model {
                        id: object_4_001_________1_0
                        objectName: "Object_4.001_��������1_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/object_4_001_________1_0_mesh.mesh"
                        eulerRotation.x: -node.wheelAngle
                        materials: [
                            material_18_material
                        ]
                    }
                    Model {
                        id: object_4_001_________2_0
                        objectName: "Object_4.001_��������2_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/object_4_001_________2_0_mesh.mesh"
                        eulerRotation.x: -node.wheelAngle
                        materials: [
                            material_19_material
                        ]
                    }
                    Model {
                        id: object_4_001_DiffuseGrey_0
                        objectName: "Object_4.001_DiffuseGrey_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/object_4_001_DiffuseGrey_0_mesh.mesh"
                        eulerRotation.x: -node.wheelAngle
                        materials: [
                            diffuseGrey_material
                        ]
                    }
                    Model {
                        id: object_4_001_2232_0
                        objectName: "Object_4.001_2232_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/object_4_001_2232_0_mesh.mesh"
                        eulerRotation.x: -node.wheelAngle
                        materials: [
                            node2232_material
                        ]
                    }
                    Model {
                        id: object_4_001__________0
                        objectName: "Object_4.001_��������_0"
                        source: "qrc:/audi/models_3d/audi_low_poly/meshes/object_4_001__________0_mesh.mesh"
                        eulerRotation.x: -node.wheelAngle
                        materials: [
                            material_22_material
                        ]
                    }
                }
            }
        }
    }

    // Animations:
}
