# Running the IVI Drive View pipeline

Three processes make the Drive View populate: the KITTI bag, the detector node,
and the app itself. All three need the same two setup files sourced, so every
terminal starts with that.

The laptop is an NVIDIA PRIME offload setup (RTX 3050 Ti) and `prime-run` is not
installed, so `appIVI` needs the two `__NV_*` / `__GLX_*` variables to land on
the discrete GPU.

---

## Build

Once, and after any code change:

```bash
source /opt/ros/humble/setup.bash && source ~/Documents/ITI_9Months/GP/ros2_ws_gp/install/setup.bash && cd ~/Documents/ITI_9Months/GP/IVI-Detections3D && cmake --build build
```

If `build/` ever needs regenerating from scratch:

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
```

---

## After a `git pull` on IVI — sync the ROS workspace first

The IVI app and the detector share `object_detection_msgs`, and they are in
separate repos. An IVI commit that reads a new message field will not compile
until the workspace is rebuilt, and the error names the field rather than the
cause. `no member named 'track_id'` means exactly this, not a bug in IVI.

```bash
cd ~/Documents/ITI_9Months/GP/ros2_ws_gp/src/ros2-lidar-object-detection && git pull
```

```bash
cd ~/Documents/ITI_9Months/GP/ros2_ws_gp && source /opt/ros/humble/setup.bash && colcon build --symlink-install --packages-select object_detection_msgs lidar_object_detection
```

Then build IVI as above. `--symlink-install` is mandatory — a plain build drops
the compiled `voxel_op` / `iou3d_op` `.so` files and the node dies on import.

New detector features tend to bring Python dependencies that are missing from
`package.xml`, so `rosdep` never reports them and the node only fails at
runtime. Known ones so far: `numba`, and `filterpy` for the AB3DMOT tracker.

```bash
pip install --user filterpy
```

---

## Terminal 1 — KITTI bag

```bash
source /opt/ros/humble/setup.bash && source ~/Documents/ITI_9Months/GP/ros2_ws_gp/install/setup.bash && ros2 bag play ~/Documents/ITI_9Months/GP/2011_09_29_drive_0004_sync_bag --loop
```

35.2 s / 339 lidar frames at ~9.6 Hz, hence `--loop`.

Any KITTI bag converted the same way works — the topic names are what matter,
not the drive. `main.cpp` hard-codes `/kitti/velo`, `/kitti/oxts/gps/vel`,
`/kitti/oxts/imu` and `/kitti/oxts/gps/fix`, and the detector subscribes to
`kitti/velo`, so a bag carrying those needs no rebuild. Check a new one before
wondering why the scene stays empty:

```bash
ros2 bag info ~/Documents/ITI_9Months/GP/<bag_dir>
```

Previously used here: `2011_09_26_drive_0005_sync_bag` (15.8 s / 154 frames).

## Terminal 2 — detector

```bash
source /opt/ros/humble/setup.bash && source ~/Documents/ITI_9Months/GP/ros2_ws_gp/install/setup.bash && ros2 run lidar_object_detection lidar_object_detector_node
```

## Terminal 3 — IVI, on the NVIDIA GPU

```bash
source /opt/ros/humble/setup.bash && source ~/Documents/ITI_9Months/GP/ros2_ws_gp/install/setup.bash && cd ~/Documents/ITI_9Months/GP/IVI && __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia ./build/appIVI
```

---

## Stop everything

```bash
pkill -f 'ros2 bag play'; pkill -f lidar_object_detector_nod[e]; pkill -f build/appIV[I]
```

The bracket in `nod[e]` / `appIV[I]` stops `pkill` from matching the shell that
is running the `pkill` itself.

---

## Gotchas

- **Both env vars start with two underscores** — `__NV_PRIME_RENDER_OFFLOAD`,
  `__GLX_VENDOR_LIBRARY_NAME`. A single underscore silently does nothing and the
  app renders on the Intel iGPU with no error to tell you.
- **Source ROS in the IVI terminal too**, not just the two ROS ones. `appIVI`
  links `rclcpp` and the message packages directly, so without the workspace on
  `LD_LIBRARY_PATH` it fails at load time rather than merely showing an empty
  Drive View.
- **Start the detector before or with the bag.** It drops messages that arrive
  before its subscription is up, and with `--loop` you would otherwise wait out
  a full 35.2 s pass before any detections appear.
- To confirm the offload took effect, `nvidia-smi` should list `appIVI` under
  its process table while the app is running.

## Environment notes

Workspace layout and the setup steps that are easy to get wrong (the mandatory
`colcon build --symlink-install`, the manual CUDA ops build, the pinned
CUDA/torch pair, `transforms3d` from pip not apt) are recorded separately —
this file is only the run commands.
