#ifndef DETECTION_SMOOTHER_H
#define DETECTION_SMOOTHER_H

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
        QVector3D targetVel;          // low-passed measurement velocity (m/s)
        QVector3D targetPrevPos;      // previous message position
        qint64 targetPrevTimeMs = 0;  // wall time of previous message
        qint64 lastTickMs = 0;        // wall time of previous 60 Hz tick

        // Spawn opacity, delivered to the renderer as the alpha of
        // DetectionData::color. Spawn ONLY — there is no despawn ramp; a track
        // the detector stops reporting is erased outright, so this value only
        // ever climbs.
        float alpha = 0.0f;           // 0 on creation: everything fades in
    };

    void tick();
    QList<DetectionData> buildOutput() const;

    DetectionModel* model_ = nullptr;
    QHash<int, Track> tracks_;
    QMutex mutex_;
    QTimer timer_;
};

#endif // DETECTION_SMOOTHER_H
