import QtQuick
import QtQuick3D

// Ground + road environment for the detection visualization.
// Two styles:
//   neon (default) — Outrun-style: near-black ground, dark road, glowing
//                     magenta edge lines + scrolling city of neon cubes
//   asphalt        — realistic PBR asphalt (EosADAS texture set) + white edges
Node {
    id: root

    property bool asphalt: false

    // tile mode: the mini scene draws the road over a transparent glass
    // card, so it can drop the opaque ground strip and the scrolling city
    property bool showGround: true
    property bool showCity: true

    // created city entries (for teardown on theme/palette change)
    property var cityEntries: []

    // the city palette depends on the theme (asphalt flag) -> rebuild
    onAsphaltChanged: rebuildCity()

    // ground level — detection box bottoms sit at ~ -1.36 m median in the
    // velo frame (echoed /object_detections_3d), i.e. y ≈ -136 Qt units.
    // Keep the floor a few units below that so nothing clips.
    readonly property real floorY: -142

    // Half the road width, in Qt units (100 = 1 m). The lane markings, the
    // asphalt tiling and the gap to the city all key off this, so widening the
    // road means changing this one number and nothing else — the edge lines
    // used to be a separate literal that silently had to match.
    readonly property real roadHalfWidth: 810   // 16.2 m across

    // ---- GROUND ----------------------------------------------------------
    Model {
        id: ground
        source: "#Rectangle"
        visible: root.showGround
        y: floorY
        eulerRotation.x: -90
        // 12000-wide x 24000-long strip. Width tracks the city: the outermost
        // facade is at cityInset + 3450 = 5550, and half of 12000 is 6000, so
        // the buildings still stand on ground rather than over the void.
        scale: Qt.vector3d(120, 240, 1)
        receivesShadows: false
        castsShadows: false
        materials: groundMaterial

        PrincipledMaterial {
            id: groundMaterial
            roughness: 1
            metalness: 0
            baseColor: "#101014"
            cullMode: Material.NoCulling
        }
    }

    // asphalt texture set (asphalt style only)
    Texture {
        id: asphaltTex
        source: "qrc:/img/Road_DiagonalLightBrushing_color.png"
        generateMipmaps: true
        mipFilter: Texture.Linear
        tilingModeHorizontal: Texture.Repeat
        tilingModeVertical: Texture.Repeat
        // UVs run 0..1 across the road quad however wide it is, so the tile
        // count has to track the width or the grain stretches with it. 26 was
        // tuned for a 500-unit half-width.
        scaleU: 26 * root.roadHalfWidth / 500
        scaleV: 26
    }
    Texture {
        id: asphaltNormal
        source: "qrc:/img/Road_DiagonalLightBrushing_normal.png"
        generateMipmaps: true
        mipFilter: Texture.Linear
        tilingModeHorizontal: Texture.Repeat
        tilingModeVertical: Texture.Repeat
        // Must match asphaltTex exactly or the bumps desync from the colour.
        scaleU: 26 * root.roadHalfWidth / 500
        scaleV: 26
    }

    // ---- ROAD ------------------------------------------------------------
    // one straight 2-lane road along Z (KITTI forward = -Z), centered on origin
    Model {
        id: roadSurface
        source: "#Rectangle"
        y: floorY + 0.5
        eulerRotation.x: -90
        // #Rectangle is 100x100 local units, hence the /100
        scale: Qt.vector3d(root.roadHalfWidth * 2 / 100, 120, 1)   // x 12000 long (Z)
        receivesShadows: false
        castsShadows: false
        materials: roadMaterial
    }

    PrincipledMaterial {
        id: roadMaterial
        baseColor: "#1e1e26"
        roughness: 0.9
        metalness: 0
        cullMode: Material.NoCulling
    }

    // lane markings (thin strips above the asphalt)
    // Inset a little from the physical edge so the asphalt still shows outside
    // the line. Their thickness is deliberately NOT scaled with the road: a
    // painted line is a fixed real-world width whatever the road is doing.
    readonly property real edgeLineX: roadHalfWidth * 0.96

    // left edge solid line (magenta in neon style)
    Model {
        id: leftEdge
        source: "#Rectangle"
        x: -root.edgeLineX
        y: floorY + 1
        eulerRotation.x: -90
        scale: Qt.vector3d(0.35, 120, 1)
        receivesShadows: false
        castsShadows: false
        materials: edgeMaterial
    }
    // right edge solid line (magenta in neon style)
    Model {
        id: rightEdge
        source: "#Rectangle"
        x: root.edgeLineX
        y: floorY + 1
        eulerRotation.x: -90
        scale: Qt.vector3d(0.35, 120, 1)
        receivesShadows: false
        castsShadows: false
        materials: edgeMaterial
    }

    PrincipledMaterial {
        id: edgeMaterial
        baseColor: "#00e5ff"
        lighting: PrincipledMaterial.NoLighting
        cullMode: Material.NoCulling
    }

    // Distance from the centre line to the nearest building facade. Widest
    // building is 3000 and the facade jitter adds up to 450, so the outermost
    // wall lands at cityInset + 3450 — the ground strip has to reach past it.
    readonly property real cityInset: 2100


    // ---- MOVING CITY (neon style) ---------------------------------------
    // Instanced building cubes on both sides of the road, scrolling toward
    // the camera in a seamless loop (Outrun style).
    // Rows run from 100 m BEHIND the ego car (z=0) to the road's far end
    // (z=-6000) — nothing past the road at rest, and the loop keeps rows
    // behind the car at all times (nearest row is 4 m behind at loop start).
    // Pattern: deterministic 12-row cycle, spacing 800 -> the city tiles
    // perfectly every 12*800 = 9600 units, and the model animates by exactly
    // one period (-9600 -> 0) so the loop has no seam. Building depth stays
    // below the spacing (max 760 < 800) so cubes never overlap each other.
    // Buildings are BIG and drastically varied (8..20 m wide, 3..7.6 m deep,
    // 3..40 m tall); their inner edge sits cityInset..cityInset+4.5 m from the
    // road centre, and outer edges stay inside the 12000-wide strip.
    // Depth haze is NOT baked into the city: the whole city is one opaque
    // layer — the far end fades via SceneEnvironment fog (Scene3D.qml),
    // which is world-space and seamless, and also hides the loop-wrap pop
    // beyond the road end. No opacity bands -> no banding and no flash at
    // the loop boundary.
    Node {
        id: cityGroup
        visible: root.showCity
        position: Qt.vector3d(0, floorY + 0.5, 0)

        Vector3dAnimation on position {
            loops: Animation.Infinite
            from: Qt.vector3d(0, floorY + 0.5, -9600)
            to: Qt.vector3d(0, floorY + 0.5, 0)
            duration: 13333 // 9600 units / 13.333 s = 7.2 m/s ~ 26 km/h — relaxed
            easing.type: Easing.Linear
        }

        Model { source: "#Cube"; receivesShadows: false; castsShadows: false; materials: cityMaterial; instancing: cityList }
    }

    PrincipledMaterial {
        id: cityMaterial
        baseColor: "#ffffff"
        roughness: 0.1
        metalness: 0.3
        cullMode: Material.NoCulling
    }

    Component {
        id: cityEntry
        InstanceListEntry {}
    }

    // build the city rows (both road sides, rows kFrom..kTo).
    // All row parameters are deterministic functions of k % 12 so the city
    // tiles seamlessly with the 4800-unit loop period.
    function buildCityBand(list, kFrom, kTo) {
        // theme palette: asphalt -> road-gray family + white accents,
        // neon -> dark indigo family + neon accents
        let base = root.asphalt ? ["#9799a7", "#8d8f9d", "#a1a3b1"]
                                : ["#1f1f31", "#262642", "#181826"]
        let accent = root.asphalt ? ["#ffffff", "#f2f4f7"]
                                  : ["#00e5ff", "#ff2ea6"]
        // wild height mix: low sheds next to towers
        let mix = [0.5, 1.3,1.4, 0.8, 1.8, 2.0, 0.4, 1.5, 2.1, 1.0, 1.5, 1.6]
        // big width levels (8..20 m)
        let wl = [1200, 2500, 2000, 1900, 1800, 1200, 2600, 1600, 1400, 3000, 2100, 1900]
        // facade-line irregularity: inner edge jitters 11..15.5 m from center
        let jx = [0, 450, 200, 60, 300, 150, 420, 250, 90, 360, 180, 40]
        let arr = []
        for (let side = 0; side < 2; side++) {
            let dir = side === 0 ? -1 : 1
            for (let k = kFrom; k <= kTo; k++) {
                let p = k % 12
                // rows start 10000 units (100 m) BEHIND the ego car (z=0);
                // row 20 lands exactly on the road's far end (z=-6000)
                let z = 10000 - k * 800 + (side === 1 ? 45 : 0)
                // heights grow with distance from the car, the mix breaks monotony
                let env = 600 + 1300 * Math.min(1, Math.abs(z) / 3000)
                let h = Math.min(6000, Math.max(300, env * mix[p]))
                // 3 depth levels (300/530/760, min 3 m, < spacing 800 -> no overlap)
                let d = 300 + 460 * (p % 3) / 2
                let w = wl[p]
                // Inner edge sits cityInset + jitter from the centre line.
                // It used to be 1300, which put 40 m towers barely 13 m from
                // a chase camera sitting 8 m up: the frustum sliced straight
                // through them and they read as flat neon wedges cutting
                // across the top corners of the HUD rather than as a skyline.
                // Backing them off lets a whole facade fit in frame, which is
                // what makes them parse as buildings.
                // outer edge stays <= 3550 < strip edge 3600
                // accent rows 5 and 11, base family elsewhere
                let col = p === 5 ? accent[0] : p === 11 ? accent[1] : base[p % 3]
                // building cube; #Cube is 100x100x100 units -> /100 scales
                arr.push(cityEntry.createObject(list, {
                    position: Qt.vector3d(dir * (root.cityInset + jx[p] + w / 2), h / 2, z),
                    scale: Qt.vector3d(w / 100, h / 100, d / 100),
                    color: col
                }))
            }
        }
        return arr
    }

    // rebuild all city instances (called on theme change / startup)
    function rebuildCity() {
        cityList.instances = []
        while (cityEntries.length > 0)
            cityEntries.pop().destroy()
        cityEntries = root.buildCityBand(cityList, 0, 20)
        cityList.instances = cityEntries
    }

    InstanceList {
        id: cityList
        Component.onCompleted: root.rebuildCity()
    }

    // ---- ASPHALT STYLE OVERRIDES -----------------------------------------
    states: [
        State {
            name: "asphalt"
            when: root.asphalt

            PropertyChanges { target: groundMaterial; baseColor: "#8a8a90" }

            PropertyChanges { target: roadMaterial; baseColorMap: asphaltTex; normalMap: asphaltNormal; baseColor: "#ffffff"; metalness: 0.1; roughness: 0.9 }

            PropertyChanges { target: edgeMaterial; baseColor: "#c9c9c9" }
        }
    ]
}
