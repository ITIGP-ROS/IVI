#ifndef DETECTION_MODEL_H
#define DETECTION_MODEL_H

#include <QObject>
#include <QAbstractListModel>
#include "detection_data.h"

class DetectionModel : public QAbstractListModel
{
    Q_OBJECT

        Q_PROPERTY(int detectCount READ getDetectCount NOTIFY detectCountChanged)

public:



    enum Roles
    {
        PositionRole = Qt::UserRole + 1,
        ScaleRole,
        RotationRole,
        ColorRole,
        LabelRole,
        ConfidenceRole
    };

    explicit DetectionModel(QObject* parent = nullptr);

    void setDetections(
        const QList<DetectionData>& detections);

    const QList<DetectionData>& detections() const;

    int rowCount(
        const QModelIndex& parent = QModelIndex()
        ) const override;

    QVariant data(
        const QModelIndex& index,
        int role
        ) const override;

    QHash<int, QByteArray>
    roleNames() const override;



    int getDetectCount() const;

signals:
    void detectCountChanged();

private:

    QList<DetectionData> detections_;
    int m_detectCount;
};

#endif // DETECTION_MODEL_H
