import QtQuick
import QtQuick3D

Node {
    id: node

    // Resources
    property url textureData: "maps/textureData.png"
    Texture {
        id: _0_texture
        generateMipmaps: true
        mipFilter: Texture.Linear
        source: node.textureData
    }
    PrincipledMaterial {
        id: node767c8b7b_1260_4325_b83f_f635800d9059_Standard00E280_material
        objectName: "767c8b7b_1260_4325_b83f_f635800d9059_Standard00E280"
        baseColorMap: _0_texture
        roughness: 0.6000000238418579
        emissiveMap: _0_texture
        emissiveFactor: Qt.vector3d(0.5, 0.5, 0.5)
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }

    // Nodes:
    Node {
        id: sketchfab_model
        objectName: "Sketchfab_model"
        rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
        Node {
            id: node2e6acfb837fa495687fc45736746c77f_obj_cleaner_materialmerger_gles
            objectName: "2e6acfb837fa495687fc45736746c77f.obj.cleaner.materialmerger.gles"
            Model {
                id: object_2
                objectName: "Object_2"
                source: "meshes/object_0_mesh.mesh"
                materials: [
                    node767c8b7b_1260_4325_b83f_f635800d9059_Standard00E280_material
                ]
            }
        }
    }

    // Animations:
}
