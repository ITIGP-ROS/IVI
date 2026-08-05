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
    if (model_)
        connect(model_, &QAbstractItemModel::modelReset,
                this, &DetectionInstancing::rebuild,
                Qt::QueuedConnection);
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
                scale *= 70.0f;
            } else if (d.label == 2) {
                // car: swap scale axes and apply the -90 deg tilt
                // previously done in the QML delegate
                scale = QVector3D(d.scale.y(), d.scale.x(), d.scale.z());
                rotation = d.rotation * QQuaternion::fromEulerAngles(-90, 0, 0);
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
