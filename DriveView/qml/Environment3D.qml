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

    // Vehicle speed in m/s, straight off the bus — not a scroll rate. It goes
    // through DriveSpeed below, which decides how fast the city moves; the
    // world stands still at a standstill, same as the wheels.
    property real speed: 0

    // created city entries (for teardown on theme/palette change)
    property var cityEntries: []

    // Only the palette depends on the theme, so repaint rather than rebuild.
    onAsphaltChanged: recolourCity()

    // ground level — detection box bottoms sit at ~ -1.36 m median in the
    // velo frame (echoed /object_detections_3d), i.e. y ≈ -136 Qt units.
    // Keep the floor a few units below that so nothing clips.
    readonly property real floorY: -142

    // Half the road width, in Qt units (100 = 1 m). The lane markings, the
    // asphalt tiling and the gap to the city all key off this, so widening the
    // road means changing this one number and nothing else — the edge lines
    // used to be a separate literal that silently had to match.
    readonly property real roadHalfWidth: 874.8   // 17.5 m across

    // Ground
    Model {
        id: ground
        source: "#Rectangle"
        visible: root.showGround
        // 4 units (4 cm) below the road rather than 0.5. The road hides it
        // everywhere they overlap, so the drop is invisible even at the road
        // edge, and it buys depth separation for free — see the road quad.
        y: floorY - 4
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

    // Road
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
    // the line. Thickness is deliberately not scaled with the road — a
    // painted line has a fixed real-world width regardless of road width.
    readonly property real edgeLineX: roadHalfWidth * 0.96

    // Height of the painted lines above the road. The stack (ground / road /
    // lines) is what z-fights when depth precision runs out at the far end,
    // so the gaps are deliberately wider than they need to be for looks: at
    // 2 cm none of this is visible from a camera 12 m away, but it keeps the
    // ordering unambiguous on a 16-bit depth buffer as well as a 24-bit one.
    readonly property real edgeLineY: floorY + 2

    // left edge solid line (magenta in neon style)
    Model {
        id: leftEdge
        source: "#Rectangle"
        x: -root.edgeLineX
        y: root.edgeLineY
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
        y: root.edgeLineY
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


    // Moving city (neon style): instanced building cubes on both sides of the
    // road, scrolling toward the camera in a seamless Outrun-style loop.
    //
    // 12-row deterministic cycle, spacing 800, tiles every 9600 units. Scroll
    // is integrated per frame at the car's own speed rather than run on a
    // fixed duration, so a velocity update never jumps the loop. Building
    // depth stays below the spacing (max 760 < 800) so cubes never overlap.
    //
    // The city is one opaque layer with no baked depth haze — the far end
    // fades via SceneEnvironment fog (Scene3D.qml) instead, which avoids
    // banding at the loop boundary.

    // 12 rows x 800 spacing — the tiling period the scroll has to wrap on.
    readonly property real cityPeriod: 9600

    // Scroll rate in units/s (100 units = 1 m). DriveSpeed owns the mapping
    // (standstill threshold, corrupt-frame clamp) so the city and the ego
    // wheels can't disagree about ground speed.
    //
    // Not the car's literal ground speed — see DriveSpeed.qml for why the
    // scenery is scaled instead.
    readonly property real scrollRate: DriveSpeed.sceneMps(root.speed) * 100

    // Resting phase of the scroll: the 16000-long band wraps every 9600, so
    // this picks which window is visible before the car moves. -2400 keeps
    // city on both sides of the camera at rest, instead of leaving a bare gap
    // behind it the way the other extreme (-cityPeriod) would.
    readonly property real cityRestZ: -2400

    Node {
        id: cityGroup
        visible: root.showCity

        // Walks up to 0, then wraps back by a full period.
        property real scrollZ: root.cityRestZ
        position: Qt.vector3d(0, floorY + 0.5, scrollZ)

        FrameAnimation {
            running: root.showCity && root.scrollRate > 0
            onTriggered: {
                // Cap the step so a stall (hidden window, hitch) resumes smoothly
                // instead of teleporting the city by the whole missed interval.
                let z = cityGroup.scrollZ + root.scrollRate * Math.min(frameTime, 0.1)
                cityGroup.scrollZ = z >= 0 ? z - root.cityPeriod : z
            }
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

    // Row range for the band. Named because recolourCity() has to walk the
    // entries in exactly the order buildCityBand created them.
    readonly property int cityRowFrom: 0
    readonly property int cityRowTo:   20

    // The only thing about a building that depends on the theme — position,
    // scale and row order don't, which is what makes recolouring in place a
    // valid substitute for rebuilding.
    function cityColor(p) {
        // asphalt -> road-gray family + white accents,
        // neon    -> dark indigo family + neon accents
        let base = root.asphalt ? ["#9799a7", "#8d8f9d", "#a1a3b1"]
                                : ["#1f1f31", "#262642", "#181826"]
        let accent = root.asphalt ? ["#ffffff", "#f2f4f7"]
                                  : ["#00e5ff", "#ff2ea6"]
        // accent rows 5 and 11, base family elsewhere
        return p === 5 ? accent[0] : p === 11 ? accent[1] : base[p % 3]
    }

    // build the city rows (both road sides, rows kFrom..kTo).
    // All row parameters are deterministic functions of k % 12 so the city
    // tiles seamlessly with the 4800-unit loop period.
    function buildCityBand(list, kFrom, kTo) {
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
                // Inner edge sits cityInset + jitter from the centre line. It
                // used to be 1300 — close enough that the chase camera's
                // frustum sliced through 40 m towers instead of framing them
                // as a skyline. outer edge stays <= 3550 < strip edge 3600
                // building cube; #Cube is 100x100x100 units -> /100 scales
                arr.push(cityEntry.createObject(list, {
                    position: Qt.vector3d(dir * (root.cityInset + jx[p] + w / 2), h / 2, z),
                    scale: Qt.vector3d(w / 100, h / 100, d / 100),
                    color: root.cityColor(p)
                }))
            }
        }
        return arr
    }

    // Full rebuild. Startup only — see recolourCity() for the theme path.
    function rebuildCity() {
        cityList.instances = []
        while (cityEntries.length > 0)
            cityEntries.pop().destroy()
        cityEntries = root.buildCityBand(cityList, root.cityRowFrom, root.cityRowTo)
        cityList.instances = cityEntries
    }

    // Theme change repaints existing buildings instead of calling
    // rebuildCity() — tearing down and recreating all 42 instances stalled
    // the theme flip on the Jetson, for geometry that never depended on the
    // theme anyway.
    //
    // Traversal order below must mirror buildCityBand's (side outer, k
    // inner), so entry i matches that side/row.
    function recolourCity() {
        let i = 0
        for (let side = 0; side < 2; side++) {
            for (let k = root.cityRowFrom; k <= root.cityRowTo; k++, i++) {
                if (i < cityEntries.length)
                    cityEntries[i].color = root.cityColor(k % 12)
            }
        }
    }

    InstanceList {
        id: cityList
        Component.onCompleted: root.rebuildCity()
    }

    // Asphalt style overrides
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
