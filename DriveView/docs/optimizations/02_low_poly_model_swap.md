# Low-poly Model Swap (Tesla)

Follow-up to instancing (see `01_instanced-detections.md`): the heavy car mesh
used for label 2 (car) was replaced by a much lighter low-poly Tesla model.
This is an independent optimization on top of the instancing change.

## What changed

**Before:** `models_3d/car_mesh.mesh` (baked low-poly car) was the instanced
mesh for label 2 — 50,971 vertices, ~2.8 MB on disk, loaded once but uploaded
as one instanced draw.

**After:** the mesh is `models_3d/tesla_low_poly/meshes/object_0_mesh.mesh`
(1,176 vertices / 1,500 triangles, ~56 KB) — ~43x fewer vertices.

- `res.qrc`: `meshes/car_mesh.mesh` removed (frees ~2.8 MB of compiled
  resource), Tesla mesh and its texture maps registered instead.
- `qml/Scene3D.qml`: the car `Model` source now points at the Tesla mesh with
  a flat gray tinted texture (`textureData_gray.png`) so instances keep the
  neutral "detection" look.
- `src/detection_instancing.cpp` (label 2 block): the Tesla mesh is exported
  in centimeters and Z-up, so it needs explicit sizing/rotation in the
  instance table:
  - Mesh dimensions / 100 (the detection scale is normalized for a 100-unit
    cube): length 2.3507, height 0.6732, width 1.0351.
  - Uniform scale from the box height: `k = d.scale.y() / 0.6732f` so the car
    fills the detection box (scale `(k, k, k)`).
  - Rotation: `d.rotation * QQuaternion::fromEulerAngles(-90, 0, 0)` to level
    the Z-up mesh, plus an extra -90° yaw when the box is longest along its
    Z axis so the car points along the box.

## How it was measured

Same method as `01_instanced-detections.md` (`View3D.renderStats` with
`extendedDataCollectionEnabled`, 1 Hz debug timer in `qml/Scene3D.qml`,
same rosbag replay, window size 1500x720 and camera view).

## Results (typical values)

| Metric | Before model swap | After model swap |
|---|---|---|
| Car mesh | 50,971 verts / 2.8 MB | 1,176 verts / 56 KB |
| Vertices per frame (all instances) | ~1.0M | 132,408 |
| Draw calls | 96 - 97 | 94 |
| Render time | ~1.4 ms | ~1.1 - 1.5 ms |
| Frame time / FPS | ~66 ms / ~15 | ~66 ms / ~10-15 |

## Interpretation

- **Vertex submission dropped ~7.6x** (1.0M -> 132k per frame) with one draw
  call removed — GPU vertex/raster work is no longer the bottleneck.
- **Frame time still paced by the ROS data rate** (~10 Hz bag cadence), same
  as with instancing alone; the win is headroom for future scene content.
- The car instances keep the flat gray detection color via the tinted texture
  map (material `baseColor` stays white so the texture is not double-tinted).
