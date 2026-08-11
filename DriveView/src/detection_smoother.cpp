#include "inc/detection_smoother.h"

#include <QtMath>
#include <QSet>
#include <QDateTime>
#include <QVector2D>

namespace {
constexpr int kTickIntervalMs = 16;

// dt-aware exponential time constants (ms).
// tauPos = 70 ms matches the old fixed kAlpha = 0.2 per 16 ms tick:
//   alpha = 1 - exp(-dt/tau), alpha(16ms) = 1 - exp(-0.23) = 0.205
constexpr float kTauPosMs = 70.0f;
constexpr float kTauVelMs = 150.0f;   // measurement-velocity low-pass

// project the target along its smoothed velocity for this long (ms): at
// constant velocity the lead exactly cancels the exponential lag.
constexpr float kHorizonMs = 70.0f;

// Sanity clamp: real traffic cannot exceed ~40 m/s per message at 10 Hz; a
// larger jump is a tracker re-acquisition, so glide instead of snapping.
//
// Positions are Qt units (100 = 1 m) and so is this. It read 40.0f for a long
// time while claiming to be 40 m/s, which is 0.4 m/s — every moving object had
// its velocity crushed by ~97%, so the lead term below was worth about 3 cm
// instead of a metre, and nothing downstream could use targetVel for anything.
constexpr float kMaxSpeedUnits = 4000.0f;

// a heading change > 120 deg per message would be 1200 deg/s: impossible for
// traffic. Detector yaw has +-pi ambiguity on symmetric boxes, so flip the
// target to the near side instead of letting slerp spin the mesh 180 deg.
constexpr float kFlipThresholdDeg = 120.0f;

// Spawn/despawn opacity ramp, asymmetric on purpose.
//
// Fading in is free to be leisurely — a car arriving at partial alpha is
// blending over the road behind it, which looks like a car appearing.
//
// Fading out is not. The mesh is concave, so while it is semi-transparent you
// see its own far side through it and it blends toward the dark background;
// what that reads as is the car changing colour just before it vanishes, not
// as it dissolving. Nothing tints it — the instance RGB is white throughout —
// but a long ramp gives the eye time to read the dimming as a colour shift.
// ~90 ms out (vs ~350 ms before) is short enough to register as "gone" rather
// than "went grey".
constexpr float kTauAlphaInMs  = 90.0f;
constexpr float kTauAlphaOutMs = 40.0f;

// Below this a fading track is close enough to invisible to drop, and dropping
// it early is what keeps the see-through tail off screen. Deliberately well
// above zero: an exponential never reaches it, and the last stretch is all
// ghost. At 12% over a dark road the cut is not perceptible.
constexpr float kAlphaGone = 0.12f;

// ---- Coasting: dead reckoning past the end of the sensor -----------------
//
// The lidar's useful field of view ends at the ego car, so an oncoming vehicle
// is dropped the instant it draws level with us. That is the correct detection
// output, and it looks wrong: the car stops dead alongside and evaporates,
// when what you were just watching was something closing at 15 m/s.
//
// So a track that disappears keeps travelling on its own last measured
// velocity until it is off screen, and only fades once it is out of sight.
// Nothing is invented — it is the object's real speed and heading, held
// constant. The moment the detector sees it again, the measurements take over.

// Z at which a coasting track gives up and starts fading. +Z is behind the ego
// (ROS forward +X maps to Qt -Z), so this is 14 m back — past both default
// cameras. The chase view's lower frustum edge crosses road level at z~680
// (camera at z=771, y=919, pitched -50 deg, 70 deg FOV) and the top view sees
// to z~1220 (1600 up, 70 deg FOV, road at y=-140). Fading beyond both is the
// entire point: the object leaves the screen at full opacity, like a real one.
constexpr float kCoastEndZ = 1400.0f;

// Do not coast something that was not really moving. A track that vanishes
// while pacing us is not driving away, and sliding it across the scene would
// invent motion that never happened.
//
// Deliberately low. It was 2 m/s, which covered oncoming traffic but excluded
// the case this is most wanted for: a car we overtake pulls away at the
// *difference* between the two speeds, which is small. Measured on drive 0004,
// track 55660 fell back at 0.93 m/s over ten seconds — real, steady, and well
// under the old gate, so it vanished at the bumper like everything else.
constexpr float kCoastMinSpeed = 60.0f;    // units/s == 0.6 m/s

// Hard stop, so a bad velocity estimate can never leave a ghost parked in the
// scene. Raised alongside the speed gate: at 0.93 m/s a car needs ~8.5 s to
// clear the chase view's lower edge, and cutting it off at 3 s would drop it
// on screen — the exact pop this whole mechanism exists to avoid. Fast traffic
// still crosses kCoastEndZ in well under a second and never reaches this.
constexpr qint64 kMaxCoastMs = 10000;

// A coasting track is a guess about something the sensor cannot see any more.
// The moment a real detection shows up where that guess is, the guess is
// redundant — and keeping both is what puts two or three copies of the same
// car on screen at once. The tracker upstream reassigns ids fairly often
// (it drops an object and re-acquires it under a new one), which lands the
// same physical car in two Track entries: the old id coasting, the new id
// spawning right on top of it. Ghost-vs-live gating is what resolves that.
//
// Ground-plane distance only — height is meaningless for this, and two boxes
// for one car differ mainly along the road. 3 m is wide enough to cover the
// re-acquisition offset and the drift the ghost has accumulated, tight enough
// that a car in the next lane does not swallow a legitimate ghost. Only ghosts
// are ever suppressed; a live detection is never touched.
constexpr float kGhostMergeDist = 300.0f;   // units == 3 m

// Do not coast a track we barely saw. Fewer than this many measurements and
// the velocity is still mostly the low-pass's initial zero, so the extrapolation
// is guesswork — and short-lived false positives, which are exactly the tracks
// that die young, are the ones that would leave the most obviously wrong ghosts.
constexpr int kMinHitsToCoast = 3;

// Draw nothing until a track has been measured this many times. A detection
// that shows up for one message and is gone by the next is a false positive,
// and drawing it is what makes a car flash into existence beside the ego with
// nothing leading up to it. Costs one message of latency (~100 ms at 10 Hz) on
// genuinely new objects, which is invisible next to a spurious car appearing.
constexpr int kMinHitsToShow = 2;

// Two boxes closer together than this fraction of their combined ground radius
// are treated as one object. Two real vehicles cannot share a footprint, so an
// overlap means the detector emitted a second box for one car (or the tracker
// carried two ids for it) — which is what reads as a car doubled, or as one
// "appearing" alongside another already there.
//
// Scaled by the boxes rather than a flat distance so it stays right for a
// pedestrian and a lorry alike. For two cars it works out at ~2.4 m, comfortably
// inside the ~3.5 m spacing of adjacent lanes, so traffic in the next lane is
// never suppressed however close it passes.
constexpr float kOverlapFraction = 0.5f;

// Base for synthetic keys given to untracked detections. Real track ids from
// AB3DMOT are non-negative, so nothing can collide with these.
constexpr int kUntrackedKeyBase = -1000;

// ---- The backwards car alongside the ego ---------------------------------
//
// The detector cannot tell the front of a symmetric box from its back, so the
// yaw it reports carries a 180 deg ambiguity and picks a side arbitrarily.
// Measured on drive 0004, every car beside the ego reports its box axis at
// ~+-90 deg and the sign varies between tracks (55748 held +89.7 while 56618
// held -88.4). The renderer corrects the axis swap with a fixed -90 deg yaw, so
// a box reported at +90 comes out facing forward and one reported at -90 comes
// out facing backwards — a car driving the same way as us, drawn against the
// traffic, right alongside where it is most obvious.
//
// Such a box is not turned around to fit. Rotating it would be inventing an
// orientation the sensor never reported, and it would look identical to a real
// oncoming car, which is a worse lie on a driving display than an absent box.
// It is simply not drawn while it is beside us.
//
// The gate is deliberately narrow: alongside AND backwards. Backwards alone
// would take every oncoming car on the road, since for those it is correct.
// Alongside alone would take the adjacent-lane traffic that renders fine.

// Half-extents of the alongside zone, in Qt units (100 = 1 m). 6 m either side
// reaches across the adjacent lane on both sides without touching the one
// beyond it; 6 m fore and aft covers a car level with us plus its own length.
// The measured offender sat at x=-290, z=-50 — well inside both.
constexpr float kBesideHalfX = 600.0f;
constexpr float kBesideHalfZ = 600.0f;

// Below this the object's own direction of travel is not established well
// enough to contradict anything, so the suppression falls back to position and
// drawn heading alone.
constexpr int kMinHitsForTravelDir = 2;

// ---- Scene geometry ------------------------------------------------------
//
// Mirrors of two numbers the 3D scene is built from. They live in QML
// (Environment3D.qml: roadHalfWidth, cityInset) where C++ cannot read them, so
// they are duplicated. Widen the road again and both of these move with it.
constexpr float kRoadHalfWidth = 893.0f;   // road edge, 8.9 m from centre
constexpr float kCityInset     = 2100.0f;  // nearest building facade

// Pedestrians are drawn only on the pavement: the band between the road edge
// and the buildings. The detector puts people in the carriageway and inside
// the facades often enough to be distracting, and neither is anywhere a person
// can actually be in this scene — one is under the traffic, the other is inside
// a wall. What lies between the two is a 12.5 m strip that reads as pavement,
// which is where the real ones are anyway.
constexpr int kLabelPedestrian = 0;

// Half the diagonal of a box's ground footprint, in Qt units. Box scale is the
// #Cube multiplier — x = length, y = height, z = width — and the primitive is
// 100 units across, so a scale of 4.5 is a 4.5 m side.
float groundRadius(const QVector3D& scale)
{
    const float len = scale.x() * 100.0f;
    const float wid = scale.z() * 100.0f;
    return 0.5f * qSqrt(len * len + wid * wid);
}
}

