#include "inc/box_transform.h"
#include <QMatrix3x3>

static float dist(const QVector3D& a, const QVector3D& b)
{
    return (b - a).length();
}

// ROS (velo_link): X=forward, Y=left, Z=up  → right-handed
// Qt3D:            X=right,   Y=up,   Z=back → left-handed
//
//  ROS +X  →  Qt3D -Z   (forward  → into screen)
//  ROS +Y  →  Qt3D -X   (left     → screen left)
//  ROS +Z  →  Qt3D +Y   (up       → up)
static QVector3D rosToQt(const QVector3D& v)
{
    return QVector3D(-v.y(), v.z(), -v.x());
}

BoxTransform computeBoxTransform(const QVector3D corners[8])
{
    BoxTransform t;

    // Convert & scale all corners first (metres → Qt units)
    QVector3D c[8];
    for (int i = 0; i < 8; i++)
        c[i] = rosToQt(corners[i]) * 100.0f;

    // -------------------------------------------------------
    // From your diagram:
    //   0→4 = ROS X axis (length / forward)
    //   0→3 = ROS Y axis (width  / lateral)
    //   0→1 = ROS Z axis (height / up)
    // After rosToQt these become Qt3D axes correctly.
    // -------------------------------------------------------
    QVector3D axisL = (c[4] - c[0]).normalized();   // length axis
    QVector3D axisW = (c[3] - c[0]).normalized();   // width axis
    QVector3D axisH = (c[1] - c[0]).normalized();   // height axis

    float sL = dist(c[0], c[4]);   // length
    float sW = dist(c[0], c[3]);   // width
    float sH = dist(c[0], c[1]);   // height

    // Center = midpoint of diagonal opposite corners 0 ↔ 6
    t.position = (c[0] + c[6]) * 0.5f;

    // #Cube primitive = 100×100×100 Qt units
    // Map: length→X, width→Z, height→Y  (Qt3D convention)
    t.scale = QVector3D(sL / 100.0f,   // Qt X = ROS X (length)
                        sH / 100.0f,   // Qt Y = ROS Z (height)
                        sW / 100.0f);  // Qt Z = ROS Y (width)

    // Build rotation: cols = (axisL, axisH, axisW) in Qt3D space
    QVector3D col0 = axisL;
    QVector3D col1 = axisH;
    QVector3D col2 = QVector3D::crossProduct(col0, col1).normalized();
    col1 = QVector3D::crossProduct(col2, col0).normalized(); // re-orthogonalise

    QMatrix3x3 m;
    m(0,0)=col0.x(); m(0,1)=col1.x(); m(0,2)=col2.x();
    m(1,0)=col0.y(); m(1,1)=col1.y(); m(1,2)=col2.y();
    m(2,0)=col0.z(); m(2,1)=col1.z(); m(2,2)=col2.z();

    t.rotation = QQuaternion::fromRotationMatrix(m);
    return t;
}
