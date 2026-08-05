#include "inc/detection_model.h"

// #include "box_transform.h"

DetectionModel::DetectionModel(QObject* parent)
    : QAbstractListModel(parent)
{

}

void DetectionModel::setDetections(
    const QList<DetectionData>& detections)
{
    beginResetModel();

    detections_ = detections;
    m_detectCount = detections_.size();

    endResetModel();

    emit detectCountChanged();
}

const QList<DetectionData>& DetectionModel::detections() const
{
    return detections_;
}

int DetectionModel::rowCount(
    const QModelIndex& parent
    ) const
{
    Q_UNUSED(parent);
    return detections_.size();
}

QVariant DetectionModel::data(
    const QModelIndex& index,
    int role
    ) const
{
    if (!index.isValid())
        return {};

    const auto& d =
        detections_[index.row()];

    switch (role)
    {
    case PositionRole:
        return d.position;

    case ScaleRole:
        return d.scale;

    case RotationRole:
        return QVariant::fromValue(
            d.rotation
            );

    case ColorRole:
        return d.color;

    case LabelRole:
        return d.label;

    case ConfidenceRole:
        return d.confidence;

    }

    return {};
}

QHash<int, QByteArray>
DetectionModel::roleNames() const
{
    return {
        {PositionRole, "position"},
        {ScaleRole, "scale"},
        {RotationRole, "rotation"},
        {ColorRole, "color"},
        {LabelRole, "label"},
        {ConfidenceRole, "confidence"}

    };
}

int DetectionModel::getDetectCount() const
{
    return m_detectCount;
}
