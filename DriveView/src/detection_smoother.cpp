#include "inc/detection_smoother.h"

#include <QtMath>
#include <QSet>
#include <QDateTime>

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

// sanity clamp: real traffic cannot exceed ~40 m/s per message at 10 Hz;
// a larger jump is a tracker re-acquisition, so glide instead of snapping.
constexpr float kMaxSpeedMs = 40.0f;

// a heading change > 120 deg per message would be 1200 deg/s: impossible for
// traffic. Detector yaw has +-pi ambiguity on symmetric boxes, so flip the
// target to the near side instead of letting slerp spin the mesh 180 deg.
constexpr float kFlipThresholdDeg = 120.0f;

// Base for synthetic keys given to untracked detections. Real track ids from
// AB3DMOT are non-negative, so nothing can collide with these.
constexpr int kUntrackedKeyBase = -1000;
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

    for (const DetectionData& d : raw) {
        const int key = (d.trackId < 0)
                            ? (kUntrackedKeyBase - untrackedSeq++)
                            : d.trackId;

        Track& track = tracks_[key];
        track.trackId = d.trackId;
        track.color = d.color;
        track.label = d.label;
        track.confidence = d.confidence;

        if (d.trackId < 0) {
            // untracked stream: pass through instantly, no interpolation
            track.untracked = true;
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
                if (speed > kMaxSpeedMs)
                    rawVel *= kMaxSpeedMs / speed;
                const float aV = 1.0f - qExp(-float(dtMsg) / kTauVelMs);
                track.targetVel += (rawVel - track.targetVel) * aV;
            } else if (dtMsg >= 500) {
                // long gap: stale velocity is worse than none
                track.targetVel = QVector3D();
            }
            track.targetPrevPos = d.position;
            track.targetPrevTimeMs = nowMs;

            // Flip guard: snap the target rotation to the near side so the
            // mesh never 180-spins on symmetric-box yaw ambiguity. Must flip
            // about the box's own up axis, not a world axis, or it turns the
            // box upside down.
            //
            // getAxisAndAngle reports (180, 360] when the quaternion's scalar
            // is negative, so the diff must be sign-normalized (w >= 0) first
            // or the near-side check always rejects the flip.
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

            track.targetPos = d.position;
            track.targetScale = d.scale;
            track.targetRot = targetRot;
        }

        seen.insert(key);
    }

    // Tracks that disappeared (the detector's own tracker holds objects
    // through missed frames, so this only fires on real deletion) drop
    // immediately rather than fading out — a fade left the Tesla mesh's
    // wheels re-sorting through partial alpha and visibly shifting colour
    // while the car sat frozen going translucent.
    //
    // Safe because a re-acquired object comes back under a new id, so this
    // can't be triggered by a one-message dropout.
    for (auto it = tracks_.begin(); it != tracks_.end();) {
        if (seen.contains(it.key()))
            ++it;
        else
            it = tracks_.erase(it);
    }
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

        const float alpha = 1.0f - qExp(-float(dtMs) / kTauPosMs);

        // lead the target along its smoothed velocity to cancel lag; when
        // the target stops, targetVel decays and the correction term pulls
        // the box in without overshoot
        const QVector3D projected = track.targetPos
            + track.targetVel * (kHorizonMs / 1000.0f);

        track.currentPos += (projected - track.currentPos) * alpha;
        track.currentScale += (track.targetScale - track.currentScale) * alpha;
        track.currentRot = QQuaternion::slerp(track.currentRot, track.targetRot, alpha);
    }

    const QList<DetectionData> output = buildOutput();

    // model is only touched from the GUI thread, so unlock before setDetections
    locker.unlock();

    if (model_)
        model_->setDetections(output);
}

void DetectionSmoother::clear()
{
    {
        QMutexLocker locker(&mutex_);
        tracks_.clear();
    }

    // Same rule as tick(): the model belongs to the GUI thread, so it is
    // touched with the mutex released.
    if (model_)
        model_->setDetections({});
}

QList<DetectionData> DetectionSmoother::buildOutput() const
{
    QList<DetectionData> out;
    out.reserve(tracks_.size());

    for (const auto& track : tracks_) {
        DetectionData d;
        d.trackId = track.trackId;
        d.position = track.currentPos;
        d.scale = track.currentScale;
        d.rotation = track.currentRot;
        d.color = track.color;
        d.label = track.label;
        d.confidence = track.confidence;
        out.append(d);
    }

    return out;
}