DetectionSmoother::DetectionSmoother(QObject* parent)
    : QObject(parent)
{
    timer_.setInterval(kTickIntervalMs);
    connect(&timer_, &QTimer::timeout,
            this, &DetectionSmoother::tick);
    // Started here on the GUI thread; never restarted from the ROS thread.
    // tick() just no-ops while there are no tracks, so an always-on timer
    // is cheaper and safer than cross-thread start/stop.
    timer_.start();
}

void DetectionSmoother::setModel(DetectionModel* model)
{
    model_ = model;
}

void DetectionSmoother::update(const QList<DetectionData>& raw)
{
    QMutexLocker locker(&mutex_);

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();

    QSet<int> seen;

    // Untracked detections all arrive carrying the same trackId (-1 by the
    // message's own definition). Keying the hash on that value collapsed
    // every one of them into a single Track, so N untracked objects rendered
    // as exactly 1 — and the same would happen to the whole scene if the
    // tracker were ever disabled and left track_id at its default. They carry
    // no identity to preserve and pass straight through without smoothing, so
    // a per-message synthetic key is all they need to stay distinct.
    int untrackedSeq = 0;

    // Every detection actually measured this message, for the ghost gating
    // below. Untracked ones count too: an object the tracker lost the id for
    // but still reports is the very case that produces a duplicate.
    struct Live { int key; int label; QVector3D pos; };
    QList<Live> live;
    live.reserve(raw.size());

    for (const DetectionData& d : raw) {
        const int key = (d.trackId < 0)
                            ? (kUntrackedKeyBase - untrackedSeq++)
                            : d.trackId;

        Track& track = tracks_[key];
        // A track that went missing and came back keeps its identity and
        // simply stops leaving — whether it was coasting on dead reckoning or
        // already fading. Measurements resume from wherever it coasted to, and
        // the existing exponential follow absorbs the correction.
        track.fading = false;
        track.coasting = false;
        track.trackId = d.trackId;
        track.color = d.color;
        track.label = d.label;
        track.confidence = d.confidence;

        if (d.trackId < 0) {
            // untracked stream: pass through instantly, no interpolation
            track.untracked = true;
            // tick() skips untracked tracks entirely, so their opacity would
            // never ramp; they are simply always solid.
            track.alpha = 1.0f;
            track.currentPos = d.position;
            track.targetPos = d.position;
            track.currentScale = d.scale;
            track.targetScale = d.scale;
            track.currentRot = d.rotation;
            track.targetRot = d.rotation;
            track.targetVel = QVector3D();
        } else if (track.untracked) {
            // first frame with an ID: snap to the measurement
            track.untracked = false;
            track.currentPos = d.position;
            track.targetPos = d.position;
            track.currentScale = d.scale;
            track.targetScale = d.scale;
            track.currentRot = d.rotation;
            track.targetRot = d.rotation;
            track.targetVel = QVector3D();
            track.targetPrevPos = d.position;
            track.targetPrevTimeMs = nowMs;
        } else {
            // raw measurement velocity, low-passed into targetVel
            const qint64 dtMsg = nowMs - track.targetPrevTimeMs;
            if (dtMsg > 1 && dtMsg < 500) {
                QVector3D rawVel = (d.position - track.targetPrevPos)
                                   * (1000.0f / dtMsg);
                const float speed = rawVel.length();
                if (speed > kMaxSpeedUnits)
                    rawVel *= kMaxSpeedUnits / speed;
                const float aV = 1.0f - qExp(-float(dtMsg) / kTauVelMs);
                track.targetVel += (rawVel - track.targetVel) * aV;
            } else if (dtMsg >= 500) {
                // long gap: stale velocity is worse than none
                track.targetVel = QVector3D();
            }
            track.targetPrevPos = d.position;
            track.targetPrevTimeMs = nowMs;

            // flip guard: snap the target rotation to the near side so the
            // mesh never 180-spins on symmetric-box yaw ambiguity.
            // IMPORTANT: rotations here live in the Qt3D frame where UP = Y,
            // so the flip must be about the box's OWN up axis (which stays
            // fixed under the flip); a 180 deg rotation about any horizontal
            // world axis would turn the box upside down.
            // NOTE: QQuaternion::getAxisAndAngle reports the angle in the
            // range (180, 360] whenever the quaternion's scalar part is
            // negative (it does not normalize to the shortest rotation), so
            // the diff quaternion must be sign-normalized (w >= 0) first,
            // otherwise the near-side flip is always rejected and the box
            // slerps through a full 180 deg spin on yaw sign flips.
            QQuaternion targetRot = d.rotation;
            QQuaternion diff = track.currentRot.conjugated() * targetRot;
            if (diff.scalar() < 0.0f)
                diff = -diff;   // same rotation, shortest angle now
            QVector3D axis;
            float angleDeg = 0.0f;
            diff.getAxisAndAngle(&axis, &angleDeg);
            if (angleDeg > kFlipThresholdDeg) {
                const QVector3D up = (targetRot * QVector3D(0.0f, 1.0f, 0.0f))
                                         .normalized();
                const QQuaternion flipped =
                    QQuaternion::fromAxisAndAngle(up, 180.0f) * targetRot;
                // only accept the flip if it actually brings the target nearer
                QQuaternion diffFlipped = track.currentRot.conjugated() * flipped;
                if (diffFlipped.scalar() < 0.0f)
                    diffFlipped = -diffFlipped;
                QVector3D axis2;
                float flippedDeg = 0.0f;
                diffFlipped.getAxisAndAngle(&axis2, &flippedDeg);
                if (flippedDeg < angleDeg)
                    targetRot = flipped;
            }

            // Decide whether to draw this box at all. The orientation itself is
            // left exactly as the detector reported it — nothing is ever turned
            // to fit — this only decides whether to show it. See kBesideHalfX.
            //
            // Which local axis carries the box's length depends on how the
            // detector filled in the corners, so choose between them the way
            // the renderer does: by comparing the two ground dimensions.
            const bool lengthIsZ = d.scale.z() > d.scale.x() * 1.1f;
            const QVector3D lengthLocal = lengthIsZ ? QVector3D(0, 0, 1)
                                                    : QVector3D(1, 0, 0);
            // +Z is behind us, so a length axis with a positive Z component is
            // a box drawn nose-to-tail against our own direction of travel.
            const bool facingBackwards = (targetRot * lengthLocal).z() > 0.0f;
            const bool alongside = qAbs(d.position.x()) < kBesideHalfX
                                   && qAbs(d.position.z()) < kBesideHalfZ;

            // The third condition, and the one that matters: is the box drawn
            // backwards while the object is actually going our way? That is a
            // contradiction, and it is the case worth hiding.
            //
            // A genuinely oncoming car is also drawn backwards — correctly —
            // and must be left alone. Without this it got suppressed for the
            // half second it spent alongside and then returned once it was
            // behind, which read as cars blinking out and back on the way past.
            //
            // Ego frame -> world: something standing still appears to recede at
            // exactly our own speed, so worldVz = relativeVz - egoSpeed. We
            // travel toward -Z, so our way is negative.
            const float worldVz = track.targetVel.z()
                                  - egoSpeed_.load() * 100.0f;
            const bool goingOurWay = track.hits < kMinHitsForTravelDir
                                         ? true          // not yet known
                                         : worldVz < 0.0f;

            track.suppressed = alongside && facingBackwards && goingOurWay;

            track.targetPos = d.position;
            track.targetScale = d.scale;
            track.targetRot = targetRot;
        }

        // Pavement rule for people, checked for every detection including the
        // untracked ones (which skip the branches above entirely, so they would
        // otherwise never be filtered). Purely positional — a person in the
        // carriageway or standing inside a building facade is not somewhere a
        // person can be, whatever the box says.
        if (d.label == kLabelPedestrian) {
            const float lat = qAbs(d.position.x());
            track.suppressed = lat < kRoadHalfWidth || lat > kCityInset;
        }

        track.hits++;
        seen.insert(key);
        live.append({key, d.label, d.position});
    }

    // Live duplicate suppression, before anything else looks at the set.
    // Overlapping same-label boxes are one object counted twice; the weaker
    // one goes. Only ever removes a box that overlaps another — an isolated
    // detection, however unexpected, is always kept.
    QSet<int> dropped;
    for (int i = 0; i < live.size(); ++i) {
        for (int j = i + 1; j < live.size(); ++j) {
            if (live[i].label != live[j].label)
                continue;
            if (dropped.contains(live[i].key) || dropped.contains(live[j].key))
                continue;

            const auto a = tracks_.constFind(live[i].key);
            const auto b = tracks_.constFind(live[j].key);
            if (a == tracks_.constEnd() || b == tracks_.constEnd())
                continue;

            const QVector3D delta = live[i].pos - live[j].pos;
            const float gap = QVector2D(delta.x(), delta.z()).length();
            const float limit = kOverlapFraction * (groundRadius(a->targetScale)
                                                    + groundRadius(b->targetScale));
            if (gap >= limit)
                continue;

            // Keep whichever is better established — more measurements first,
            // confidence to break a tie. Discarding the newcomer is also what
            // stops the duplicate popping into existence next to the original.
            const bool keepA = (a->hits != b->hits)
                                   ? (a->hits > b->hits)
                                   : (a->confidence >= b->confidence);
            dropped.insert(keepA ? live[j].key : live[i].key);
        }
    }
    for (int key : dropped) {
        tracks_.remove(key);
        seen.remove(key);
    }

    // Tracks that disappeared (the detector-side tracker already holds objects
    // through missed frames, so this only fires on real deletion).
    //
    // Tracked objects are marked for a fade rather than erased — deleting them
    // here made them blink out between two frames, which reads as a glitch
    // rather than as an object leaving. tick() removes them once invisible.
    // Untracked ones go immediately: their synthetic key is regenerated every
    // message, so a "missing" one is an artefact of renumbering, not an object
    // that actually left, and fading it would flicker.
    for (auto it = tracks_.begin(); it != tracks_.end();) {
        if (seen.contains(it.key())) {
            ++it;
        } else if (it->untracked) {
            it = tracks_.erase(it);
        } else if (it->coasting || it->fading) {
            // Already on its way out; tick() owns it from here. Deciding again
            // on every message would keep resetting coastStartMs, and the
            // coast timeout would never fire.
            ++it;
        } else {
            // Coast only what was genuinely driving away from us. Everything
            // else fades where it stands: a near-stationary track that
            // vanished was a dropped detection rather than a departure, and
            // one lost while heading deeper into the scene would have to
            // travel *towards* the camera to leave — a ghost moving into the
            // view is far more noticeable than one leaving it.
            const QVector3D v = it->targetVel;
            if (it->hits >= kMinHitsToCoast
                && v.z() > 0.0f && v.length() >= kCoastMinSpeed
                && it->currentPos.z() < kCoastEndZ) {
                it->coasting = true;
                it->coastStartMs = nowMs;
            } else {
                it->fading = true;
            }
            ++it;
        }
    }

    // Ghost gating. A coasting track standing where a real detection has just
    // been measured is the same object counted twice — almost always because
    // the tracker retired one id and re-acquired the car under another — so
    // the extrapolated copy goes and the measured one stays.
    //
    // Runs after the loop above so a track that only started coasting on this
    // message is gated immediately, before it can ever be drawn beside its own
    // replacement. Same label required: a pedestrian walking past the spot a
    // car vanished from says nothing about the car.
    for (auto it = tracks_.begin(); it != tracks_.end();) {
        if (!it->coasting) {
            ++it;
            continue;
        }

        // Not an int sentinel: untracked detections are keyed on negative
        // synthetic ids, so any "not found" value in int range is a key that
        // can legitimately occur.
        bool takenOver = false;
        int takenOverBy = 0;
        for (const Live& l : live) {
            if (l.label != it->label)
                continue;
            const QVector3D delta = l.pos - it->currentPos;
            // ground plane only: two boxes for one car differ along the road,
            // and box-centre height varies enough to poison a 3D distance
            if (QVector2D(delta.x(), delta.z()).length() < kGhostMergeDist) {
                takenOver = true;
                takenOverBy = l.key;
                break;
            }
        }

        if (!takenOver) {
            ++it;
            continue;
        }

        // Hand the ghost's history to the detection replacing it. It is the
        // same physical object under a new id, so the replacement inherits
        // rather than starting from nothing.
        //
        // Both halves matter. Without the alpha the swap costs a visible dip,
        // the ghost leaving at full opacity while its replacement ramps up
        // from zero. Without the hit count it is worse: the replacement counts
        // as tentative and buildOutput withholds it altogether, so the car
        // vanishes for a message and then returns — which is the blink on cars
        // going past, not a detection dropout at all.
        const auto liveIt = tracks_.find(takenOverBy);
        if (liveIt != tracks_.end()) {
            liveIt->alpha = qMax(liveIt->alpha, it->alpha);
            liveIt->hits  = qMax(liveIt->hits,  it->hits);
        }
        it = tracks_.erase(it);
    }

    // Ghost against ghost. The pass above only ever compares a coasting track
    // with something measured this message, so two ghosts of the same car —
    // which is what id churn during a handover leaves behind, one coasting
    // copy per retired id — never met and both kept coasting side by side.
    // Rare, but it is the overlap that survives everything else.
    QList<int> ghosts;
    for (auto it = tracks_.begin(); it != tracks_.end(); ++it)
        if (it->coasting)
            ghosts.append(it.key());

    QSet<int> merged;
    for (int i = 0; i < ghosts.size(); ++i) {
        for (int j = i + 1; j < ghosts.size(); ++j) {
            if (merged.contains(ghosts[i]) || merged.contains(ghosts[j]))
                continue;
            const auto a = tracks_.constFind(ghosts[i]);
            const auto b = tracks_.constFind(ghosts[j]);
            if (a == tracks_.constEnd() || b == tracks_.constEnd()
                || a->label != b->label)
                continue;

            const QVector3D delta = a->currentPos - b->currentPos;
            if (QVector2D(delta.x(), delta.z()).length() >= kGhostMergeDist)
                continue;

            // Keep the better-established one, exactly as for live boxes.
            const bool keepA = (a->hits != b->hits) ? (a->hits > b->hits)
                                                    : (a->confidence >= b->confidence);
            merged.insert(keepA ? ghosts[j] : ghosts[i]);
        }
    }
    for (int key : merged)
        tracks_.remove(key);
}

