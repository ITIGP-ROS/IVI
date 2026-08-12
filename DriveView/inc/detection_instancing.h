#ifndef DETECTION_INSTANCING_H
#define DETECTION_INSTANCING_H

#include <QQuick3DInstancing>
#include <QMutex>

#include "detection_model.h"

class DetectionInstancing : public QQuick3DInstancing
{
    Q_OBJECT

    Q_PROPERTY(int labelFilter READ labelFilter WRITE setLabelFilter NOTIFY labelFilterChanged FINAL)
    Q_PROPERTY(DetectionModel* model READ model WRITE setModel NOTIFY modelChanged FINAL)
    Q_PROPERTY(bool useInstanceColor READ useInstanceColor WRITE setUseInstanceColor NOTIFY useInstanceColorChanged FINAL)

public:
    explicit DetectionInstancing(QQuick3DObject *parent = nullptr);

    int labelFilter() const;
    void setLabelFilter(int labelFilter);

    DetectionModel *model() const;
    void setModel(DetectionModel *model);

    bool useInstanceColor() const;
    void setUseInstanceColor(bool useInstanceColor);

signals:
    void labelFilterChanged();
    void modelChanged();
    void useInstanceColorChanged();

protected:
    QByteArray getInstanceBuffer(int *instanceCount) override;

private slots:
    void rebuild();

private:
    int labelFilter_ = -1;
    DetectionModel *model_ = nullptr;
    bool useInstanceColor_ = false;

    mutable QMutex mutex_;
    QByteArray buffer_;
    int count_ = 0;
};

#endif // DETECTION_INSTANCING_H
