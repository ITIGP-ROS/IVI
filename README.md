# IVI Dashboard

> A modern, feature-rich **In-Vehicle Infotainment (IVI)** system built with **Qt 6 / QML** and a **C++ backend**, designed to run on embedded Linux platforms including the Raspberry Pi 3B+.

---

## Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Features](#features)
  - [Launcher / Home Screen](#launcher--home-screen)
  - [Weather Page](#weather-page)
  - [Media Player Page](#media-player-page)
    - [Audio Player](#audio-player)
    - [Video Player](#video-player)
    - [Radio Player](#radio-player)
  - [Climate Control (HVAC) Page](#climate-control-hvac-page)
  - [Settings Page](#settings-page)
    - [Wi-Fi Settings](#wi-fi-settings)
    - [Bluetooth Settings](#bluetooth-settings)
- [Backend Components](#backend-components)
  - [BluetoothManager](#bluetoothmanager)
  - [BluetoothHWManager](#bluetoothhwmanager)
  - [WifiManager](#wifimanager)
  - [USBManager](#usbmanager)
  - [SystemVolumeController](#systemvolumecontroller)
  - [SpeechManager](#speechmanager)
- [QML API Modules](#qml-api-modules)
  - [WeatherAPI](#weatherapi)
  - [RadioAPI](#radioapi)
- [Reusable QML Components](#reusable-qml-components)
  - [WindowBar](#windowbar)
  - [MediaCard](#mediacard)
  - [CarInfoPopup](#carinfopopup)
- [Design System & UI Conventions](#design-system--ui-conventions)
- [Build System](#build-system)
  - [Dependencies](#dependencies)
  - [Building on Desktop](#building-on-desktop)
- [Raspberry Pi Deployment (Yocto)](#raspberry-pi-deployment-yocto)
  - [Step 1 — `local.conf` Additions](#step-1--localconf-additions)
  - [Step 2 — Yocto Recipe for the App](#step-2--yocto-recipe-for-the-app)
  - [Step 3 — Vosk Recipe](#step-3--vosk-recipe)
  - [Step 4 — Update the Vosk Model Path](#step-4--update-the-vosk-model-path)
  - [Step 5 — `config.txt` on the RPi](#step-5--configtxt-on-the-rpi)
  - [Step 6 — Launch Script or systemd Service](#step-6--launch-script-or-systemd-service)
  - [Step 7 — Build and Flash](#step-7--build-and-flash)
  - [Yocto Package Checklist](#yocto-package-checklist)
- [Author](#author)

---

## Overview

The **IVI Dashboard** is a full-featured infotainment application designed to replicate the experience of a production car head unit. It provides a unified interface for weather, media playback (USB audio, USB video, and internet radio), climate control, connectivity management (Wi-Fi and Bluetooth), and voice-activated navigation—all rendered in a polished dark-navy and amber design language.

The application is architected as a **Qt Quick (QML) frontend** backed by a **C++ engine**, communicating over Qt's property-binding and signal/slot system. The C++ backend handles all hardware-level interactions: PulseAudio for volume, D-Bus for Wi-Fi (via NetworkManager) and Bluetooth (via BlueZ 5), UDisks2 for USB drives, and the Vosk library for offline speech recognition.

Key design goals:
- **Frameless, embedded-first UI** — runs at 1024×600 without a window manager.
- **Offline-capable** — speech recognition and core UI require no internet; weather and radio use public free APIs.
- **Persistent state** — radio search state, last-used city, and media playback survive navigation between pages.
- **Raspberry Pi ready** — ships with a detailed Yocto meta-layer integration guide.

---

## Project Structure

```
IVI/
├── main.cpp                     # Application entry point; registers all C++ backends
├── Main.qml                     # Root ApplicationWindow; splash screen, StackView, global state
├── CMakeLists.txt               # CMake build configuration (Qt 6.8+, PulseAudio, Vosk)
├── resources.qrc                # Qt resource file (icons, images, videos, fonts)
│
├── API/
│   ├── WeatherAPI.qml           # Open-Meteo geocoding + forecast integration
│   └── RadioAPI.qml             # radio-browser.info station search + playback control
│
├── Backend/
│   ├── BluetoothManager.cpp/hpp       # A2DP / AVRCP media player via BlueZ D-Bus
│   ├── BluetoothHWManager.cpp/hpp     # Bluetooth adapter power, scan, pair, connect
│   ├── WifiManager.cpp/hpp            # Wi-Fi enable/disable, scan, connect via NetworkManager D-Bus
│   ├── USBManager.cpp/hpp             # UDisks2 USB detection, mount, async file scan
│   ├── SystemVolumeController.cpp/hpp # PulseAudio system volume and mute control
│   └── SpeechManager.cpp/hpp         # Vosk offline speech-to-text, QAudioSource capture
│
├── Components/
│   ├── MediaCard.qml            # Now-playing card with artwork, title, and transport controls
│   ├── WindowBar.qml            # Shared top bar with title, back, brightness, and volume controls
│   └── CarInfoPopup.qml         # Modal vehicle information overlay
│
├── MediaPages/
│   ├── AudioPage.qml            # USB audio player (Bluetooth + USB sources, playlist)
│   ├── VideoPage.qml            # USB video player with full-screen playback
│   └── RadioPage.qml            # Internet radio browser and player
│
├── pages/
│   ├── WeatherPage.qml          # Full weather dashboard (current, hourly, 7-day forecast)
│   ├── MediaPlayerPage.qml      # Media hub routing to Audio, Video, and Radio sub-pages
│   ├── ClimateControlPage.qml   # Dual-zone HVAC controller (front + rear)
│   └── SettingPage.qml          # Settings hub routing to Wi-Fi and Bluetooth sub-pages
│
└── SettingPages/
    ├── WiFiPage.qml             # Wi-Fi network list, connect/disconnect, password dialog
    └── BluetoothPage.qml        # Bluetooth device list, pair, connect, disconnect
```

---

## Architecture

The application follows a **layered architecture** that cleanly separates hardware access, application logic, and UI rendering.

```
┌──────────────────────────────────────────────────────────────────┐
│                         QML / UI Layer                           │
│  Main.qml · pages/ · MediaPages/ · SettingPages/ · Components/  │
│  Pure declarative UI; binds to C++ properties and signals        │
└────────────────────────────┬─────────────────────────────────────┘
                             │  Q_PROPERTY bindings, signals/slots
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                      QML API / Logic Layer                       │
│  WeatherAPI.qml  ·  RadioAPI.qml                                 │
│  XMLHttpRequest to public REST APIs; emits structured signals    │
└────────────────────────────┬─────────────────────────────────────┘
                             │  context properties (setContextProperty)
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                     C++ Backend Layer                            │
│  BluetoothManager · BluetoothHWManager · WifiManager            │
│  USBManager · SystemVolumeController · SpeechManager            │
│  Each is a QObject registered in QQmlContext                     │
└────────────────────────────┬─────────────────────────────────────┘
                             │  Linux system APIs
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                       Hardware / OS Layer                        │
│  D-Bus (BlueZ 5, NetworkManager, UDisks2)                        │
│  PulseAudio (system volume, Bluetooth audio, microphone)         │
│  Vosk (offline speech recognition)                               │
│  Qt Multimedia / GStreamer (audio & video playback)              │
└──────────────────────────────────────────────────────────────────┘
```

**State management** follows a "global window" pattern: `Main.qml`'s `ApplicationWindow` acts as the single source of truth for cross-page state (current media, radio state, preferred city, brightness). Individual pages receive state via required properties and write back through signals or direct property binding on `mainWindow`.

**Navigation** uses a single `StackView` rooted in `Main.qml`. Each destination is a `Component` that gets pushed onto the stack when selected from the launcher, and popped when the back button in the `WindowBar` is pressed. The Settings and Media pages contain their own nested `StackView` for their sub-pages.

---

## Features

### Launcher / Home Screen

The home screen is the entry point after the splash screen finishes. It presents four animated app tiles (Weather, Media, Climate, Settings) alongside live status widgets.

**App Tiles**

The tiles are laid out inline in `Main.qml` rather than as a shared component. Each has:
- A colored top accent bar that matches the app's theme color.
- A circular icon container with a semi-transparent tinted background.
- A title and subtitle text block.
- A smooth scale + border-glow hover animation driven by `MouseArea` and `Behavior` animations.
- Floating animation (`NumberAnimation` looping between y offsets) that adds a subtle "breathing" liveliness to the idle state.

**Live Weather Widget**

A compact card on the launcher displays:
- Current temperature in degrees Celsius.
- A weather emoji mapped from the WMO weather code (e.g., `☀️` for clear, `🌧️` for rain).
- A short text description of the current condition.
- The currently configured city name.

The data is fetched automatically on launch and refreshed whenever `mainWindow.preferredCity` changes.

**HVAC Quick-Control Widget**

A mini version of the Climate Control page lives on the launcher, giving the driver immediate access to:
- Air direction mode buttons (three icons for vent, floor, defrost).
- Temperature adjustment (arc-style canvas gauge).
- Fan speed control.
- Power toggle.

All HVAC state is stored directly on `launcherItem` and is two-way synced with the full `ClimateControlPage` so that changes made on the launcher are reflected in the full page and vice versa.

**Splash Screen**

On launch, an `AnimatedImage` plays the branded clip (`assets/videos/vpace_splash.gif`, 90 frames, ~3 s) full-screen from embedded resources, cropped to fill with `PreserveAspectCrop`.

`AnimatedImage` loops forever and has no "finished" signal, so the end of the clip is detected by watching `currentFrame` reach `frameCount - 1`. Playback is stopped *on* that frame — letting it wrap would visibly restart the logo underneath the fade — and a 300 ms `NumberAnimation` fades the splash out, after which `splashDone` is set to `true` and the item is hidden. A 6 s backstop timer forces the same transition if the gif is missing or fails to decode, so a bad resource can never strand the head unit on a splash it cannot leave.

**Voice Activation**

A microphone button in the launcher activates offline voice recognition. When pressed, the button turns red and the `SpeechManager` starts listening. Recognized commands are routed to navigation actions:
- "weather" / city names → opens `WeatherPage` for that city.
- "media" / "music" / "video" → opens `MediaPlayerPage`.
- "climate" / "hvac" → opens `ClimateControlPage`.
- "settings" → opens `SettingPage`.

While listening, a partial result text updates live beneath the mic button to give visual feedback of what the system is hearing.

**Car Info Popup**

A car icon button opens a modal popup (`CarInfoPopup`) that shows static vehicle information (model, year, VIN, service status) in a centered card with a backdrop overlay. Clicking outside the card closes it.

---

### Weather Page

The Weather page is a full-screen meteorological dashboard powered by the **Open-Meteo** free API (no API key required).

**Current Conditions Panel**

The upper portion of the page displays:
- A large weather emoji and temperature for the current moment.
- Apparent ("feels like") temperature.
- Wind speed and direction (the direction arrow SVG is rotated dynamically to match the wind bearing).
- Relative humidity, surface pressure, UV index, and cloud cover percentage.
- Rain accumulation for the last hour.
- A day/night indicator from the `is_day` field.

**Hourly Temperature Chart**

A scrollable horizontal row of hourly temperature bubbles spans the next 24 hours. Each bubble shows a time label and temperature, with the current hour highlighted in the accent amber color.

**7-Day Forecast Strip**

A row of 7 day cards each show:
- The abbreviated day name.
- A weather emoji for that day's dominant condition.
- Min and max temperature range.

**City Search**

A text input in the `WindowBar` (or a dedicated field) allows the user to type a new city name. The search flows through the geocoding API to resolve coordinates, then fetches forecast data. The resolved city name is persisted to Qt `Settings` (stored on disk) so it survives restarts. The default city is set to `"Giza"`.

**Weather Code Mapping**

The QML function `weatherEmoji(code, isDay)` maps all standard WMO weather interpretation codes (0–99) to human-readable emoji strings:
- 0 = `☀️` / `🌙`
- 1–2 = `🌤️`
- 3 = `☁️`
- 45–48 = `🌫️`
- 51–55 = `🌦️`
- 61–65 = `🌧️`
- 71–75 = `❄️`
- 80–82 = `🌦️`
- 95–99 = `⛈️`

---

### Media Player Page

The Media Player page acts as a hub that routes into three distinct sub-pages via a nested `StackView`: Audio, Video, and Radio. A shared `MediaPlayer` instance (created in `Main.qml`) is injected into each sub-page so that audio playback is persistent across navigation — switching from the Radio page back to the launcher does not stop the stream.

**Global Media State**

`Main.qml` maintains these cross-page properties:
- `currentMediaTitle` / `currentMediaSubtitle` / `currentMediaFavicon` — displayed in `MediaCard` on the launcher.
- `currentMediaType` — integer discriminator (0 = none, 1 = radio, 2 = audio, 3 = video).
- `mediaPlaying` — bound to the shared player's `playbackState`.

#### Audio Player

The Audio page (`MediaPages/AudioPage.qml`) provides:

**Source Selection (Left Panel)**

A narrow left panel lists available audio sources:
- **Bluetooth** — streams audio from the connected A2DP device. Track metadata (title, artist, album) and playback state are read from `btManager` (the `BluetoothManager` C++ backend). Transport controls (play, pause, next, previous, stop) are wired directly to `btManager` slots.
- **USB** — when a USB drive is detected by `usbManager`, its audio file list (`usbManager.audioFiles`) populates the playlist.
- **URL** — a text input accepts any HTTP/HTTPS audio stream URL for direct playback.

**Now-Playing Panel**

The center/right area shows:
- Cover art area (placeholder or favicon for radio).
- Track title, artist, and album.
- Playback position slider with elapsed and total time labels.
- Transport buttons: previous, play/pause, next.
- Shuffle and repeat toggle buttons.

**Playlist Panel**

A `ListView` of available tracks (from USB or a curated list) with the currently playing track highlighted. Tapping a track loads it immediately. The playlist scrolls independently and supports keyboard navigation in desktop mode.

**Error Handling**

The `Connections` block on the shared `MediaPlayer` maps `onErrorOccurred` to a human-readable error banner covering common failure cases: `NetworkError`, `FormatError`, `AccessDeniedError`, and `ResourceError`.

#### Video Player

The Video page (`MediaPages/VideoPage.qml`) has its own dedicated `MediaPlayer` (separate from the shared audio player) so that it can drive a `VideoOutput` component without conflicting with audio streams.

**Source Selection**

A left panel (same layout as Audio) supports:
- **USB** — populates a playlist from `usbManager.videoFiles`. Supported extensions are detected by `USBManager`'s internal scanner (`.mp4`, `.mkv`, `.avi`, `.mov`, `.webm`, and others).
- **URL** — direct stream URL input.

**Video Output**

A `VideoOutput` item fills the main area and is bound to the local `videoPlayer`. The aspect ratio is preserved (`fillMode: PreserveAspectFit`).

**Full-Screen Toggle**

A button in the control bar toggles full-screen playback by temporarily collapsing the left panel and control bar, expanding `VideoOutput` to fill the entire page.

**Playback Controls**

Position slider, elapsed/total time, play/pause, seek backward/forward (10-second jumps), and volume control overlay (independent from the system volume).

#### Radio Player

The Radio page (`MediaPages/RadioPage.qml`) fetches live internet radio stations from the public **radio-browser.info** API.

**Station Search**

A search bar at the top is bound to `mainWindow.radioSearchQuery`. When the user types and presses Enter, `RadioAPI.fetchStations()` is called, which queries the radio-browser.info REST endpoint for the top 100 stations matching the query, ordered by vote count. The loading spinner shows `radioIsLoading` state (managed globally so it can be shown in other contexts too).

**Station List**

Results appear in a scrollable `ListView`. Each row shows:
- Station favicon (falls back to a radio icon if the favicon URL is empty or fails to load).
- Station name.
- Country flag emoji and codec string as subtitle.
- Vote count badge.

Tapping a row calls `RadioAPI.playStation(station)`, which updates global media state and begins streaming.

**Transport Controls**

Below the list a mini-player bar shows the currently playing station name, a play/pause toggle, and previous/next buttons that cycle through the fetched station list.

**Status Indicator**

A colored dot reflects the `MediaPlayer`'s `mediaStatus`:
- Amber — buffering.
- Green — buffered and playing.
- Dark amber — stalled.
- Dark — no media.

**Persistent State**

Because `globalStationsModel` and `globalRadioAPI` are properties of `mainWindow`, navigating away from the Radio page and returning does not clear the station list or stop playback. The user can open the Weather page, return to Media, and find the station still playing.

---

### Climate Control (HVAC) Page

The Climate Control page (`pages/ClimateControlPage.qml`) provides a **dual-zone HVAC controller** for both the front and rear cabin zones.

**Dual-Zone Layout**

The page is split into a Front zone (left) and a Rear zone (right), each with identical controls:
- **Temperature Dial** — an arc-shaped `Canvas` gauge that updates live as the value changes. The arc is drawn in the accent amber color, and the numeric temperature is displayed in the center.
- **Fan Speed Slider** — a styled horizontal `Slider` (Qt Quick Controls 2) labeled with the current speed number (0–8).
- **Air Direction Mode** — three icon buttons selecting the airflow direction (face vents, floor, windshield). The selected mode is highlighted in the accent green color.
- **Power Toggle** — an on/off button that enables or disables the zone.

**Global Controls**

Between the two zones a center column provides:
- **Sync Toggle** — when active, changes to the front zone are mirrored to the rear zone automatically.
- **Auto Mode** — single button that sets both zones to automatic temperature management.
- **Recirculation Toggle** — enables cabin air recirculation.
- **Air Quality Toggle** — enables the cabin air filter / ionizer.

**Two-Way Sync with Launcher**

HVAC state is stored as properties on `launcherItem` in `Main.qml`. The `ClimateControlPage` receives these values as required properties and writes changes back via property bindings, so the mini HVAC widget on the launcher always reflects the current state even when the full page is not open.

**Visual Design**

The page background is a dark navy gradient (`#082839` → `#10475E` → `#082839`) with a subtle dot-grid pattern drawn on a `Canvas` at 4% opacity. The accent color for active elements is `#18b78f` (teal-green). Temperature values below 18°C show a blue tint; above 25°C an amber tint.

---

### Settings Page

The Settings page (`pages/SettingPage.qml`) is a navigation hub that uses its own nested `StackView`. The main page shows two large glassmorphism cards — one for Wi-Fi and one for Bluetooth — each showing the current connection status and navigating to the respective detail page on tap.

**Glassmorphism Cards**

Each card uses a `Rectangle` with:
- Semi-transparent background (`rgba(255,255,255,0.08)`).
- A subtle white border at 12% opacity.
- Rounded corners (16 px radius).
- A `DropShadow` effect from `Qt5Compat.GraphicalEffects`.
- Scale animation on hover.

The Wi-Fi card shows the connected SSID (from `WifiManager.connectedSsid`). The Bluetooth card shows whether Bluetooth is enabled.

#### Wi-Fi Settings

`SettingPages/WiFiPage.qml` is a full Wi-Fi management interface backed by `WifiManager`.

**Enable / Disable Toggle**

A `Switch` control at the top of the page is two-way bound to `WifiManager.wifiEnabled`. When toggled on, the backend enables the Wi-Fi adapter via D-Bus NetworkManager and automatically triggers a scan.

**Network Scanning**

A "Scan" button calls `WifiManager.scanNetworks()`. While scanning, a `BusyIndicator` is shown. When `onScanFinished(networks)` fires, `networkListModel` is populated with the returned SSID list. If `WifiManager.connectedSsid` matches any entry, that entry is marked `connected: true` and displayed with a checkmark.

**Connecting to a Network**

Tapping a network entry checks whether a stored profile exists:
- If yes (already known network), `connectToSelectedNetwork(ssid)` is called directly.
- If no, a password dialog appears — a `Rectangle` overlay with a `TextField` for password input. Confirming calls `connectToNetwork(ssid, password)`.

The `WifiManager` emits `passwordRequired(ssid)` if an existing profile exists but authentication fails, re-triggering the password dialog.

**Connection Status Feedback**

`onConnectSuccess` / `onConnectFailed` signals from `WifiManager` update a small status text beneath the network list with success or failure messages. `onConnectedSsidChanged` refreshes the checkmark indicator in the list.

**Disconnecting**

A "Disconnect" button appears next to the connected network entry. It calls `WifiManager.disconnectFromNetwork()`.

#### Bluetooth Settings

`SettingPages/BluetoothPage.qml` provides hardware Bluetooth management via `BluetoothHWManager`, plus media metadata via `BluetoothManager`.

**Enable / Disable Toggle**

A `Switch` bound to `BluetoothHWManager.bluetoothEnabled`. Enabling triggers an automatic device scan.

**Device List**

`deviceListModel` is a `ListModel` populated from `onScanFinished(devices)`. Each entry shows:
- Device address.
- Device name (resolved asynchronously or shown as address until known).
- Connection status badge (Connected / Paired / Discovered).
- Three action buttons: Pair, Connect, Disconnect (shown/hidden based on current device state).

The page tracks `connectedAddresses[]`, `connectingAddress`, and `disconnectingAddress` properties to manage per-device loading states without a full model refresh.

**Signals from BluetoothHWManager**

| Signal | UI Action |
|---|---|
| `onScanStarted` | Shows scanning spinner |
| `onScanFinished(devices)` | Populates device list |
| `onPairSuccess(name)` | Shows success toast, updates row badge |
| `onPairFailed(reason)` | Shows error toast |
| `onConnectSuccess(name)` | Adds to `connectedAddresses` |
| `onConnectFailed(reason)` | Shows error toast |
| `onDisconnectSuccess(name)` | Removes from `connectedAddresses` |
| `onDeviceConnectionChanged(address, connected)` | Immediately updates the row |

**Media Metadata**

When a Bluetooth device is connected and streaming via A2DP, `BluetoothManager` exposes `trackTitle`, `trackArtist`, `trackAlbum`, and `playerStatus` as live properties. These are reflected in the Audio page's now-playing panel.

---

## Backend Components

All backend components are C++ classes that extend `QObject`, expose state via `Q_PROPERTY`, and are registered in the QML engine context in `main.cpp` using `setContextProperty`.

### BluetoothManager

**File:** `Backend/BluetoothManager.cpp/hpp`
**Context key:** `btManager`

Handles **Bluetooth media (A2DP/AVRCP)** integration by communicating directly with the **BlueZ 5** D-Bus interface (`org.bluez`).

| Property | Type | Description |
|---|---|---|
| `connected` | `bool` | Whether a Bluetooth device is currently connected |
| `deviceName` | `QString` | Friendly name of the connected device |
| `deviceAddress` | `QString` | MAC address of the connected device |
| `trackTitle` | `QString` | Currently playing track title (from AVRCP) |
| `trackArtist` | `QString` | Track artist |
| `trackAlbum` | `QString` | Track album |
| `playerStatus` | `QString` | BlueZ player status ("playing", "paused", "stopped") |

**Public Slots:** `play()`, `pause()`, `next()`, `previous()`, `stop()` — all send AVRCP commands via D-Bus.

**Polling mechanism:** A `QTimer` fires every 500 ms and calls `poll()`, which re-reads all properties from BlueZ using `getManagedObjects()` and `getProperties()`. This approach avoids the complexity of subscribing to BlueZ property-change signals while keeping the UI responsive to track changes.

**D-Bus interaction:** Uses raw `QDBusArgument` deserialization to avoid relying on auto-generated BlueZ bindings, which makes it more robust across BlueZ versions.

---

### BluetoothHWManager

**File:** `Backend/BluetoothHWManager.cpp/hpp`
**Context key:** `BluetoothManager`

Controls the **Bluetooth hardware adapter** (power on/off, device scanning, pairing, and connection) via the BlueZ `org.bluez.Adapter1` and `org.bluez.Device1` D-Bus interfaces.

| Property | Type | Description |
|---|---|---|
| `bluetoothEnabled` | `bool` | Read/write; controls adapter power via `org.bluez.Adapter1.Powered` |

**Invokable methods:**
- `scanDevices()` — calls `StartDiscovery` on the adapter; subscribes to `InterfacesAdded` to collect new device paths.
- `pairDevice(address)` — resolves the device path and calls `Pair()`.
- `connectDevice(address)` — calls `Connect()` on the resolved device path.
- `disconnectDevice(address)` — calls `Disconnect()`.

**DeviceWatcher helper class:** A lightweight `QObject` that subscribes to `PropertiesChanged` on a specific device D-Bus path and emits `connectionChanged(address, bool)` when the `Connected` property changes. A `DeviceWatcher` instance is created for each known device to provide real-time connection status without polling.

---

### WifiManager

**File:** `Backend/WifiManager.cpp/hpp`
**Context key:** `WifiManager`

Controls **Wi-Fi networking** through the **NetworkManager D-Bus API** (`org.freedesktop.NetworkManager`).

| Property | Type | Description |
|---|---|---|
| `wifiEnabled` | `bool` | Read/write; maps to the NetworkManager Wi-Fi device's managed state |
| `connectedSsid` | `QString` | SSID of the currently active connection |

**Invokable methods:**
- `scanNetworks()` — triggers a Wi-Fi scan on the first detected Wi-Fi device; collects access point SSIDs from `org.freedesktop.NetworkManager.AccessPoint`.
- `connectToNetwork(ssid, password)` — creates a new 802-11-wireless connection profile and activates it.
- `connectToSelectedNetwork(ssid)` — activates an existing saved connection profile.
- `disconnectFromNetwork()` — deactivates the current active connection.

**Active connection watcher:** `watchActiveConnection()` subscribes to `PropertiesChanged` on the active connection path to detect when `State` transitions to `Activated` or `Deactivated`, emitting `connectSuccess` or `connectFailed` accordingly.

---

### USBManager

**File:** `Backend/USBManager.cpp/hpp`
**Context key:** `usbManager`

Detects **USB storage devices** and **MTP devices** (phones connected via USB), mounts them, and scans for playable media files.

| Property | Type | Description |
|---|---|---|
| `connected` | `bool` | Whether a USB drive is currently mounted |
| `scanning` | `bool` | Whether an async file scan is in progress |
| `mountPath` | `QString` | Filesystem path where the drive is mounted |
| `driveName` | `QString` | Friendly name of the drive |
| `audioFiles` | `QStringList` | Absolute paths of all discovered audio files |
| `videoFiles` | `QStringList` | Absolute paths of all discovered video files |

**File detection:** `USBManager` uses two parallel detection paths:
1. **UDisks2** (`org.freedesktop.UDisks2`) — monitors D-Bus `InterfacesAdded` / `InterfacesRemoved` signals for block devices. When a new block device with a filesystem interface appears, `mountDrive()` is called.
2. **GVFS MTP** — scans `/run/user/<uid>/gvfs/` for `mtp:` prefixed directories to detect phones mounted by GVFS.

**Async file scanning:** Once mounted, `scanFiles()` launches a background task via `QtConcurrent::run` and `QFutureWatcher<void>`. The `scanDirectory()` static method recursively walks the mount point and sorts files into audio and video lists based on extension. `AUDIO_EXTENSIONS` and `VIDEO_EXTENSIONS` are defined as static `QStringList` constants in the class.

**Invokable:** `fileName(path)` — returns the base name without extension for display in playlists.

---

### SystemVolumeController

**File:** `Backend/SystemVolumeController.cpp/hpp`
**Context key:** `systemVolume`

Controls the **system audio volume and mute state** by directly interfacing with the **PulseAudio** C API.

| Property | Type | Range | Description |
|---|---|---|---|
| `volume` | `int` | 0–100 | System output volume percentage |
| `muted` | `bool` | — | Whether the default sink is muted |

**Invokable methods:** `setVolume(int)`, `setMuted(bool)`, `toggleMute()`.

**PulseAudio event loop integration:**
A `pa_mainloop` and `pa_context` are created at construction time. A `QTimer` fires every 50 ms and calls `pa_mainloop_iterate()` in non-blocking mode, draining any pending PulseAudio callbacks without blocking Qt's event loop. This bridges PulseAudio's callback-driven model into Qt's timer-driven world.

**Volume update flow:**

```
QML Slider changes value
       │
       ▼
  setVolume(int)
       │
       ▼
  applyVolume()  ──► pa_context_set_sink_volume_by_index()
                                 │
                                 ▼
                      PulseAudio confirms success
                                 │
                                 ▼
                      sinkInfoCallback() fires
                                 │
                                 ▼
                      m_volume updated → volumeChanged() signal
                                 │
                                 ▼
                      QML Slider/display updates
```

**Connection lifecycle:** `contextStateCallback` monitors the PulseAudio connection state. If the connection drops (e.g., PulseAudio restarts), `connectPulse()` is called again after a short delay.

---

### SpeechManager

**File:** `Backend/SpeechManager.cpp/hpp`
**Context key:** `speechManager`

Provides **offline speech-to-text** using the **Vosk** speech recognition library. Audio is captured from the default microphone via `QAudioSource` and fed in chunks to the Vosk recognizer.

| Property | Type | Description |
|---|---|---|
| `listening` | `bool` | `true` while the microphone is active |
| `partialResult` | `QString` | Live partial transcription as the user speaks |

**Invokable methods:**
- `startListening()` — opens the default audio input at 16 kHz mono 16-bit PCM; connects `QIODevice::readyRead` to `onAudioData()`.
- `stopListening()` — closes the audio input; retrieves the final result from Vosk and emits `resultReady(text)`.

**Grammar restriction:** The Vosk recognizer is initialized with a JSON grammar whitelist containing approximately 20 keywords (weather, city names, HVAC terms, media commands). This dramatically reduces false positives and improves recognition speed on embedded hardware by constraining the search space.

**Audio pipeline:**

```
  Microphone (16kHz/16bit/mono)
         │
         ▼
    QAudioSource  ──► QIODevice::readyRead
         │
         ▼
    onAudioData()  ──► vosk_recognizer_accept_waveform()
         │
         ├── partial result → partialResultChanged()
         │
         └── final result   → resultReady(text)
```

**Model:** The Vosk acoustic model is loaded from `../assets/models/vosk` at startup. A small English model (e.g., `vosk-model-small-en-us-0.15`, ~40 MB) is recommended for embedded deployment. For Raspberry Pi, the model path is updated to `/opt/ivi/vosk-model` (see the Yocto section).

---

## QML API Modules

### WeatherAPI

**File:** `API/WeatherAPI.qml`

A `QtObject` that wraps two HTTP requests to the **Open-Meteo** free weather API (no API key required).

**Signals:**

| Signal | Parameters | Description |
|---|---|---|
| `weatherReceived` | `current, daily, hourly, location, population` | Emitted with parsed weather data objects |
| `cityNotFound` | `city: string` | Emitted when the geocoding API returns no results |
| `networkError` | `message: string` | Emitted on HTTP errors |

**Public method:** `fetch(city)` — the single entry point. Triggers `openMeteoWeatherAPI(city)`.

**Request chain:**

1. `GET https://geocoding-api.open-meteo.com/v1/search?name={city}&count=1`
   — resolves city name to latitude, longitude, country, and population.

2. `GET https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&timezone=auto&current=temperature_2m,wind_speed_10m,...&daily=uv_index_max,...&hourly=temperature_2m`
   — fetches current conditions, 7-day daily forecast, and 24-hour hourly data.

Both requests use a shared `fetchData(url, callback)` helper built on `XMLHttpRequest`. The callback pattern allows the two requests to be chained without Promises.

---

### RadioAPI

**File:** `API/RadioAPI.qml`

A `QtObject` that manages station discovery and playback control for the **radio-browser.info** public API.

**Required properties:** `stationsModel` (ListModel), `radioPlayer` (MediaPlayer), `mainWindow` (ApplicationWindow).

**Signals:** `loadingStarted()`, `loadingFinished()`.

**Key methods:**

| Method | Description |
|---|---|
| `fetchStations()` | Clears the model; fetches top-100 stations from radio-browser.info (filtered by search query if set); populates `stationsModel` |
| `playStation(station)` | Updates global media state on `mainWindow`; sets `radioPlayer.source`; calls the radio-browser.info click-counter endpoint; plays the stream |
| `togglePlayPause()` | Checks `radioPlayer.playbackState` and calls `play()` or `pause()` |
| `playNext()` | Finds the current station's index in `stationsModel` and advances by 1 (wraps to 0) |
| `playPrevious()` | Finds the current station's index and steps back by 1 (wraps to last) |

**URL construction:** `buildURL()` builds the query string, appending `&name=encodeURIComponent(query)` when a search query is set.

Each station object stored in `stationsModel` contains: `stationuuid`, `name`, `url`, `favicon`, `codec`, `tags`, `country`, `votes`.

---

## Reusable QML Components

### WindowBar

**File:** `Components/WindowBar.qml`

A shared top bar used on every page of the application. It provides consistent system controls and drag-to-move behavior for the frameless window.

**Required properties:**
- `window` — reference to the containing `Window` (enables `startSystemMove()`).
- `titleName` — string displayed in the center of the bar.
- `showBackButton` — whether the back/home arrow button is shown.
- `color0`, `color1`, `color2` — gradient stops for the horizontal bar gradient (allows each page to theme its bar).

**Optional properties:**
- `brightnessValue` / `volumeValue` / `volumeMuted` — bound to global state for the system-wide controls.

**Signals:** `backRequested()`, `brightnessChanged(value)`, `volumeChanged(value)`, `volumeMuteToggled()`.

**Controls included:**
- **Back / Home button** — amber-bordered square with a home icon; triggers `backRequested()`.
- **Title text** — centered, amber, bold.
- **Brightness popup** — triggered by a sun icon button; shows a vertical `Slider` in a floating `Rectangle`. Value is mapped to `mainWindow.appBrightness` which drives a full-screen semi-transparent black overlay.
- **Volume popup** — triggered by a speaker icon; shows a vertical `Slider` and a mute toggle. Bound to `systemVolume.volume` and `systemVolume.muted`.
- **Close / minimize buttons** (on the right end) — calls `window.close()` and `window.showMinimized()`.

**Drag behavior:** The `MouseArea` covering the bar calls `window.startSystemMove()` on press, allowing the frameless window to be dragged by the title bar on desktop deployments.

**Opacity animation:** On mouse enter the bar fades to full opacity (1.0); on exit it settles at 0.9, giving a subtle depth effect.

---

### MediaCard

**File:** `Components/MediaCard.qml`

A compact now-playing card shown on the launcher while media is active. Displays the current track/station and provides basic transport controls without leaving the home screen.

**Bound to:** `mainWindow.currentMediaTitle`, `currentMediaSubtitle`, `currentMediaFavicon`, `currentMediaType`, `mediaPlaying`.

**Features:**
- Favicon/artwork image with a fallback icon.
- Scrolling marquee for long track names.
- Play/pause button wired to `sharedMediaPlayer`.
- Media type badge indicating whether the source is Radio, Audio, or Video.

---

### CarInfoPopup

**File:** `Components/CarInfoPopup.qml`

A modal overlay popup showing static vehicle information.

**Signal:** `closePopup()`.

**Visual structure:**
- Full-screen semi-transparent backdrop (`rgba(0.02, 0.04, 0.08, 0.85)`).
- Centered card (440×340 px, 24 px radius) with a dark background and a thin amber top-accent bar.
- Close button (`✕`) in the top-right corner with a red hover state.
- Vehicle data rows (label + value) for model, year, VIN, and next service date.
- Animated fade-in via `Behavior on opacity` on `Component.onCompleted`.
- Clicking outside the card emits `closePopup()`.

---

## Design System & UI Conventions

The IVI Dashboard follows a consistent visual language across all pages:

**Color Palette**

| Role | Value | Usage |
|---|---|---|
| Background dark | `#082839` | Gradient start and end stops |
| Background mid | `#10475E` | Gradient center stop |
| Accent amber | `#D08831` | Titles, icons, active controls, accents |
| Accent teal | `#18b78f` | HVAC active states, selected items |
| Text primary | `#ffffff` | Main labels |
| Text secondary | `#8899bb` | Subtitles, metadata |
| Success | `#00ffaa` | Connected / playing indicators |
| Warning | `#D08831` | Buffering indicators |
| Error | `#ff4444` | Error text, close button hover |

**Typography**

All text uses the `"Arial"` font family (or system fallback). Title text in `WindowBar` is 14 pt bold amber. Body text is sized proportionally using `(width + height) / 60` to scale correctly across display resolutions from 800×480 to 1280×800.

**Background Pattern**

Every page uses the same three-stop dark navy gradient as its background. Overlaid on this is a `Canvas` element that draws a dot grid at 40 px spacing in the accent color at 4% opacity. This provides a subtle depth cue without distracting from the UI content.

**Brightness Overlay**

A `Rectangle` with `parent: Overlay.overlay` and `z: 99999` sits above all content including popups. Its `opacity` is `1.0 - mainWindow.appBrightness`. This universal overlay means any page or popup respects the brightness setting without each component needing to implement it individually.

**Animation Conventions**
- Hover scale transitions: `NumberAnimation { duration: 150; easing.type: Easing.OutQuad }`.
- Page transitions: `StackView` default slide animation.
- Floating idle animations on launcher tiles: `SequentialAnimation` looping `NumberAnimation` between ±3–5 px on the Y axis over 4–6 seconds with `Easing.InOutSine`.
- Popup fade-in: `Behavior on opacity { NumberAnimation { duration: 200 } }` with `Component.onCompleted: opacity = 1`.

---
## Demo
> 🎬 **[Watch the full demo video →](https://drive.google.com/file/d/1Oj1QQaDpHGheh9F3O2MxpUNavDnGgvdd/view?usp=drive_link)**

---
## Author

**Ehab Magdy**

---

*IVI Dashboard — Qt 6 · QML · C++ · PulseAudio · BlueZ · NetworkManager · Vosk*