void DetectionSmoother::tick()
{
    QMutexLocker locker(&mutex_);

    if (tracks_.isEmpty())
        return;

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();

    for (auto& track : tracks_) {
        if (track.untracked)
            continue;

        // dt-aware alpha: identical motion at any frame rate
        qint64 dtMs = nowMs - track.lastTickMs;
        if (dtMs < 1)
            dtMs = 1;
        else if (dtMs > 100)
            dtMs = 100;
        track.lastTickMs = nowMs;

        // Dead reckoning. targetPos is frozen the instant the measurements
        // stop, so on its own the follow below converges on a point one lead
        // length ahead of where the track died and parks there — which is the
        // stop-dead-then-dissolve this exists to remove. Pushing the target
        // along at the last measured velocity instead means every bit of the
        // existing smoothing keeps working unchanged, and the object simply
        // carries on at the speed it was already doing.
        //
        // Constant velocity, not decaying: traffic passing you does not slow
        // down as it goes, and a decay would read as the car braking.
        if (track.coasting) {
            // Along the road only. The lateral part of a dead-reckoned velocity
            // is mostly estimate noise, and integrating it for several seconds
            // walked cars sideways out of their lane and off the tarmac —
            // motion the object never had. A vehicle leaving the sensor is
            // going straight down the road, so that is all it is given.
            track.targetPos.setZ(track.targetPos.z()
                                 + track.targetVel.z() * (float(dtMs) / 1000.0f));

            if (track.currentPos.z() > kCoastEndZ
                || nowMs - track.coastStartMs > kMaxCoastMs
                // Backstop for one that was already off the tarmac when the
                // sensor dropped it: extrapolating a car through the pavement
                // looks worse than letting it go.
                || qAbs(track.currentPos.x()) > kRoadHalfWidth) {
                track.coasting = false;
                track.fading = true;
            }
        }

        const float alpha = 1.0f - qExp(-float(dtMs) / kTauPosMs);

        // lead the target along its smoothed velocity to cancel lag; when
        // the target stops, targetVel decays and the correction term pulls
        // the box in without overshoot
        const QVector3D projected = track.targetPos
            + track.targetVel * (kHorizonMs / 1000.0f);

        track.currentPos += (projected - track.currentPos) * alpha;
        track.currentScale += (track.targetScale - track.currentScale) * alpha;
        track.currentRot = QQuaternion::slerp(track.currentRot, track.targetRot, alpha);

        // Opacity ramp. Coasting tracks are deliberately not fading, so they
        // stay at full alpha the whole way out and only start dropping once
        // they are past kCoastEndZ and off screen.
        // A tentative track is not drawn yet (see buildOutput), so it is held
        // at zero rather than left to ramp. Otherwise it spends its whole
        // fade-in invisible and then appears at two-thirds brightness the
        // instant it is confirmed, which is the pop the confirmation exists
        // to remove.
        const bool tentative = !track.untracked && track.hits < kMinHitsToShow;
        // Suppressed rides the ramp rather than being cut, so a car crossing
        // into the alongside zone dissolves over ~40 ms instead of blinking out
        // at the boundary — and comes back the same way if it leaves again.
        const bool hidden = track.fading || tentative || track.suppressed;
        const float tauFade = hidden ? kTauAlphaOutMs : kTauAlphaInMs;
        const float aFade = 1.0f - qExp(-float(dtMs) / tauFade);
        const float targetAlpha = hidden ? 0.0f : 1.0f;
        track.alpha += (targetAlpha - track.alpha) * aFade;
    }

    // Reap tracks that have finished fading out. An exponential never quite
    // reaches zero, so the threshold is what actually ends them.
    for (auto it = tracks_.begin(); it != tracks_.end();) {
        if (it->fading && it->alpha < kAlphaGone)
            it = tracks_.erase(it);
        else
            ++it;
    }

    const QList<DetectionData> output = buildOutput();

    // model is only touched from the GUI thread, so unlock before setDetections
    locker.unlock();

    if (model_)
        model_->setDetections(output);
}

