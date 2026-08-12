# Instanced Rendering for 3D Detections

Optimization applied to the 3D view in `qml/Scene3D.qml` for rendering many
detected objects (cars, pedestrians, cyclists) coming from ROS.

## What changed

**Before:** a `Repeater3D` created one full QML scene-graph branch
(`Node` + `Model` + `PrincipledMaterial`) **per detection**, every time a new
detection message arrived. N detections = N draw calls and N scene-graph
objects created/destroyed on every update.

**After:** detection meshes are rendered with **instanced rendering**
(`QQuick3DInstancing`). One `Model` per mesh class (plane / cube / car mesh),
each referencing an instance table that contains the position, scale, rotation
and color of every detection.

- New C++ class `DetectionInstancing : QQuick3DInstancing`
  (`inc/detection_instancing.h`, `src/detection_instancing.cpp`) builds the
  instance table directly from `DetectionModel` in `getInstanceBuffer()`.
- Three tables, filtered by label: `planeInstancing` (0 = pedestrian),
  `cubeInstancing` (1 = cyclist), `carInstancing` (2 = car).
- The table is rebuilt only when the detection model resets
  (`modelReset`, delivered on the GUI thread via queued connection) and
  uploaded once via `markDirty()`.
- Per-label visual adjustments (scale-up for pedestrians, axis-swapped scale
  and -90° tilt for cars) moved from the QML delegate into the C++ table.
- `useInstanceColor` property is available to switch on per-class colors later
  (instance colors multiply the material's `baseColor`; keep the material
  white when enabled).

## How it was measured

Using the built-in `View3D.renderStats` (Qt 6.5+, see
[RenderStats](https://doc.qt.io/qt-6/qml-qtquick3d-renderstats.html)):

- A 1 Hz debug timer in `qml/Scene3D.qml` logs `fps, frame, max, render, sync,
  draws, verts, passes` to stdout (marked `// DEBUG` for removal).
- `extendedDataCollectionEnabled` is enabled on `view.renderStats` so that
  `drawCallCount` / `drawVertexCount` are collected.
- Both runs used the same rosbag replay (KITTI topics), same window size
  (1500x720) and same camera view.

## Results (typical values)

| Metric | Before (Repeater3D) | After (instancing) |
|---|---|---|
| Draw calls | 94 - 124 (scales with detection count) | 96 - 97 (flat) |
| Vertices per frame | 0.99M - 8.0M (scales with detection count) | ~1.0M (flat) |
| Sync time | 0.09 - 0.48 ms | 0.01 ms |
| Render time | ~1.5 ms | ~1.4 ms |
| Frame time / FPS | ~67 ms / ~15 | ~66 ms / ~15 |

## Interpretation

- **Draw calls and vertices no longer scale with the number of detections** —
  the biggest saving. At peak detection density the submitted vertex count
  dropped 8x (8.0M -> 1.0M), i.e. much less GPU vertex/raster work per frame.
- **Sync time dropped ~15-40x** (CPU): no more per-frame creation and
  destruction of QML delegates in the Repeater3D.
- **Frame time / FPS unchanged** because the scene renders **on demand**: Qt
  only redraws when something changes, so frames are paced by the ROS data
  rate (~10 Hz). The ~70 ms frames / ~13 fps is the bag's cadence, not a
  rendering cost. Verified by testing on both the Intel iGPU and the NVIDIA
  RTX 3050 (PRIME render offload) with identical results.



## Optional: run on the NVIDIA GPU

The app uses the Intel iGPU by default (display is wired to it). To render on
the discrete GPU instead, launch with:

```sh
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia ./build/Desktop_Qt_6_8_3-Debug/DriveView
```
