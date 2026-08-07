#include "inc/detection_instancing.h"

DetectionInstancing::DetectionInstancing(QQuick3DObject *parent)
    : QQuick3DInstancing(parent)
{
}

int DetectionInstancing::labelFilter() const
{
    return labelFilter_;
}

void DetectionInstancing::setLabelFilter(int labelFilter)
{
    if (labelFilter_ == labelFilter)
        return;
    labelFilter_ = labelFilter;
    emit labelFilterChanged();
    rebuild();
}

DetectionModel *DetectionInstancing::model() const
{
    return model_;
}

void DetectionInstancing::setModel(DetectionModel *model)
{
    if (model_ == model)
        return;
    model_ = model;
    emit modelChanged();
    if (model_) {
        connect(model_, &QAbstractItemModel::modelReset,
                this, &DetectionInstancing::rebuild,
                Qt::QueuedConnection);
        connect(model_, &QAbstractItemModel::dataChanged,
                this, &DetectionInstancing::rebuild,
                Qt::QueuedConnection);
    }
    rebuild();
}

bool DetectionInstancing::useInstanceColor() const
{
    return useInstanceColor_;
}

void DetectionInstancing::setUseInstanceColor(bool useInstanceColor)
{
    if (useInstanceColor_ == useInstanceColor)
        return;
    useInstanceColor_ = useInstanceColor;
    emit useInstanceColorChanged();
    rebuild();
}

void DetectionInstancing::rebuild()
{
    QByteArray data;

    if (model_) {
        const QList<DetectionData>& detections = model_->detections();
        for (const DetectionData& d : detections) {
            if (labelFilter_ >= 0 && d.label != labelFilter_)
                continue;

            QVector3D scale = d.scale;
            QQuaternion rotation = d.rotation;

            if (d.label == 0) {
                // pedestrian: plane mesh needs a big upscale
                scale *= 100.0f;
                // walkpose mesh is Blender Z-up (height along +Z, arms +-Y);
                // the pedestrian box rotation maps local Y -> world up.
                // Pre-rotate pitch -90 deg about X: +Z (up) -> +Y (up).
                // Angles (pitch, yaw, roll); keep pitch -90, tune yaw only:
                //   (-90, 0, 0)    faces along motion
                //   (-90, 180, 0)  facing flipped 180 deg
                rotation = d.rotation * QQuaternion::fromEulerAngles(-90, 0, 0);
            } else if (d.label == 2) {
                // tesla mesh: length +-117 (X), width +-51 (Y), up 0..67 (Z), ~cm units
                // measured boxes: x=width, y=height, z=length.
                // Uniform scale by the box HEIGHT so the car fills the box
                // vertically (k = y / 0.6732; 0.6732 = mesh height / 100).
                const float k = d.scale.y() / 0.6732f;
                scale = QVector3D(k*0.8, k, k*1.5);
                // pitch -90 maps Z up -> Y up; yaw -90 turns the car length
                // along the box's width slot (z) which holds the true length
                float yaw = 0.0f;
                if (d.scale.z() > d.scale.x() * 1.1f && d.scale.z() > d.scale.y() * 1.1f)
                    yaw = -90.0f;
                rotation = d.rotation * QQuaternion::fromEulerAngles(-90, yaw, 0);
            }

            const QColor color = useInstanceColor_ ? d.color : Qt::white;
            const InstanceTableEntry entry =
                calculateTableEntryFromQuaternion(d.position, scale, rotation, color);

            data.append(reinterpret_cast<const char*>(&entry), sizeof(entry));
        }
    }

    QMutexLocker locker(&mutex_);
    count_ = data.size() / static_cast<int>(sizeof(InstanceTableEntry));
    buffer_ = data;
    markDirty();
}

QByteArray DetectionInstancing::getInstanceBuffer(int *instanceCount)
{
    QMutexLocker locker(&mutex_);
    *instanceCount = count_;
    return buffer_;
}
