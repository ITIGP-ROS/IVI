#ifndef BOX_TRANSFORM_H
#define BOX_TRANSFORM_H

#include <QVector3D>
#include <QQuaternion>

struct BoxTransform
{
    QVector3D position;
    QVector3D scale;
    QQuaternion rotation;
};
BoxTransform computeBoxTransform(
    const QVector3D corners[8]);

#endif // BOX_TRANSFORM_H
