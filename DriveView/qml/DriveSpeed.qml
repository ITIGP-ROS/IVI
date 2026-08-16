pragma Singleton
import QtQuick

/*
 * The one place that turns the vehicle's real speed into the speed the 3D
 * scene is ANIMATED at. Everything that moves with the car — the scrolling
 * city, the ego car's wheels — pulls its rate from here, so they can never
 * drift out of step with each other.
 *
 * Why a gain exists at all
 * -----------------------
 * The scene is drawn at real-world scale: a 17.5 m road, 40 m towers, a
 * 5 m car, 100 units = 1 m. The vehicle underneath it is not a real car — the
 * Tiva reports 0x200 speed at 1 LSB = 1 m/min, full scale 50 m/min, i.e.
 * 0.833 m/s or a slow walk. Animating a real-scale city at a literal 0.833 m/s
 * puts one building past the camera every 9.6 s and spins the wheels at a
 * quarter turn a second: the world reads as frozen and the car as parked, even
 * at full throttle. This used to look right only because the speed came from a
 * KITTI bag doing 7-14 m/s.
 *
 * So the backdrop is stylised, deliberately: it moves proportionally to the
 * real speed, scaled so that the vehicle's own ceiling looks like the drive the
 * scene was built to depict.
 *
 * What this does NOT touch
 * ------------------------
 * The HUD speed pill (Scene3D.qml) and everything else a driver reads as an
 * instrument stay on the true number in m/min. So do the detections: those are
 * metres in the velo frame, positioned by the lidar, and no gain is applied to
 * them anywhere. This scales scenery only.
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

    /*
     * THE TWO LOOK KNOBS.
     *
     * Each says what its animation should look like at the vehicle's full
     * 50 m/min, and the two are independent on purpose. They are tuned by eye,
     * separately, against the running scene — so speeding the city up must not
     * drag the wheels along with it, or every adjustment to one becomes a
     * re-tune of the other. That coupling is exactly what the first version of
     * this file got wrong.
     */

    // City scroll at full scale, in m/s. The starting point was 7.2 — 720
    // units/s, the rate the band was originally composed at back when it ran on
    // a fixed 13.333 s animation — and this is that 30% faster, which is where
    // it was judged to read as driving rather than drifting. Buildings arrive
    // about one every 0.85 s here.
    readonly property real sceneTopMps: 9.36

    // Ego wheel spin at full scale, in deg/s — 1.92 rev/s.
    //
    // Deliberately a little under a true no-slip roll. The wheel's centre sits
    // ~0.715 m above the road surface, the largest rolling radius this mesh can
    // be read as having (the smallest is 0.39 m, the same wheel unstretched by
    // the 250/137 vertical scale), and even that wants 750 deg/s against a
    // 9.36 m/s ground. This is ~8% under it — what a 0.78 m wheel would turn
    // at. Anything faster looked frantic on a car nominally doing walking pace.
    readonly property real wheelTopDegPerSec: 691.2

    /*
     * The shape both animations share: vehicle speed as a fraction of full
     * scale — 0 at a standstill, 1 at 50 m/min, and over 1 only while the
     * corrupt-frame clamp is doing its job.
     *
     * Linear on purpose: twice the speed on the bus has to look twice as fast,
     * or the backdrop stops meaning anything at all.
     */
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
