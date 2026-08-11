#ifndef DETECTION_SMOOTHER_H
#define DETECTION_SMOOTHER_H

#include <atomic>

#include <QObject>
#include <QTimer>
#include <QMutex>
#include <QHash>
#include <QVector3D>
#include <QQuaternion>
#include <QColor>

#include "detection_data.h"
#include "detection_model.h"

// Interpolates detection poses between incoming ROS messages so the scene
// updates smoothly instead of stepping at the message rate.
//
// update() is called from the ROS spin thread and only mutates the target
// poses (mutex-protected). A 60 Hz timer (GUI thread) advances each track's
// current pose toward its target and pushes the result into DetectionModel.
class DetectionSmoother : public QObject
{
    Q_OBJECT

public:
    explicit DetectionSmoother(QObject* parent = nullptr);

    void setModel(DetectionModel* model);

    // thread-safe; call from the ROS callback with the raw detections
    void update(const QList<DetectionData>& raw);

    // Ego speed in m/s, from /kitti/oxts/gps/vel. Used only to classify a
    // detection's true direction of travel — never to change how one is drawn.
    // Detections arrive in the ego frame, where an oncoming car and one we are
    // overtaking both fall behind us; adding our own speed back is the only way
    // to tell those apart. Written from the ROS velocity callback and read
    // while smoothing, hence atomic rather than mutex-held.
    void setEgoSpeed(float mps) { egoSpeed_ = mps; }

private:
    struct Track
    {
        int trackId = -1;
        QVector3D currentPos;
        QVector3D targetPos;
        QVector3D currentScale;
        QVector3D targetScale;
        QQuaternion currentRot;
        QQuaternion targetRot;
        QColor color;
        int label = 0;
        float confidence = 0.0f;
        bool untracked = true;   // trackId < 0: pass through, no smoothing;
                                 // new tracks start "untracked" so the first
                                 // sight of an ID snaps instead of flying in
                                 // from the origin

        // predictive-follow state (position only)
        QVector3D targetVel;          // low-passed measurement velocity, in Qt
                                      // units/s (100 units = 1 m), NOT m/s
        QVector3D targetPrevPos;      // previous message position
        qint64 targetPrevTimeMs = 0;  // wall time of previous message
        qint64 lastTickMs = 0;        // wall time of previous 60 Hz tick

        // spawn/despawn opacity, delivered to the renderer as the alpha of
        // DetectionData::color. Tracks used to be erased the instant they
        // went missing, so objects blinked out of existence between frames.
        float alpha = 0.0f;           // 0 on creation: everything fades in
        bool fading = false;          // unseen; ramping out before deletion

        // Dead reckoning once the sensor drops the object: it keeps moving at
        // its last measured velocity, at full opacity, until it is off screen
        // (see kCoastEndZ). Only then does `fading` take over. Mutually
        // exclusive with `fading`; both clear if the track is re-acquired.
        bool coasting = false;
        qint64 coastStartMs = 0;      // wall time coasting began, for the cap
        int hits = 0;                 // measurements received; gates coasting
                                      // so barely-seen tracks cannot leave one

        // Alongside the ego and drawn facing backwards, so withheld. Rides the
        // same opacity ramp as everything else rather than being cut, or it
        // would blink out the moment it crossed the zone edge.
        bool suppressed = false;
    };

    void tick();
    QList<DetectionData> buildOutput() const;

    DetectionModel* model_ = nullptr;
    std::atomic<float> egoSpeed_{0.0f};
    QHash<int, Track> tracks_;
    QMutex mutex_;
    QTimer timer_;
};

#endif // DETECTION_SMOOTHER_H
