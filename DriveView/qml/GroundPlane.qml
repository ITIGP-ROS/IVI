import QtQuick
import QtQuick3D

/*
 * The road surface under the ego car — chevron block paving, no lane markings.
 *
 * Markings are deliberately absent. We have no idea where the real lanes are;
 * painting some on would be inventing road geometry the sensors never reported,
 * and a driver reading a lane line that isn't there is worse than no line.
 *
 * The surface fades to nothing towards the rim rather than ending at a hard
 * edge, so the visible road *is* the detection envelope: where the paving stops
 * is where the system stops knowing.
 *
 * Textures come from textures/generate_road.py. Scene lights do all the
 * shading — the maps carry no baked lighting, which is why this still looks
 * right when the camera orbits.
 */
Model {
    id: ground

    // Full width of the plane in scene units. 1 m = 100 units (box_transform.cpp
    // scales metres by 100), so this is a 70 m square.
    //
    // Sized against the fade in range_fade.png, not against the sensor range:
    // the texture reaches zero alpha at 0.8 of the half-width, so changing this
    // moves where the road disappears. 70 m puts that at ~28 m, just past the
    // top of the chase view.
    //
    // Making this larger is always safe: every point on the plane's boundary is
    // at radius >= 1.0, where the fade is already zero, so the plane's own edge
    // can never show up as a hard line.
    property real size: 7000

    // Scene units per texture tile. 250 = one 2.5 m tile, which makes each
    // paving cell 62 cm across — about life size, and matching the reference.
    property real tileSize: 250

    readonly property real _tiles: size / tileSize

    source: "#Rectangle"

    // "#Rectangle" is 100x100 and faces +Z; lay it flat, normal up.
    eulerRotation.x: -90
    scale: Qt.vector3d(size / 100, size / 100, 1)

    // Shadows land on it, but it must not cast one — it is the floor, and a
    // plane this size self-shadowing at a grazing sun angle just produces acne.
    castsShadows: false
    receivesShadows: true

    materials: PrincipledMaterial {
        baseColorMap: Texture {
            source: "qrc:/textures/road_basecolor.png"
            scaleU: ground._tiles; scaleV: ground._tiles
            tilingModeHorizontal: Texture.Repeat
            tilingModeVertical: Texture.Repeat
            generateMipmaps: true
            mipFilter: Texture.Linear
        }

        normalMap: Texture {
            source: "qrc:/textures/road_normal.png"
            scaleU: ground._tiles; scaleV: ground._tiles
            tilingModeHorizontal: Texture.Repeat
            tilingModeVertical: Texture.Repeat
            generateMipmaps: true
            mipFilter: Texture.Linear
        }
        // Higher than it was for tarmac. The grooves are the whole look — the
        // chamfer either side of one is what catches the highlight that makes
        // the paving read as three-dimensional rather than printed on.
        //
        // Held down to 0.55 all the same. Past that the bevels start throwing
        // a hard specular streak where the low fill light rakes across them,
        // and it crawls as the camera moves.
        normalStrength: 0.55

        roughnessMap: Texture {
            source: "qrc:/textures/road_roughness.png"
            scaleU: ground._tiles; scaleV: ground._tiles
            tilingModeHorizontal: Texture.Repeat
            tilingModeVertical: Texture.Repeat
            generateMipmaps: true
            mipFilter: Texture.Linear
        }
        roughnessChannel: Material.R

        // The range fade. Unlike the others this is not tiled — it spans the
        // plane exactly once, so its centre sits on the ego car.
        opacityMap: Texture {
            source: "qrc:/textures/range_fade.png"
            tilingModeHorizontal: Texture.ClampToEdge
            tilingModeVertical: Texture.ClampToEdge
            generateMipmaps: true
            mipFilter: Texture.Linear
        }
        opacityChannel: Material.R

        alphaMode: PrincipledMaterial.Blend
        metalness: 0.0
    }
}
