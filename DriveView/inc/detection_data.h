#ifndef DETECTION_DATA_H
#define DETECTION_DATA_H


#include <QVector3D>
#include <QQuaternion>
#include <QColor>

struct DetectionData
{
    QVector3D position;
    QVector3D scale;
    QQuaternion rotation;

    QColor color;

    int label;
    float confidence;
};

#endif // DETECTION_DATA_H