QList<DetectionData> DetectionSmoother::buildOutput() const
{
    QList<DetectionData> out;
    out.reserve(tracks_.size());

    for (const auto& track : tracks_) {
        // Tentative tracks are withheld until confirmed by a second
        // measurement. Untracked detections are exempt: their key is
        // regenerated every message, so they can never accumulate hits and
        // gating them would hide the whole class.
        if (!track.untracked && track.hits < kMinHitsToShow)
            continue;

        // Suppressed boxes leave the output entirely rather than being shipped
        // fully transparent every frame, which keeps the HUD's detection count
        // honest about what is on screen. Untracked ones are cut outright:
        // tick() skips them, so they have no opacity ramp to ride out.
        if (track.suppressed && (track.untracked || track.alpha < kAlphaGone))
            continue;

        DetectionData d;
        d.trackId = track.trackId;
        d.position = track.currentPos;
        d.scale = track.currentScale;
        d.rotation = track.currentRot;
        // Opacity travels as the alpha of the colour: DetectionInstancing
        // passes it into the instance table whether or not the class tint
        // is enabled, so a fade costs no extra plumbing.
        d.color = track.color;
        d.color.setAlphaF(qBound(0.0f, track.alpha, 1.0f));
        d.label = track.label;
        d.confidence = track.confidence;
        out.append(d);
    }

    return out;
}
