# IVI Head Unit

> A production-shaped **In-Vehicle Infotainment** system built on **Qt 6 / QML**, a **C++ hardware layer**, and a **ROS 2** perception pipeline — rendering live 3D lidar detections, media, connectivity, climate-adjacent comfort features, and vehicle telemetry on a single 1024×600 frameless surface.

This document describes **what the head unit is and how it works**. It is a reference for the software as it stands, not an installation guide — there are no build, flash, or deployment steps here.

---

## Table of Contents

- [1. Overview](#1-overview)
  - [1.1 What this is](#11-what-this-is)
  - [1.2 Design principles](#12-design-principles)
  - [1.3 Feature matrix](#13-feature-matrix)
- [2. Architecture](#2-architecture)
  - [2.1 Layer model](#21-layer-model)
  - [2.2 Process and thread model](#22-process-and-thread-model)
  - [2.3 The context-property boundary](#23-the-context-property-boundary)
  - [2.4 Data flow](#24-data-flow)
- [3. Project Structure](#3-project-structure)
- [4. The Screens](#4-the-screens)
  - [4.1 Splash](#41-splash)
  - [4.2 Launcher](#42-launcher)
  - [4.3 Weather](#43-weather)
  - [4.4 Media hub](#44-media-hub)
  - [4.5 Drive View](#45-drive-view)
  - [4.6 Settings hub](#46-settings-hub)
- [5. Drive View in Depth](#5-drive-view-in-depth)
  - [5.1 The pipeline](#51-the-pipeline)
  - [5.2 Coordinate frames](#52-coordinate-frames)
  - [5.3 Box reconstruction](#53-box-reconstruction)
  - [5.4 Smoothing](#54-smoothing)
  - [5.5 Track lifecycle](#55-track-lifecycle)
  - [5.6 Duplicate and overlap gating](#56-duplicate-and-overlap-gating)
  - [5.7 Placement rules](#57-placement-rules)
  - [5.8 Instanced rendering](#58-instanced-rendering)
  - [5.9 The 3D world](#59-the-3d-world)
  - [5.10 Cameras](#510-cameras)
  - [5.11 HUD and debug controls](#511-hud-and-debug-controls)
  - [5.12 The launcher mini-scene](#512-the-launcher-mini-scene)
  - [5.13 Tuning reference](#513-tuning-reference)
- [6. C++ Backends](#6-c-backends)
  - [6.1 BluetoothManager](#61-bluetoothmanager)
  - [6.2 BluetoothHWManager](#62-bluetoothhwmanager)
  - [6.3 BluetoothAgent](#63-bluetoothagent)
  - [6.4 BlueZ](#64-bluez)
  - [6.5 WifiManager](#65-wifimanager)
  - [6.6 WifiCredSender](#66-wificredsender)
  - [6.7 USBManager](#67-usbmanager)
  - [6.8 MediaLibrary](#68-medialibrary)
  - [6.9 SystemVolumeController](#69-systemvolumecontroller)
  - [6.10 SpeechManager](#610-speechmanager)
  - [6.11 AmbientLightManager](#611-ambientlightmanager)
  - [6.12 Perception classes](#612-perception-classes)
- [7. QML Logic Modules](#7-qml-logic-modules)
  - [7.1 WeatherStore](#71-weatherstore)
  - [7.2 WeatherAPI](#72-weatherapi)
  - [7.3 RadioAPI](#73-radioapi)
- [8. Reusable Components](#8-reusable-components)
- [9. Vehicle Integration](#9-vehicle-integration)
  - [9.1 ROS 2 topics](#91-ros-2-topics)
  - [9.2 Ambient lighting over CAN](#92-ambient-lighting-over-can)
  - [9.3 Wi-Fi credential handoff](#93-wi-fi-credential-handoff)
- [10. Design System](#10-design-system)
- [11. State, Navigation and Persistence](#11-state-navigation-and-persistence)
- [12. Configuration Surface](#12-configuration-surface)
- [13. Known Limitations](#13-known-limitations)
- [14. Glossary](#14-glossary)

---

## 1. Overview

### 1.1 What this is

The IVI head unit is a single Qt application that occupies the whole display of an
automotive centre stack. It runs frameless at 1024×600 with no window manager,
boots into a branded splash, and lands on a launcher that routes to five
functional areas: **Weather**, **Media**, **Drive View**, **Settings**, and the
**ambient cabin lighting** quick controls.

Three things separate it from a conventional Qt demo application:

**It talks to real vehicle hardware.** Bluetooth pairing goes through BlueZ over
D-Bus with a proper `org.bluez.Agent1` implementation; Wi-Fi goes through
NetworkManager; USB mass storage through UDisks2; system volume through
PulseAudio; the cabin LED strip through raw SocketCAN frames; and Wi-Fi
credentials are handed to the vehicle host over an authenticated CAN transport.

**It renders live perception output.** A ROS 2 node subscribes to a lidar
detection topic and the vehicle's GNSS/IMU stream. Detected vehicles,
pedestrians and cyclists are reconstructed from their 3D bounding-box corners,
smoothed, filtered, and drawn as instanced meshes in a Qt Quick 3D scene at
60 Hz — while the detector itself publishes at roughly 10 Hz.

**It is written to survive a vehicle, not a demo.** Every network and hardware
interaction is asynchronous, because a stalled daemon must never freeze the HMI.
Every hardware link that can be absent has a simulation path. State that matters
is persisted. Failure modes are handled where they occur rather than surfaced as
a hang.

### 1.2 Design principles

| Principle | How it shows up |
|---|---|
| **Never block the UI thread** | Every D-Bus call is async with a callback scoped to a context object. ROS spins on its own thread. Media scanning is offloaded. A wedged `bluetoothd` costs nothing, where a synchronous call would freeze the HMI for the 25 s D-Bus timeout. |
| **Degrade, don't disappear** | No CAN bus? The ambient page still works and prints frames. No network? The launcher shows the last weather reading from disk. No detector? Drive View says `OFFLINE` instead of printing garbage. |
| **The vehicle is the source of truth** | Speed, heading, position and detections all come from the bus. Nothing on screen is invented, and where the app *does* extrapolate (Drive View coasting) it is bounded, gated, and documented as such. |
| **One knob per concept** | Road width is a single derived value that the lane markings, texture tiling and city inset all key off. Weather is one shared cache, not one per screen. Ambient state is one object driving two screens. |
| **Embedded-first sizing** | Fixed 1024×600 target, frameless, no window chrome, touch-sized hit targets, and a virtual keyboard because there is no physical one. |
| **Explain the non-obvious in place** | The source carries the reasoning for decisions that look wrong without context — why a fixed `-90°` yaw exists, why `InstanceList` rejects a JS array, why credentials go on stdin. |

### 1.3 Feature matrix

| Area | Capability | Backing |
|---|---|---|
| **Launcher** | App tiles, live weather card, clock (UTC+3), online indicator, voice activation, car info, ambient quick controls, live 3D preview tile | QML + several backends |
| **Weather** | Current conditions, 24 h hourly strip, 7-day forecast, city search, UV / wind / pressure / humidity / cloud cover, day-night awareness | Open-Meteo, `WeatherStore` |
| **Audio** | USB and local library playback, playlist, seek, shuffle/repeat, Bluetooth A2DP source, album art | `MediaLibrary`, `USBManager`, `BluetoothManager` |
| **Video** | Local and USB video playback, full-screen, transport controls, USB device panel | `MediaLibrary`, `USBManager` |
| **Radio** | Station search by name, country and tag; streaming playback; persistent search state across navigation | radio-browser.info via `RadioAPI` |
| **Drive View** | Live 3D lidar detections, ego vehicle, animated road and city, chase and top-down cameras, orbit control, speed readout, theme and HDRI switching, OSM map component | ROS 2 + Qt Quick 3D |
| **Wi-Fi** | Enable/disable, scan, signal strength, secured-network indication, connect with password, disconnect, forget, credential handoff to the vehicle host | NetworkManager D-Bus, `WifiCredSender` |
| **Bluetooth** | Adapter power, discoverable, scan, pair with numeric confirmation, connect, disconnect, remove, A2DP/AVRCP transport | BlueZ D-Bus, `BluetoothAgent` |
| **Ambient light** | On/off, 5 effect modes, 8-colour palette, free colour picker, brightness, per-LED zone masking, heartbeat re-assertion | SocketCAN → ESP32 |
| **System** | Global brightness overlay, system volume and mute, offline speech recognition | PulseAudio, Vosk |

---

## 2. Architecture

### 2.1 Layer model

```
┌───────────────────────────────────────────────────────────────────────────┐
│                             QML / UI LAYER                                │
│                                                                           │
│   Main.qml ── StackView ──┬── pages/WeatherPage.qml                       │
│                           ├── pages/MediaPlayerPage.qml ── MediaPages/*   │
│                           ├── pages/SettingPage.qml ────── SettingPages/* │
│                           └── DriveView/DriveViewPage.qml ── qml/Scene3D  │
│                                                                           │
│   Components/  WindowBar · MediaCard · CarInfoPopup · AmbientCard ·        │
│                VirtualKeyboard                                            │
│                                                                           │
│   Pure declarative. Binds to C++ properties; never calls blocking code.    │
└─────────────────────────────────┬─────────────────────────────────────────┘
                                  │  Q_PROPERTY bindings · signals · slots
                                  ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                          QML LOGIC LAYER                                  │
│                                                                           │
│   API/WeatherStore.qml   singleton, stale-while-revalidate weather cache   │
│   API/WeatherAPI.qml     Open-Meteo geocode + forecast transport           │
│   API/RadioAPI.qml       radio-browser.info search + playback control      │
│                                                                           │
│   XMLHttpRequest only. No hardware access. Emits structured signals.       │
└─────────────────────────────────┬─────────────────────────────────────────┘
                                  │  QQmlContext::setContextProperty
                                  ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                           C++ BACKEND LAYER                               │
│                                                                           │
│   Connectivity   BluetoothManager · BluetoothHWManager · BluetoothAgent ·  │
│                  BlueZ · WifiManager · WifiCredSender                     │
│   Media          USBManager · MediaLibrary · SystemVolumeController        │
│   Comfort        AmbientLightManager                                      │
│   Input          SpeechManager                                            │
│   Perception     RosNode · DetectionModel · DetectionSmoother ·            │
│                  DetectionInstancing · CarInfo · BoxTransform             │
│                                                                           │
│   Every one is a QObject exposed as a context property.                   │
└─────────────────────────────────┬─────────────────────────────────────────┘
                                  │  Linux system interfaces
                                  ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                          HARDWARE / OS LAYER                              │
│                                                                           │
│   D-Bus        BlueZ 5 · NetworkManager · UDisks2                         │
│   PulseAudio   system sink volume · Bluetooth audio · microphone capture   │
│   SocketCAN    ambient lighting (0x500) · Wi-Fi credential transport       │
│   ROS 2        rclcpp subscriptions on the perception and telemetry topics │
│   Vosk         offline speech recognition                                 │
│   Qt Multimedia / GStreamer   audio and video decode                      │
└───────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Process and thread model

The application is a single process with several threads of execution:

| Thread | Owner | Responsibility |
|---|---|---|
| **GUI thread** | Qt | All QML, all rendering, all `QObject` property updates that QML binds to. Everything that touches the scene graph. |
| **ROS spin thread** | `RosSpinThread` | A `StaticSingleThreadedExecutor` spinning the `qt_pcl_visualizer` node. Detection, velocity, IMU and GNSS callbacks all land here. |
| **Qt Concurrent pool** | `USBManager` | Filesystem scans of mounted media, which can take seconds on a large stick. |
| **Audio callback** | `QAudioSource` | Microphone frames pushed into the Vosk recognizer. |

The critical boundary is **ROS spin thread → GUI thread**. `DetectionSmoother::update()`
is called from the ROS thread and only mutates target state under a mutex; a 60 Hz
`QTimer` owned by the GUI thread advances the interpolation and pushes results into
`DetectionModel`. The mutex is explicitly released before `setDetections()` is called,
so the model — which QML binds to — is only ever touched from the GUI thread.

### 2.3 The context-property boundary

`main.cpp` is the single place where C++ becomes visible to QML. Every backend is
constructed there and registered by name:

| Context property | Type | Purpose |
|---|---|---|
| `btManager` | `BluetoothManager` | A2DP/AVRCP media transport |
| `usbManager` | `UsbManager` | USB mass storage discovery and mounting |
| `musicLibrary` | `MediaLibrary` | On-disk audio listing |
| `videoLibrary` | `MediaLibrary` | On-disk video listing |
| `WifiManager` | `WifiManager` | Wi-Fi radio and connection control |
| `BluetoothManager` | `BluetoothHWManager` | Adapter, discovery and pairing |
| `systemVolume` | `SystemVolumeController` | PulseAudio sink volume and mute |
| `AmbientLight` | `AmbientLightManager` | Cabin LED strip over CAN |
| `speechManager` | `SpeechManager` | Offline speech recognition |
| `rosNodeInstance` | `RosNode` | Perception node handle |
| `detectionModel` | `DetectionModel` | Smoothed detections as a list model |
| `carInfo` | `CarInfo` | Live vehicle telemetry |
| `planeInstancing` | `DetectionInstancing` | Pedestrian instance table (label 0) |
| `cubeInstancing` | `DetectionInstancing` | Cyclist instance table (label 1) |
| `carInstancing` | `DetectionInstancing` | Vehicle instance table (label 2) |

> **Note on naming.** `BluetoothManager` the *context property* is a
> `BluetoothHWManager` (settings/pairing), while `btManager` is the
> `BluetoothManager` C++ class (media transport). The names are crossed; the
> settings pages use `BluetoothManager`, the media pages use `btManager`.

`main.cpp` also wires one cross-backend rule directly: when A2DP playback starts,
`BluetoothHWManager::setMediaActive(true)` is asserted, because Bluetooth inquiry
starves the ACL link and audibly breaks up music. The settings page therefore
cannot scan while the media side is playing.

`WeatherStore` is the exception to the context-property pattern — it is a QML
singleton, declared via `QT_QML_SINGLETON_TYPE` in `CMakeLists.txt`. The
`pragma Singleton` in the file alone is not sufficient: without the source
property, `qt_add_qml_module` omits the `singleton` line from `qmldir` and every
caller silently instantiates its own private copy, which defeats the entire
purpose of a shared cache.

### 2.4 Data flow

**Perception, from bus to pixel:**

```
  /object_detections_3d  (Object3dArray, ~10 Hz, ROS thread)
        │
        ▼
  RosNode::objectDetectionCallback
        │   8 box corners → computeBoxTransform → position / scale / rotation
        │   label → class colour
        ▼
  DetectionSmoother::update              [mutex, ROS thread]
        │   associate by track_id · low-pass velocity · yaw flip guard
        │   overlap suppression · placement rules · lifecycle transitions
        ▼
  DetectionSmoother::tick                [60 Hz QTimer, GUI thread]
        │   dt-aware exponential follow toward target
        │   velocity lead · coasting integration · opacity ramp
        ▼
  DetectionModel::setDetections          [GUI thread]
        │
        ├──▶ QML list model (detectCount, delegates)
        └──▶ DetectionInstancing ×3      one per class, label-filtered
                 │   builds a packed instance table
                 ▼
             Model { instancing: … }     Qt Quick 3D draws N copies in one pass
```

**Telemetry:**

```
  /kitti/oxts/gps/vel  ──▶ speed  ──▶ CarInfo.currVel ──▶ HUD readout, wheel spin
  /kitti/oxts/imu      ──▶ orientation quaternion ──▶ CarInfo.currImu{X,Y,Z,W}
  /kitti/oxts/gps/fix  ──▶ lat / lon / alt ──▶ CarInfo, map centring
```

---

## 3. Project Structure

```
IVI/
├── main.cpp                          Entry point; constructs and registers every backend
├── Main.qml                          Root ApplicationWindow: splash, StackView, global state
├── CMakeLists.txt                    Qt 6.8+, PulseAudio, Vosk, rclcpp, message packages
├── resources.qrc                     Icons, images, fonts, splash clip
│
├── API/
│   ├── WeatherStore.qml              Singleton weather cache (stale-while-revalidate)
│   ├── WeatherAPI.qml                Open-Meteo geocoding + forecast transport
│   └── RadioAPI.qml                  radio-browser.info search and playback
│
├── Backend/
│   ├── BluetoothManager.{hpp,cpp}    A2DP/AVRCP player: metadata, transport, position
│   ├── BluetoothHWManager.{hpp,cpp}  Adapter power, discovery, pair/connect/remove
│   ├── BluetoothAgent.{hpp,cpp}      org.bluez.Agent1, DisplayYesNo, delayed replies
│   ├── BlueZ.{hpp,cpp}               Shared async D-Bus plumbing and type marshalling
│   ├── WifiManager.{hpp,cpp}         NetworkManager: scan, connect, disconnect, forget
│   ├── WifiCredSender.{hpp,cpp}      Credential handoff to the vehicle host over CAN
│   ├── USBManager.{hpp,cpp}          UDisks2 discovery, mount, async media scan
│   ├── MediaLibrary.{hpp,cpp}        Directory-backed list model, one per media type
│   ├── SystemVolumeController.{hpp,cpp}  PulseAudio sink volume and mute
│   ├── SpeechManager.{hpp,cpp}       Vosk offline recognition over QAudioSource
│   ├── AmbientLightManager.{hpp,cpp} Cabin LED strip over SocketCAN
│   ├── vosk_api.h · libvosk.so       Vendored speech recognition library
│
├── Components/
│   ├── WindowBar.qml                 Shared top bar: title, back, brightness, volume, status
│   ├── MediaCard.qml                 Now-playing card with artwork and transport
│   ├── CarInfoPopup.qml              Modal vehicle information overlay
│   ├── AmbientCard.qml               Launcher ambient-light quick controls
│   └── VirtualKeyboard.qml           On-screen keyboard with shift, password mode, reveal
│
├── pages/
│   ├── WeatherPage.qml               Full weather dashboard and city search
│   ├── MediaPlayerPage.qml           Media hub routing to Audio / Video / Radio
│   └── SettingPage.qml               Settings hub routing to Wi-Fi / Bluetooth / Ambient
│
├── MediaPages/
│   ├── AudioPage.qml                 Audio player, playlist, Bluetooth and USB sources
│   ├── VideoPage.qml                 Video player, full-screen, USB device panel
│   └── RadioPage.qml                 Internet radio browser and player
│
├── SettingPages/
│   ├── WiFiPage.qml                  Network list, connect dialog, credential handoff
│   ├── BluetoothPage.qml             Device list, pairing confirmation, connection state
│   └── AmbientLightPage.qml          Full ambient controls: modes, palette, zones, picker
│
└── DriveView/
    ├── DriveViewPage.qml             Page shell: Scene3D + WindowBar
    ├── res.qrc                       Meshes, textures, HDRI probes
    ├── inc/
    │   ├── ros_node.h                Subscriptions, callbacks, spin thread
    │   ├── detection_data.h          The per-detection POD passed between layers
    │   ├── detection_model.h         QAbstractListModel of smoothed detections
    │   ├── detection_smoother.h      Track state, lifecycle flags, interpolation
    │   ├── detection_instancing.h    QQuick3DInstancing subclass, label-filtered
    │   ├── box_transform.h           8 corners → position / scale / quaternion
    │   └── car_info.h                Vehicle telemetry properties
    ├── src/                          Implementations of the above
    ├── qml/
    │   ├── Scene3D.qml               Full-screen scene, HUD, cameras, settings drawer
    │   ├── MiniScene3D.qml           Launcher tile preview, same instancing tables
    │   ├── Environment3D.qml         Road, ground, lane markings, scrolling city
    │   └── MapOSM.qml                OpenStreetMap view via QtLocation
    └── models_3d/
        ├── audi_low_poly/            Ego vehicle, with driven wheel spin
        ├── tesla_low_poly/           Detected vehicle mesh + silver texture
        └── lowpoly_ps1_character…/   Detected pedestrian mesh, walk pose
```

---

## 4. The Screens

### 4.1 Splash

An `AnimatedImage` plays a branded clip (`assets/videos/vpace_splash.gif`, 90
frames, roughly 3 s) full-screen from embedded resources, cropped with
`PreserveAspectCrop` over an opaque backdrop so no aspect ratio can expose bare
window.

`AnimatedImage` loops forever and offers no "finished" signal, so the end of the
clip is detected by watching `currentFrame` reach `frameCount - 1`. Playback is
stopped **on** that frame rather than after it — letting it wrap visibly restarts
the logo underneath the fade. A 300 ms opacity animation then hands over to the
UI.

A 6 s backstop timer forces the same transition if the clip is missing or fails
to decode. A bad resource must never strand a head unit on a splash screen it
cannot leave.

### 4.2 Launcher

The home screen is a bento grid over an animated gradient background with
floating blurred colour blobs.

**Top glass bar** — carries the clock, the date, a "Drive Safe" greeting, an
online/offline indicator bound to `WifiManager.connectedSsid`, and the vehicle
logo. The whole bar is a hit target that opens the car info popup; it lifts on
hover, because a header that reacts to nothing gives no hint it can be pressed.

The clock is derived from the epoch rather than formatted from local time:

```js
var now  = new Date()
var here = new Date(now.getTime() + (now.getTimezoneOffset() + tzOffsetMinutes) * 60000)
```

`tzOffsetMinutes` is fixed at `3 * 60`. Formatting `new Date()` directly would
trust whatever zone the host is set to, and the target image comes up as UTC —
so the bar read three hours behind while the underlying epoch was correct. This
form produces the same wall clock on the vehicle and on a developer laptop in
any zone.

**App tiles** — Weather, Media, Drive View and Settings. Each has a coloured
accent bar, a tinted circular icon, a title and subtitle, a scale-and-glow hover
animation, and a slow looping vertical drift that keeps the idle screen alive.

**Live weather card** — current temperature, a WMO-code-derived emoji, a short
description, and the configured city. Reads synchronously from `WeatherStore`,
so it paints on its first frame from cache and updates in place when a refresh
lands.

**Drive View tile** — a live `MiniScene3D`, sharing the same instancing tables
as the full page. It shows real detections, not a mock-up, with no second
subscription and no duplicated state.

**Ambient card** — power, mode and the fixed palette. Brightness, zone masking
and the free colour picker are deliberately left on the settings page: the
launcher may be used while moving, and a hue wheel is not something to hand a
driver at speed.

**Voice activation** — a microphone button starts `SpeechManager`. While
listening the button turns red and a live partial transcript appears beneath it.
Recognised words route to navigation: weather and city names open the weather
page, media/music/video open the media hub, settings opens the settings hub.

**Global brightness overlay** — a black `Rectangle` parented to
`Overlay.overlay` at `z: 99999`, with `opacity = 1.0 - appBrightness`. Because it
is on the overlay layer it dims popups and dialogs too, which a plain sibling
rectangle would not.

### 4.3 Weather

A full dashboard backed by **Open-Meteo**, which needs no API key.

- **Current conditions** — temperature, apparent temperature, condition text and
  icon, wind speed and direction, surface and mean-sea-level pressure, relative
  humidity, cloud cover, and a day/night flag that the styling responds to.
- **Hourly strip** — the next 24 hours, horizontally scrollable.
- **Daily forecast** — 7 days with high/low and maximum UV index.
- **City search** — a text field with the on-screen `VirtualKeyboard`, resolving
  through Open-Meteo's geocoding endpoint. A successful search updates
  `mainWindow.preferredCity`, which persists and re-points the launcher card.
- **Not-found handling** — `WeatherStore` emits `notFound`, and the page shows an
  inline message rather than an empty dashboard.

All of it reads through `WeatherStore`, so entering the page from the launcher
costs nothing when the cache is fresh.

### 4.4 Media hub

`MediaPlayerPage` is a router with its own nested `StackView`. Playback state is
owned above it, in `Main.qml`, so audio survives navigation.

**Shared now-playing state** lives on the root window:

| Property | Meaning |
|---|---|
| `currentMediaTitle` / `currentMediaSubtitle` | What is playing |
| `currentMediaFavicon` | Station icon, radio only |
| `currentMediaType` | `0` none · `1` radio · `2` local audio · `3` video · `4` Bluetooth |
| `mediaPlaying` | Unified play state |

`mediaPlaying` is not simply `sharedMediaPlayer.playbackState`. Bluetooth audio
is driven by the phone, not by the local player, so for `currentMediaType === 4`
the state comes from AVRCP (`btManager.playerStatus`) instead. `Connections` on
`btManager` mirror the phone's stream into the shared state so it surfaces
everywhere local sources do — and clearing only happens if Bluetooth is what is
currently showing, so a locally started track is never stomped.

#### Audio player

Sources are the on-disk library (`musicLibrary`), mounted USB devices
(`usbManager`), and a connected phone over A2DP. The page offers a scrollable
playlist with the active row highlighted, a seek bar with elapsed and total time,
transport controls, and artwork.

#### Video player

Full-screen playback with an auto-hiding control overlay, a seek bar, and a
device panel listing mounted USB volumes so a stick can be browsed without
leaving the page.

#### Radio

Search by name, country or tag against **radio-browser.info**. Results list
station name, country, codec and bitrate with the station favicon. Selecting one
streams it through the shared player.

Search state — query text, whether a search has been attempted, loading flag, and
the current station — is held on `mainWindow`, not on the page. The page is
pushed from a `Component` and therefore destroyed on back navigation; keeping the
state above it means returning to radio restores the previous result list instead
of an empty search box.

### 4.5 Drive View

The 3D perception view. Covered in full in [section 5](#5-drive-view-in-depth).

### 4.6 Settings hub

`SettingPage` routes to three sub-pages through a nested `StackView` and can be
addressed directly from elsewhere: `Main.qml` exposes `openSettingsSection(name)`
so the status icons in `WindowBar` can jump straight to Wi-Fi or Bluetooth. If
settings is already on screen it switches section rather than pushing a second
copy.

#### Wi-Fi

Radio toggle, scan, and a network list showing SSID, signal strength and a lock
indicator for secured networks, with the connected network pinned and marked.
Connecting to a secured network opens a password dialog backed by the virtual
keyboard, with a reveal toggle. Disconnect and forget are available on the
active connection.

On a successful connection the credentials are additionally handed to the
vehicle host through `WifiCredSender` (see [9.3](#93-wi-fi-credential-handoff)).

#### Bluetooth

Adapter power and discoverability, scan with live device arrival, and a device
list split into paired and available. Pairing uses **numeric comparison**: BlueZ
calls into `BluetoothAgent`, the six-digit passkey is shown in a modal, and the
D-Bus reply is held open until the driver accepts or rejects.

Scanning is suppressed while A2DP is playing, wired in `main.cpp`.

#### Ambient light

The full control surface for the cabin strip: power, the five effect modes
(Static, Breathe, Chase, Scanner, Rainbow), an eight-colour preset palette, a
free HSV colour picker, a brightness slider, and per-LED zone masking across the
six LEDs.

The palette contains **no alternating red/blue**. That pattern imitates emergency
vehicles and is illegal on a road vehicle in most jurisdictions. Single static
colours are not.

---

## 5. Drive View in Depth

### 5.1 The pipeline

Drive View turns a sparse, noisy, ~10 Hz stream of 3D bounding boxes into a
stable 60 Hz scene. The problem is not drawing boxes — it is that raw detector
output, drawn directly, looks broken:

- Objects step visibly at the message rate rather than moving.
- Boxes jitter frame to frame as the detector's estimate wobbles.
- Symmetric boxes flip 180° at random because yaw is ambiguous.
- The tracker retires and re-acquires IDs, so one car becomes two.
- Objects vanish instantly at the edge of the sensor's field of view.
- The detector occasionally emits two boxes for one vehicle.
- People appear in the middle of the carriageway and inside buildings.

Everything in `DetectionSmoother` exists to address one of those.

### 5.2 Coordinate frames

Two frames are in play, and the conversion is the source of most of the sign
conventions in the code.

| | ROS (`velo_link`) | Qt Quick 3D |
|---|---|---|
| Handedness | Right | Left |
| Forward | `+X` | `−Z` |
| Left | `+Y` | `−X` |
| Up | `+Z` | `+Y` |
| Unit | metres | 1/100 m |

```cpp
static QVector3D rosToQt(const QVector3D& v)
{
    return QVector3D(-v.y(), v.z(), -v.x());
}
```

Two consequences worth internalising, because nearly every threshold in the
smoother depends on them:

1. **`+Z` is behind the ego.** Anything receding has positive Z velocity.
2. **Positions are in hundredths of a metre.** A value of `850.5` is 8.5 m.

That second point caused a real defect. The velocity sanity clamp was written as
`kMaxSpeedMs = 40.0f` and documented as 40 m/s, but it was compared against a
speed in Qt units per second — so it actually clamped to **0.4 m/s**. Every
moving object had its velocity crushed by roughly 97%, which made the velocity
lead worth about 3 cm instead of a metre and left `targetVel` useless for
anything downstream. It is now `kMaxSpeedUnits = 4000.0f`.

### 5.3 Box reconstruction

The message carries eight corner points, not a pose. `computeBoxTransform()`
recovers one:

```
        ^ z   x     6 ------ 5
        |   /      / |     / |
        |  /      2 -|---- 1 |
 y      | /       |  |     | |
 <------|o        | 7 -----| 4
                  |/   o   |/
                  3 ------ 0
```

- `0→4`, `0→3` and `0→1` give the three box axes.
- Their lengths give the three extents.
- The centre is the midpoint of the `0↔6` diagonal.
- A rotation matrix is assembled from the axes and re-orthogonalised via two
  cross products before conversion to a quaternion.

**A caveat that matters downstream:** the axis the code calls "length" is not
reliably the vehicle's long axis. Measured on drive 0004, every car alongside the
ego reports its `0→4` axis at approximately ±90° — i.e. across the vehicle, not
along it. The renderer compensates with a fixed `-90°` yaw whenever the width
slot exceeds the length slot, which is why `detection_instancing.cpp` contains
what looks like an arbitrary constant. It is not arbitrary; it is the correction
for a swapped axis.

The sign of that ±90 is chosen arbitrarily by the detector, and that is the root
of the "backwards car" behaviour handled in [5.7](#57-placement-rules).

### 5.4 Smoothing

Interpolation is **dt-aware exponential**, not fixed-step:

```cpp
const float alpha = 1.0f - qExp(-float(dtMs) / kTauPosMs);
track.currentPos += (projected - track.currentPos) * alpha;
```

A fixed per-tick factor produces different motion at different frame rates. The
exponential form is defined by a time constant, so identical motion results
whether ticks land at 16 ms or 30 ms. `kTauPosMs = 70` reproduces the previous
fixed `0.2` per 16 ms tick exactly.

**Velocity lead.** Pure exponential following always lags a moving target. The
target is therefore projected forward along its own smoothed velocity before the
follow runs:

```cpp
const QVector3D projected = track.targetPos + track.targetVel * (kHorizonMs / 1000.0f);
```

With `kHorizonMs == kTauPosMs`, the lead exactly cancels the lag at constant
velocity. When the object stops, `targetVel` decays and the correction term pulls
the box in without overshoot.

**Measurement velocity** is itself low-passed (`kTauVelMs = 150`) from successive
message positions, clamped to a plausible maximum, and reset outright after a gap
of 500 ms or more — a stale velocity is worse than no velocity.

**Yaw flip guard.** Detector yaw carries a ±π ambiguity on symmetric boxes. Left
alone, `slerp` spins the mesh through a full 180° every time the sign changes.
When the measured rotation differs from the current one by more than
`kFlipThresholdDeg` (120°), the guard tries the 180° alternative about the box's
**own up axis** and accepts it if it is nearer.

Two details make this correct rather than approximately correct:

- The flip must be about the box's own up axis. Rotating 180° about any
  horizontal world axis would turn the box upside down.
- The difference quaternion must be sign-normalised (`w >= 0`) first.
  `QQuaternion::getAxisAndAngle` reports angles in `(180°, 360°]` when the scalar
  part is negative rather than normalising to the shortest rotation, so without
  this the near-side flip is always rejected and the box spins anyway.

### 5.5 Track lifecycle

Each track moves through four observable states:

```
                 ┌──────────────────────────────────────────┐
                 │              re-acquired                  │
                 ▼                                           │
   ┌───────────┐    2 hits    ┌────────┐    lost      ┌──────────┐
   │ tentative │─────────────▶│  live  │─────────────▶│ coasting │
   └───────────┘              └────────┘              └──────────┘
        │  never seen again        │  suppressed           │  off screen
        │                          │  by a rule            │  or capped
        ▼                          ▼                       ▼
   ┌────────────────────────── fading ──────────────────────────┐
   │            opacity → 0 over ~40 ms, then reaped            │
   └────────────────────────────────────────────────────────────┘
```

**Tentative.** A new track is not drawn until it has been measured
`kMinHitsToShow` (2) times. A detection that appears for one message and is gone
by the next is a false positive, and drawing it is what makes a car flash into
existence beside the ego with nothing leading up to it. Tentative tracks are also
pinned at zero opacity — otherwise they spend their entire fade-in invisible and
then appear at two-thirds brightness the instant they confirm, which is the exact
pop the gate exists to remove.

**Coasting** is dead reckoning past the end of the sensor. The lidar's useful
field of view ends at the ego vehicle, so an oncoming car is dropped the instant
it draws level. That is correct detector output and it looks wrong: the car stops
dead alongside and evaporates, when what you were watching was something closing
at 15 m/s.

A dropped track therefore keeps travelling on its own last measured velocity at
full opacity until it is off screen, and only then fades:

```cpp
track.targetPos.setZ(track.targetPos.z() + track.targetVel.z() * dt);
```

Constant velocity, not decaying — traffic passing you does not slow down, and a
decay reads as braking. **Z only**: the lateral component of a dead-reckoned
velocity is mostly estimate noise, and integrating it for several seconds walked
cars sideways out of their lane and off the tarmac, which is motion the object
never had.

Coasting is gated so it can never invent motion:

| Gate | Value | Why |
|---|---|---|
| Must be receding | `v.z > 0` | A ghost drifting *toward* the camera is far more noticeable than one leaving. |
| Must be moving | `≥ 0.6 m/s` | A track that vanishes while pacing us is not driving away. |
| Must be established | `≥ 3 hits` | Below that the velocity is mostly the low-pass's initial zero. |
| Must be on the road | `\|x\| ≤ roadHalfWidth` | Extrapolating a car through the pavement looks worse than letting it go. |
| Hard time cap | 10 s | A bad velocity estimate can never leave a ghost parked in the scene. |

The 0.6 m/s floor is deliberately low. It was 2 m/s, which covered oncoming
traffic but excluded the case the feature is most wanted for: a car you overtake
pulls away at the *difference* between the two speeds. Measured on drive 0004,
track 55660 fell back at **0.93 m/s** over ten seconds — real, steady, and under
the old gate, so it vanished at the bumper like everything else.

**The fade happens off screen.** `kCoastEndZ = 1400` (14 m back) is past both
default cameras — the chase view's lower frustum edge crosses road level at
z ≈ 680, and the top view sees to z ≈ 1220. That is the entire point: the object
leaves the screen at full opacity, the way a real one does.

**Fading** is asymmetric on purpose. Fading *in* can be leisurely (90 ms), because
a car arriving at partial alpha is blending over the road behind it and looks
like a car appearing. Fading *out* cannot: the vehicle mesh is concave, so while
it is semi-transparent you see its own far side through it and it blends toward
the dark background — which reads as the car changing colour just before it
vanishes rather than dissolving. Nothing tints it; the instance RGB is white
throughout. A long ramp simply gives the eye time to read the dimming as a colour
shift, so the out-ramp is 40 ms and the track is reaped while still 12% visible.

### 5.6 Duplicate and overlap gating

Three separate mechanisms, because duplicates arise three different ways.

**Live versus live.** Two boxes for one object — the detector occasionally emits
a second, and the tracker occasionally carries both IDs forward — sit almost on
top of each other. Two real vehicles cannot share a footprint, so overlapping
same-label boxes are one object and the weaker one is dropped.

The gate scales with the boxes rather than being a flat distance:

```cpp
gap < kOverlapFraction * (groundRadius(a) + groundRadius(b))
```

where `groundRadius` is half the diagonal of the box footprint. This stays
correct across classes:

| Pair | Merges below |
|---|---|
| car / car | 2.42 m |
| pedestrian / pedestrian | 0.57 m |
| lorry / lorry | 5.15 m |

At 2.42 m for cars there is over a metre of margin against 3.5 m lane spacing, so
traffic in the next lane is never suppressed however close it passes. Ties break
on hit count, then confidence, so the established box survives and the newcomer
goes.

**Ghost versus live.** A coasting track is a *prediction* of something the sensor
can no longer see. The moment a real detection appears where that prediction is,
the prediction is redundant — and keeping both is what puts two or three copies
of one car on screen. The upstream tracker reassigns IDs frequently, which lands
one physical car in two entries: the old ID coasting, the new ID spawning on top.

The displaced ghost hands its **alpha and its hit count** to the replacement.
Both halves matter. Without the alpha the swap costs a visible dip, the ghost
leaving at full opacity while its replacement ramps from zero. Without the hit
count it is worse — the replacement counts as tentative and is withheld
altogether, so the car vanishes for a message and returns, which reads as cars
blinking on the way past.

**Ghost versus ghost.** Repeated ID churn leaves one coasting copy per retired
ID, and those never meet a live detection to be gated against. A final pairwise
pass merges them by the same rule.

### 5.7 Placement rules

Two rules suppress detections that are real output but not plausible content.

**The backwards car alongside the ego.** Because the detector's ±90 sign is
arbitrary and the renderer applies a fixed `-90°` correction, a box reported at
`+90` comes out facing forward and one reported at `-90` comes out facing
backwards — a car driving the same way as you, drawn against the traffic, right
alongside where it is most obvious.

Such a box is **not rotated to fit**. Turning it would invent an orientation the
sensor never reported, and the result would be indistinguishable from a real
oncoming car — a worse lie on a driving display than an absent box. It is simply
not drawn, and only under three simultaneous conditions:

```cpp
track.suppressed = alongside && facingBackwards && goingOurWay;
```

| Condition | Test |
|---|---|
| `alongside` | within 6 m either side and 6 m fore/aft |
| `facingBackwards` | box length axis has positive Z |
| `goingOurWay` | world Z velocity is negative |

All three are required. *Backwards* alone would take every oncoming car on the
road, since for those backwards is correct. *Alongside* alone would take the
adjacent-lane traffic that renders fine. Only the combination — a box drawn
backwards while the object is measurably travelling your way — is a
contradiction worth hiding.

The third condition needs **world** velocity, not ego-frame velocity: in the ego
frame an oncoming car and one you are overtaking both simply fall behind you.
Ego speed is therefore fed to the smoother purely to classify direction:

```cpp
const float worldVz = track.targetVel.z() - egoSpeed * 100.0f;
```

**Pedestrians on the pavement.** People are drawn only in the band between the
road edge and the buildings. The detector puts them in the carriageway and inside
the facades often enough to be distracting, and neither is somewhere a person can
be in this scene — one is under the traffic, the other is inside a wall.

```cpp
suppressed = lat < kRoadHalfWidth || lat > kCityInset;
```

This is checked for untracked detections too, which skip the tracking branches
entirely and would otherwise never be filtered.

**Both rules ride the opacity ramp** rather than cutting, so an object crossing a
boundary dissolves over ~40 ms instead of blinking, and returns the same way if
it leaves the zone. Once faded it is dropped from the output entirely, which
keeps the HUD's detection count honest about what is actually on screen.

> **Coupling to watch.** `kRoadHalfWidth` and `kCityInset` in
> `detection_smoother.cpp` are *mirrors* of `roadHalfWidth` and `cityInset` in
> `Environment3D.qml`. C++ cannot read the QML values, so widening the road means
> changing both. The pedestrian margin is currently thin — the nearest observed
> pedestrian sits about 0.24 m outside the road edge.

### 5.8 Instanced rendering

All detections of a class are drawn in **one pass**. `DetectionInstancing`
subclasses `QQuick3DInstancing` and builds a packed table of per-instance
transforms and colours:

```cpp
const InstanceTableEntry entry =
    calculateTableEntryFromQuaternion(d.position, scale, rotation, color);
```

Three instances exist, one per class, each with a `labelFilter`, all sharing the
same `DetectionModel`. They rebuild on `modelReset` and `dataChanged` via queued
connections.

Per-class geometry fixes are applied here:

| Label | Mesh | Adjustment |
|---|---|---|
| 0 pedestrian | walk-pose plane | ×100 upscale; pre-rotate pitch −90° to map Blender Z-up to Y-up |
| 1 cyclist | `#Cube` | box dimensions used directly |
| 2 vehicle | Tesla low-poly | uniform scale from box height; extra −90° yaw when the width slot holds the true length |

**Colour and alpha are handled separately.** Alpha always rides through, because
it carries the spawn/despawn fade. RGB is opt-in (`useInstanceColor`, default
false) because the class colours are raw primaries chosen as *data*, not as a
look — applying them would repaint the silver vehicle pure blue and the
pedestrian pure red.

### 5.9 The 3D world

`Environment3D.qml` builds the road and surroundings in two styles: **neon**
(default — near-black ground, dark road, glowing cyan edge lines) and **asphalt**
(PBR textured road, white markings), switched by one boolean via QML states.

**Road width is a single knob.** `roadHalfWidth` (currently `893.0`, so 17.86 m
across) drives the road quad, the edge-line positions (`× 0.96`) and the asphalt
texture tiling. That last one is easy to miss: UVs run 0..1 across the quad
regardless of its scale, so the tile count has to track the width or the grain
stretches with it:

```qml
scaleU: 26 * root.roadHalfWidth / 500
```

**Ground plane** at `floorY = -142`, chosen a few units below the observed median
detection box bottom (≈ −136) so nothing clips through.

**The scrolling city** is instanced cubes on both sides, animated toward the
camera in a seamless loop. The seamlessness is arithmetic rather than luck: a
deterministic 12-row cycle at 800-unit spacing tiles exactly every 9600 units,
and the animation translates by precisely one period (−9600 → 0), so there is no
seam. Building depth stays below the row spacing (max 760 < 800) so cubes never
intersect. Heights, widths, depths and facade jitter are all functions of
`k % 12`.

Depth haze is **not** baked into the city as per-row opacity — that produces
banding and a visible flash at the loop boundary. It comes from world-space
`SceneEnvironment` fog instead, which is smooth, seamless, and also hides the
loop-wrap beyond the road end.

**Lighting** is two directional lights (a warm key and a cool blue fill at
opposing yaws) plus optional HDRI image-based lighting from one of two probes.
Both `.hdr` files are loaded once into `Texture` objects at startup and a theme
switch only re-points the `lightProbe` reference — decoding a compressed HDR and
regenerating environment mipmaps on the GUI thread was a visible freeze.

### 5.10 Cameras

| View | Pivot | Rotation | Distance | FOV |
|---|---|---|---|---|
| Chase | origin | −50° pitch | 1200 | 70° |
| Top-down | origin | −90° pitch | 1600 | 70° |
| Mini-scene | `(0, 0, −185)` | −42° pitch | 1250 | 60° |

Switching views animates the rig's rotation and the camera's distance with
matched 700 ms `InOutCubic` curves, so the pitch does not snap while the camera
glides. The rotation is animated by explicit from/to rather than a `Behavior`,
because the `OrbitCameraController` writes `orbitOrigin` every frame while
dragging and a `Behavior` would fight it.

The mini-scene's pivot sits ahead of the car, which drops the vehicle below
centre and gives most of the frame to the road ahead. It originally sat a full
3 m forward, which pushed the rear bumper to within ~0.7 m of the bottom edge.
Backing it off to 185 units lifts the bumper from roughly 7% to 17% of tile
height. Only Z moves — the rotation and the camera's local offset are untouched,
so the rig slides along the road without changing angle.

### 5.11 HUD and debug controls

Overlaid on the scene: a status card (detection count, active view), a legend, a
live camera position and rotation readout, a large speed readout in km/h derived
from `carInfo.currVel × 3.6`, and buttons for view switching and camera reset.

A settings drawer exposes theme, ego vehicle colour via an HSV picker, light
brightness, HDRI selection and exposure, road style, and the Tesla texture
toggle.

The detection count guards against uninitialised data with
`Math.abs(detectCount) > 1000`, showing a dash instead of a nonsense number
before the first message arrives. `MiniScene3D` exposes the same guard as a
`hasSignal` flag so the tile can say `OFFLINE`.

> These controls are development instrumentation, not shipping UI.

### 5.12 The launcher mini-scene

`MiniScene3D` renders the same ego vehicle and the same instancing tables as the
full page — real detections, no second subscription, no duplicated state — with
no HUD, no orbit controller, and no drawer. Leaving the controller out is
deliberate: the tile below has to stay clickable, and a drag on the home screen
should scroll the launcher, not spin a camera.

It renders with a transparent background so the card's glass gradient shows
through, and is masked to the card's corner radius using a QML-drawn `Rectangle`
as a `MultiEffect` mask source. The mask is drawn rather than loaded as a bitmap
because a bitmap gets stretched to the item, so a round corner in the file comes
out as an ellipse on a non-square card. A `Rectangle`'s radius stays a radius.

It also runs cheaper settings than the full page — `Medium` antialiasing rather
than `High` — because it renders continuously behind the entire launcher.

### 5.13 Tuning reference

Every constant in `detection_smoother.cpp`, in one place:

| Constant | Value | Governs |
|---|---|---|
| `kTickIntervalMs` | 16 | Interpolation tick (≈60 Hz) |
| `kTauPosMs` | 70 | Position/scale/rotation follow time constant |
| `kTauVelMs` | 150 | Measurement-velocity low-pass |
| `kHorizonMs` | 70 | Velocity lead; equals `kTauPosMs` to cancel lag exactly |
| `kMaxSpeedUnits` | 4000 | Velocity clamp (40 m/s) |
| `kFlipThresholdDeg` | 120 | Above this a yaw change is treated as an ambiguity flip |
| `kTauAlphaInMs` | 90 | Spawn fade-in |
| `kTauAlphaOutMs` | 40 | Despawn fade-out |
| `kAlphaGone` | 0.12 | Opacity at which a fading track is reaped |
| `kCoastEndZ` | 1400 | Distance behind ego at which coasting ends (14 m) |
| `kCoastMinSpeed` | 60 | Minimum recession speed to coast (0.6 m/s) |
| `kMaxCoastMs` | 10000 | Hard cap on dead reckoning |
| `kGhostMergeDist` | 300 | Ghost-to-detection association radius (3 m) |
| `kMinHitsToCoast` | 3 | Measurements before a track may coast |
| `kMinHitsToShow` | 2 | Measurements before a track is drawn |
| `kMinHitsForTravelDir` | 2 | Measurements before travel direction is trusted |
| `kOverlapFraction` | 0.5 | Fraction of combined ground radius treated as overlap |
| `kBesideHalfX` / `kBesideHalfZ` | 600 | Alongside-suppression zone half-extents (6 m) |
| `kRoadHalfWidth` | 893.0 | Mirror of the QML road half-width |
| `kCityInset` | 2100 | Mirror of the QML building facade distance |
| `kUntrackedKeyBase` | −1000 | Base for synthetic keys given to untracked detections |

**On untracked detections:** every untracked object arrives carrying
`track_id = -1` by the message's own definition. Keying the track hash on that
value collapsed all of them into a single entry, so N untracked objects rendered
as exactly one — and the same would happen to the entire scene if the tracker
were ever disabled. They carry no identity worth preserving, so each gets a
per-message synthetic negative key and passes straight through without smoothing.

---

## 6. C++ Backends

### 6.1 BluetoothManager

A2DP/AVRCP media transport for a connected phone.

Tracks `org.bluez.MediaPlayer1` and surfaces track metadata (title, artist,
album), playback status, and position. Emits `connectedChanged`,
`playerStatusChanged`, `trackInfoChanged` and `deviceNameChanged`, which
`Main.qml` mirrors into the shared now-playing state.

Playback control is issued as AVRCP commands to the phone; the head unit does not
decode the stream itself.

### 6.2 BluetoothHWManager

Adapter and device management: power state, discoverability, discovery
start/stop, pair, connect, disconnect and remove.

Exposes discovered and paired devices as models with address, name, class icon,
paired/trusted/connected flags and RSSI.

Carries a `mediaActive` flag, asserted from `main.cpp`, which suppresses inquiry
while A2DP is playing. Inquiry starves the ACL link and audibly breaks up music.

### 6.3 BluetoothAgent

Implements `org.bluez.Agent1`. BlueZ delegates **all** pairing interaction to a
registered agent — without one, the Secure Simple Pairing methods that current
phones use (numeric comparison, passkey entry) cannot be completed from the HMI
at all.

Capability is **`DisplayYesNo`**: the head unit can show a six-digit passkey and
the driver confirms it matches the phone. That is the correct profile for a
device with a display and no keyboard. `NoInputNoOutput` would silently downgrade
every pairing to Just Works, which is weaker and shows the driver nothing.

`RequestConfirmation` uses a **delayed D-Bus reply**: the call is held open while
the driver decides and answered later from `resolvePending()`. Replying
immediately would mean accepting a pairing nobody saw.

### 6.4 BlueZ

Shared D-Bus plumbing for both Bluetooth backends: service and interface name
constants, `QDBusArgument` marshalling for the nested `GetManagedObjects` types,
and async wrappers for `GetManagedObjects` and `Properties.GetAll`.

It exists because both managers previously carried their own hand-rolled copy of
object enumeration, with different bugs in each.

Every call is asynchronous, and callbacks are scoped to a context object — if
that object dies first, the callback never runs.

### 6.5 WifiManager

NetworkManager over D-Bus: radio enable/disable, scan, access-point enumeration
with SSID/strength/security, connect (with or without a passphrase), disconnect,
and forget.

Exposes `connectedSsid`, which the launcher's online indicator and the
`WindowBar` status icon both bind to — so the two can never disagree about
whether the vehicle has a link.

### 6.6 WifiCredSender

Hands Wi-Fi credentials to the vehicle host over CAN by invoking the
`wifi_cred_send` tool, which performs SecOC authentication and ISO-TP
segmentation.

Two properties of this class are deliberate and load-bearing:

**Credentials go in on stdin, never in argv.** Anything in `argv` is readable by
every user on the machine through `ps aux` and `/proc/<pid>/cmdline`. A password
must not go there.

**It is asynchronous.** The transfer waits on ISO-TP flow control from the host,
and blocking the GUI thread on that would freeze the head unit.

Exit code 0 means **delivered**, not **accepted**. The host returns no verdict
over CAN, so a MAC or freshness rejection is only visible in the host's own log.

### 6.7 USBManager

UDisks2-based mass-storage handling: device arrival and removal, mount and
unmount, and an asynchronous recursive scan of mounted volumes for playable
media. The scan runs on the Qt Concurrent pool because it can take seconds on a
large stick.

### 6.8 MediaLibrary

A directory-backed `QAbstractListModel` with `fileName` and `filePath` roles. Two
instances are constructed — `MediaLibrary::music()` and `MediaLibrary::video()` —
differing only in their glob filters.

It deliberately does **not** use `Qt.labs.folderlistmodel`. That is a separate QML
plugin, not part of the base `qtdeclarative` install, and an image that omits it
fails at load time with *"FolderListModel is not a type"* — taking down the whole
UI, not just the page that used it. Listing a directory is a few lines of `QDir`,
so the runtime dependency is not worth the risk on a head unit.

Location is resolved at runtime, in priority order:

1. The environment override (`IVI_MUSIC_DIR` / `IVI_VIDEO_DIR`)
2. `/var/lib/ivi/media` on the target board
3. The XDG user directory, else `$HOME/<fallback>`, on a developer machine

Hardcoding a path would fail silently: the developer machine and the vehicle do
not share a username, so a literal `/home/<someone>/Music` lists nothing on the
target. A `QFileSystemWatcher` triggers `refresh()` when the directory changes.

### 6.9 SystemVolumeController

PulseAudio sink volume and mute, exposed as `volume`, `maxVolume` and `muted`
with a `toggleMute()` invokable. Bound by `WindowBar`, so the volume control is
available from every page.

### 6.10 SpeechManager

Offline speech recognition via **Vosk**. Captures from the default input through
`QAudioSource`, feeds frames to a `VoskRecognizer`, and exposes `listening` and a
live `partialResult` alongside a `resultReady(text)` signal for finalised
utterances.

Offline by design — voice navigation must work with no network.

### 6.11 AmbientLightManager

Drives the cabin WS2812 strip over SocketCAN.

**It sends intent, not pixels.** The head unit says "static, this colour, this
brightness" and the ESP32 renders it. Six LEDs is 18 bytes of pixel data, which
would need ISO-TP segmentation on every animation tick — a continuous flood on a
bus that also carries ultrasonic telemetry and OTA traffic. Intent fits in a
single classic 8-byte frame, and the strip keeps doing the right thing when the
head unit reboots.

Four mechanisms make the link robust:

| Mechanism | Purpose |
|---|---|
| **Coalescing timer** | Dragging a brightness slider emits changes every frame. Writes are collapsed and sent at a fixed rate, with the final value always going out because the timer fires once more after the last change. |
| **Duplicate suppression** | The last payload (bytes 0–6, excluding the rolling sequence counter) is retained so a frame telling the ECU nothing new is dropped. |
| **Reopen timer** | `can0` is usually not up when the UI starts, same as the network. One failed open at startup must not disable the feature for the session. |
| **Heartbeat** | The ECU boots dark and keeps no state. A purely event-driven link would leave it dark forever after an ECU reset, because the head unit already sent its only frame. Periodic re-assertion is how state signals normally work on CAN, and it makes a reset heal itself. |

There is deliberately **no SecOC** here, unlike `WifiCredSender`: a MAC plus
freshness counter would not fit in 8 bytes and would drag ISO-TP back in for what
is a comfort feature. The safety envelope belongs in the ECU instead — it must
refuse unsafe modes whatever arrives on the wire, because anything can inject on
a shared bus and nothing here can be trusted to be the only sender.

### 6.12 Perception classes

| Class | Role |
|---|---|
| **RosNode** | Owns the `qt_pcl_visualizer` node and its spin thread. Subscribes to detections, velocity, IMU and GNSS. Converts message corners into `DetectionData` and feeds the smoother. |
| **DetectionData** | Plain struct passed between layers: position, scale, rotation, colour, label, confidence, track ID. |
| **DetectionSmoother** | Track association, interpolation, lifecycle, gating and placement rules. The bulk of the perception logic. |
| **DetectionModel** | `QAbstractListModel` of smoothed detections, plus a `detectCount` property for the HUD. |
| **DetectionInstancing** | `QQuick3DInstancing` subclass building a packed instance table, filtered by label. |
| **CarInfo** | Vehicle telemetry as bindable properties: velocity, IMU quaternion, latitude, longitude, altitude. |
| **BoxTransform** | Free function converting eight corners into position, scale and quaternion. |

---

## 7. QML Logic Modules

### 7.1 WeatherStore

A singleton, stale-while-revalidate cache — the only weather state in the
application.

The launcher card and the weather page previously owned a `WeatherAPI` each, and
because the page is pushed from a `Component` it was rebuilt from scratch on
every entry and fired a fresh geocode-plus-forecast pair each time. Those two
round trips run in sequence: roughly two seconds of empty page, every entry, for
numbers the upstream service only recomputes every quarter hour.

The store fixes that with four properties:

- **Synchronously readable.** `entryFor(city)` returns cached data immediately,
  so a page paints on its first frame.
- **TTL-gated.** A request only leaves the vehicle when the cached reading has
  aged past `ttlMs` (10 minutes). Open-Meteo recomputes its current block roughly
  every 15.
- **Keyed by city**, capped at `maxEntries` (8), so the page's search box and the
  launcher's preferred city cannot evict one another and the cache cannot grow
  unbounded across a long session.
- **Persisted.** The most recent entry is written to disk, so a cold boot with no
  network starts populated rather than blank. Only the 24 hourly samples the page
  actually reads are retained (`hourlyKeep`), which is what keeps the saved copy
  small.

An `inFlight` city doubles as the guard that stops the page and the launcher
requesting the same thing at the same moment on entry. Signals are `updated`,
`notFound` and `failed`.

### 7.2 WeatherAPI

The transport underneath the store: Open-Meteo geocoding to resolve a city name
to coordinates, then a forecast request for current conditions, daily and hourly
blocks. `timezone=auto` so returned timestamps are local to the queried city.

### 7.3 RadioAPI

radio-browser.info search by name, country and tag, returning station name,
stream URL, favicon, codec and bitrate into a shared `ListModel`. Emits
`loadingStarted` and `loadingFinished`, which `Main.qml` maps onto the global
`radioIsLoading` flag.

---

## 8. Reusable Components

| Component | Purpose | Notable behaviour |
|---|---|---|
| **WindowBar** | Shared top bar on every non-launcher page | Title, back button, brightness and volume sliders, and Wi-Fi/Bluetooth status icons that navigate straight into the relevant settings section |
| **MediaCard** | Now-playing summary | Artwork, title, subtitle and transport; binds to the unified `mediaPlaying` state so it is correct for both local and Bluetooth sources |
| **CarInfoPopup** | Modal vehicle information | Centered card over a dimming backdrop; click-outside dismisses |
| **AmbientCard** | Launcher ambient controls | Power, mode and palette only — the free colour picker stays in settings, deliberately not offered to a moving driver |
| **VirtualKeyboard** | On-screen text entry | Shift, 64-character limit, password mode with a reveal toggle, live preview area, `accepted`/`cancelled` signals. Required because the head unit has no physical keyboard |

---

## 9. Vehicle Integration

### 9.1 ROS 2 topics

| Topic | Type | Direction | Use |
|---|---|---|---|
| `/kitti/velo` | `sensor_msgs/PointCloud2` | in | Raw lidar (callback currently inactive) |
| `/object_detections_3d` | `object_detection_msgs/Object3dArray` | in | Detections with label, confidence, track ID, 8 corners |
| `/kitti/oxts/gps/vel` | `geometry_msgs/TwistStamped` | in | Ego speed → HUD, wheel spin, travel-direction classification |
| `/kitti/oxts/imu` | `sensor_msgs/Imu` | in | Orientation quaternion |
| `/kitti/oxts/gps/fix` | `sensor_msgs/NavSatFix` | in | Latitude, longitude, altitude |

`Object3d` carries `label` (0 pedestrian, 1 cyclist, 2 car), `confidence_score`,
`track_id` (−1 when untracked), and a `BoundingBox3d` of eight corner points.

### 9.2 Ambient lighting over CAN

**Frame `0x500`**, classic 8-byte, one shot per state change:

| Byte | Field | Values |
|---|---|---|
| 0 | mode | 0 off · 1 static · 2 breathe · 3 chase · 4 scanner · 5 rainbow |
| 1 | red | 0–255 |
| 2 | green | 0–255 |
| 3 | blue | 0–255 |
| 4 | brightness | 0–255 |
| 5 | speed | effect period; unused while static |
| 6 | zone mask | one bit per LED; `0x3F` is all six |
| 7 | sequence | rolling, lets the ECU spot a dropped update |

`0x500` is a **high ID on purpose**: CAN arbitration is lowest-ID-wins, so
decoration always loses to ultrasonic telemetry at `0x160` and warnings at
`0x400`.

Mode `0` on the wire means off and is derived from the `on` property rather than
stored in `mode` — turning the strip off and back on must return to the effect
that was running.

### 9.3 Wi-Fi credential handoff

On a successful Wi-Fi connection the SSID and passphrase are forwarded to the
vehicle host through `WifiCredSender`, which runs the `wifi_cred_send` tool with
SecOC authentication and ISO-TP segmentation over `can0`, keyed from
`/etc/wifi_secoc.key`.

Credentials are passed on **stdin**. See [6.6](#66-wificredsender).

---

## 10. Design System

**Palette**

| Token | Value | Use |
|---|---|---|
| Deep navy | `#0e0e14` → `#1a1a2e` → `#2e2e4a` | Page and bar gradients |
| Scene background | `#080a0d` | Drive View clear colour and fog |
| Amber accent | `#D08831` | Primary accent, focus, active states |
| Ego blue | `#0066cc` | Ego vehicle, "Ego" legend entry |
| Detection grey | `#a6a6a6` | Detected objects |
| Neon cyan | `#00e5ff` | Lane markings, neon city accent |
| Neon magenta | `#ff2ea6` | Secondary neon city accent |
| Primary text | `#f2f5f8` | Headings and values |
| Secondary text | `#9aa4b0` / `#8899bb` | Labels and captions |
| Online green | `#3ad07a` | Connectivity indicator |

Panels are translucent white over the scene — `rgba(1,1,1,0.05)` fill with an
`rgba(1,1,1,0.12)` border — with 16–28 px corner radii.

The Drive View HUD is **inverted relative to the earlier design**: it was dark
ink on a light grey void, which over a real road surface reads as unlit text on
unlit tarmac. It is light-on-dark instead, rather than fighting the ground for
contrast. Panel backgrounds are opaque enough to sit over texture; the previous
9%-black wash was invisible over paving.

**Responsive scaling.** Rather than fixed pixel sizes, the 3D page derives
everything from its own dimensions:

```qml
readonly property real _m:    width * 0.022     // margin
readonly property real _fLg:  Math.max(16, height * 0.030)
readonly property real _btnW: width  * 0.125
```

Font sizes carry a `Math.max` floor so text never becomes unreadable on a small
viewport.

**Motion.** 200 ms for hover and colour transitions; 300 ms for the splash fade;
700 ms `InOutCubic` for camera view changes; multi-second looping animations for
ambient drift. Every state change that a user causes is animated; nothing snaps
except where snapping is the point (the first frame of a new track).

**Interaction rules.**

- Touch targets are sized for a finger, not a cursor.
- Anything pressable reacts on hover, so affordance is visible before contact.
- Destructive actions (forget network, remove device) require confirmation.
- Text entry always raises the virtual keyboard; there is no physical one.
- Controls that could distract while driving are kept off the launcher.

---

## 11. State, Navigation and Persistence

**The global window pattern.** `Main.qml`'s `ApplicationWindow` is the single
source of truth for anything that must outlive a page: current media, radio
search state, preferred city, and application brightness. Pages receive state
through required properties and write back through signals or direct binding on
`mainWindow`.

This exists because pages are pushed from `Component`s and destroyed on back
navigation. State held inside a page does not survive leaving it.

**Navigation** is a single root `StackView`. Each destination is pushed on
selection and popped by the `WindowBar` back button. The Settings and Media hubs
each contain their own nested `StackView` for sub-pages, so back inside a hub
returns to the hub rather than to the launcher.

`openSettingsSection(section)` lets the status icons in `WindowBar` reach Wi-Fi
or Bluetooth from anywhere; if Settings is already current it switches section
instead of pushing a duplicate.

**Persistence** uses `QtCore.Settings`, which requires organisation and
application identifiers set before any QML `Settings` element is created:

```cpp
QGuiApplication::setOrganizationName(QStringLiteral("IVI"));
QGuiApplication::setOrganizationDomain(QStringLiteral("ivi.local"));
QGuiApplication::setApplicationName(QStringLiteral("IVI"));
```

Without these, `QSettings` refuses to initialise and **every** saved value is
silently discarded at every boot.

| Key | Purpose |
|---|---|
| `savedCity` | Preferred weather city |
| `lastTemp` / `lastDesc` / `lastEmoji` | Last successful reading, so a boot with no network shows real numbers rather than a placeholder |

`WeatherStore` additionally persists its most recent cache entry, and
`AmbientLightManager` saves and restores its own state so the cabin returns to
the driver's chosen lighting.

---

## 12. Configuration Surface

**Environment variables**

| Variable | Effect |
|---|---|
| `IVI_MUSIC_DIR` | Overrides the audio library location |
| `IVI_VIDEO_DIR` | Overrides the video library location |
| `IVI_CAN_IFACE` | SocketCAN interface for ambient lighting; lets a bench point at a `vcan` without displacing a real `can0` |

**Build option**

| Option | Default | Effect |
|---|---|---|
| `AMBIENT_CAN_SIMULATE` | `OFF` | Prints ambient CAN frames to the terminal instead of opening the bus |

The simulation flag is defined **either way** rather than only when enabled.
Defining it conditionally meant a build could never turn simulation back off —
whatever the source happened to default to won — and a head unit could ship
printing frames to its log while driving nothing.

**Compile-time dependencies**

Qt 6.8+ (Quick, Quick3D, Location, Positioning, DBus, Concurrent, Multimedia),
PulseAudio (`libpulse`), Vosk, and ROS 2 (`rclcpp`, `sensor_msgs`,
`geometry_msgs`, `std_msgs`, `object_detection_msgs`).

---

## 13. Known Limitations

Recorded honestly, because a reader will otherwise assume these are bugs
nobody noticed.

- **The point cloud callback is inactive.** `RosNode::pointCloudCallback` is
  fully written but commented out. The subscription still exists, so the topic is
  received and discarded.
- **`detectCount` includes coasting ghosts.** They are real rows in the model, so
  the HUD reads slightly higher than the detector reports while objects are
  leaving. Suppressed tracks *are* excluded once faded.
- **Road geometry is mirrored, not shared.** `kRoadHalfWidth` and `kCityInset` in
  C++ duplicate QML values because C++ cannot read them. Widening the road
  requires changing both, and the pedestrian pavement band currently has only
  about 0.24 m of margin.
- **Coasting is bounded extrapolation.** A slowly overtaken vehicle may be dead
  reckoned for several seconds. If it brakes or turns off while behind you, the
  prediction will not know. It is capped at 10 s and confined to the road, but it
  is still a guess.
- **The alongside-suppression rule hides a real vehicle.** A car drawn backwards
  while travelling your way is not rendered at all while it is beside you. This
  is a deliberate trade — an absent box over a misleading one — but it does mean
  a real vehicle in the blind spot goes undrawn.
- **A stale detector doubles everything.** If two detector nodes publish to
  `/object_detections_3d`, every object appears twice with different track IDs.
  The overlap gating absorbs much of it, but the real fix is to check
  `ros2 topic info /object_detections_3d` reports exactly one publisher.
- **Wi-Fi credential delivery is unacknowledged.** Exit code 0 means delivered,
  not accepted; a MAC or freshness rejection is only visible in the host log.
- **Ambient lighting is unauthenticated.** Deliberately — see
  [6.11](#611-ambientlightmanager) — with the safety envelope pushed into the
  ECU.
- **Drive View controls are debug instrumentation.** The settings drawer, camera
  readout and view buttons are development aids, not shipping UI.

---

## 14. Glossary

| Term | Meaning |
|---|---|
| **A2DP** | Advanced Audio Distribution Profile — Bluetooth stereo audio streaming |
| **AVRCP** | Audio/Video Remote Control Profile — transport control and metadata |
| **AB3DMOT** | The upstream 3D multi-object tracker assigning track IDs |
| **Coasting** | Dead reckoning a detection past the end of the sensor's field of view |
| **Ego** | The vehicle the head unit is installed in |
| **Ghost** | A coasting track: a prediction, not a measurement |
| **HDRI** | High Dynamic Range Image used as an environment light probe |
| **IBL** | Image-Based Lighting |
| **ISO-TP** | ISO 15765-2 transport protocol; segments payloads larger than 8 bytes over CAN |
| **Instancing** | Drawing many copies of one mesh in a single pass from a transform table |
| **KITTI** | The autonomous-driving dataset whose topic layout the perception input follows |
| **SecOC** | AUTOSAR Secure Onboard Communication — MAC plus freshness on CAN frames |
| **Tentative** | A track seen too few times to be drawn yet |
| **WMO code** | World Meteorological Organization weather code, mapped to icon and text |

---

<div align="center">

**IVI Head Unit** — Qt 6 · Quick 3D · ROS 2 · C++

</div>
