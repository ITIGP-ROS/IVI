pragma Singleton
import QtQuick

/*
 * Converts real vehicle speed into the rate the 3D scene animates at, so
 * the scrolling city and ego wheels never drift out of sync.
 *
 * The scene is real-world scale, but the vehicle's own speed (Tiva 0x200,
 * full scale 50 m/min ≈ 0.833 m/s) is too slow to look right 1:1 — this
 * scales the backdrop proportionally to real speed instead.
 *
 * The HUD speed pill and detections stay on the true m/min value; no gain
 * is applied to them.
 */
QtObject {
    // The vehicle's own ceiling, from the DBC: 50 m/min. Same number the HUD
    // bar uses for full scale (Scene3D.qml `topSpeed`), and it belongs to the
    // vehicle rather than the scene — change it here if the Tiva's range does.
    readonly property real vehicleTopMps: 50 / 60          // 0.833 m/s

    // Standstill. The wire resolution is 1 m/min = 0.0167 m/s, so anything
    // under one LSB is a stopped car by definition and the scene freezes.
    readonly property real standstillMps: 0.01

    // Corrupt-frame guard, a little over the vehicle's own 0.833. 0x200 speed
    // is a u16, so a bad frame decodes to 1092 m/s; without this the gain below
    // would turn that into a 1.1-million-units/s strobe across the whole city.
    readonly property real maxVehicleMps: 1.0

    // Two independent look knobs, each tuned by eye at the vehicle's full
    // 50 m/min. Keep them independent — coupling city speed to wheel speed
    // was a past bug in this file.

    // City scroll at full scale, in m/s — tuned by eye to read as driving.
    readonly property real sceneTopMps: 9.36

    // Ego wheel spin at full scale, in deg/s. Deliberately under the true
    // no-slip roll rate (~750 deg/s) — matching it looked frantic at this
    // car's scale.
    readonly property real wheelTopDegPerSec: 691.2

    // Vehicle speed as a fraction of full scale: 0 at standstill, 1 at
    // 50 m/min, and briefly over 1 while the corrupt-frame clamp holds.
    // Linear so double the speed reads as double the animation rate.
    function fraction(mps) {
        if (!isFinite(mps) || mps <= standstillMps)
            return 0
        return Math.min(mps, maxVehicleMps) / vehicleTopMps
    }

    // Vehicle m/s -> the m/s the scenery should move at.
    function sceneMps(mps) {
        return fraction(mps) * sceneTopMps
    }

    // Vehicle m/s -> ego wheel angular velocity in deg/s.
    function wheelDegPerSec(mps) {
        return fraction(mps) * wheelTopDegPerSec
    }
}
