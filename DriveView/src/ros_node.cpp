#include "inc/ros_node.h"
#include <sensor_msgs/point_cloud2_iterator.hpp>
#include <cmath>
// #include <algorithm>
#include <QDebug>

#include "inc/box_transform.h"

namespace {
// Per-class confidence gate, indexed by the message's label field.
// Vulnerable road users are held to a higher bar than cars: a false-positive
// pedestrian or cyclist box is far more distracting on screen than a missed
// low-confidence one, and the detector is noisiest on exactly those classes.
constexpr float kConfThreshold[] = {
    0.7f,   // 0 = pedestrian
    0.7f,   // 1 = cyclist
    0.5f,   // 2 = car
};
constexpr int kConfThresholdCount =
    int(sizeof(kConfThreshold) / sizeof(kConfThreshold[0]));

// Anything the detector labels outside the known set keeps the old gate.
constexpr float kConfThresholdDefault = 0.5f;

float confThresholdFor(int label)
{
    return (label >= 0 && label < kConfThresholdCount)
               ? kConfThreshold[label]
               : kConfThresholdDefault;
}
}

RosSpinThread::RosSpinThread(std::shared_ptr<rclcpp::Node> node, QObject* parent)
    : QThread(parent), node_(node) {}

void RosSpinThread::stop() {
    // Order matters. running_ is what closes the window where stop() lands
    // before run() has reached spin(): cancel() on an executor that is not
    // spinning yet does nothing, and the thread would then spin forever.
    // Setting the flag first means run() sees it and never enters spin().
    running_ = false;
    exec_.cancel();
}


void RosSpinThread::run() {
    qDebug() << "[ROS Thread] Spin thread started";

    exec_.add_node(node_);  // Node added here

    if (running_)
        exec_.spin(); // blocks until stop() cancels the executor

    exec_.remove_node(node_); // optional cleanup
    qDebug() << "[ROS Thread] Spin thread stopped";
}

// void RosSpinThread::run() {
//     qDebug() << "[ROS Thread] Spin thread started";
//     while (running_ && rclcpp::ok()) {
//         rclcpp::spin_some(node_);
//         QThread::msleep(10);
//     }
//     qDebug() << "[ROS Thread] Spin thread stopped";
// }

// void RosSpinThread::run() {
//     qDebug() << "[ROS Thread] Spin thread started";
//     rclcpp::spin(node_); // blocks, spins forever
//     qDebug() << "[ROS Thread] Spin thread stopped";
// }

RosNode::RosNode(QObject* parent) : QObject(parent) {}

RosNode::~RosNode() {
    destroyNode();
}

void RosNode::initialize(const QString& topicDetect) {
    detectTopic_ = topicDetect;

    // 60 Hz interpolation between detection messages
    detectionSmoother_.setModel(&detectionModel_);

    /*
     * Watches for IPv4 addresses appearing and rebuilds the node when the set
     * changes. The head unit starts this app before DHCP finishes, and a Fast
     * DDS participant only knows the interfaces that existed at creation —
     * WiFi is joined through this app, so first boot always loses that race.
     *
     * Ordering after network-online.target isn't the fix either: it would
     * blank the screen for the wait-online timeout on units with no network.
     */
    ifMonitor_ = new InterfaceMonitor(this);
    connect(ifMonitor_, &InterfaceMonitor::addressesChanged,
            this, &RosNode::onAddressesChanged);

    // Nothing to talk to yet: wait for the first address rather than burning a
    // participant that would be born deaf. On a board that already has an
    // address — the laptop, or a warm restart — this is taken immediately and
    // startup is unchanged.
    if (InterfaceMonitor::currentIPv4().isEmpty()) {
        qDebug() << "[RosNode] no usable IPv4 yet; deferring ROS node until one appears";
        return;
    }

    createNode();
}

void RosNode::onAddressesChanged(const QSet<QString>& addrs)
{
    // Losing every address is not a reason to act. The participant is no use
    // without a network either way, and tearing it down mid-flap only to
    // rebuild it a second later is churn for nothing — wait for an address to
    // come back and rebuild once, there.
    if (addrs.isEmpty()) {
        qDebug() << "[RosNode] no IPv4 addresses left; waiting for one to return";
        return;
    }

    // Same addresses the live node was built on: it can already reach
    // everything it will ever reach, so leave it alone. This is what keeps a
    // working node from being restarted by unrelated network activity.
    if (node_ && addrs == nodeAddrs_)
        return;

    qDebug() << "[RosNode] rebuilding ROS node for new address set:"
             << nodeAddrs_.values() << "->" << addrs.values();

    destroyNode();
    createNode();
}

void RosNode::destroyNode()
{
    if (spinThread_) {
        spinThread_->stop();
        spinThread_->wait();
        spinThread_.reset();
    }

    // Subscriptions must go before the node: they hold it alive, and the
    // participant is only dropped once the last node in the context is gone.
    detectSub_.reset();

    node_.reset();
    nodeAddrs_.clear();
}

void RosNode::createNode() {
    nodeAddrs_ = InterfaceMonitor::currentIPv4();

    // Tracks smoothed from the previous node's messages are stale the moment
    // it goes away — without this, whatever was on screen at the rebuild would
    // hang there as ghosts until the detector happened to reuse those ids.
    detectionSmoother_.clear();

    qDebug() << "[RosNode] Initializing with detection topic:" << detectTopic_
             << "on" << nodeAddrs_.values();

    node_ = std::make_shared<rclcpp::Node>("qt_pcl_visualizer");

    /*
     * No point cloud subscription: pointCloudCallback's body is commented out
     * and nothing draws a cloud any more (Environment3D replaced that view),
     * so this was pure overhead — a KITTI velodyne frame at 10 Hz saturates
     * the Jetson's WiFi (~155 Mbit/s vs ~11 Mbit/s available) and starved the
     * much smaller detections stream sharing the link.
     *
     * Restore this together with the callback body, not before it.
     */

    // detected objects
    detectSub_ = node_->create_subscription<object_detection_msgs::msg::Object3dArray>(
        detectTopic_.toStdString(),10,
        [this](const object_detection_msgs::msg::Object3dArray::ConstSharedPtr msg) {
            objectDetectionCallback(msg);

        });

    /*
     * No velocity subscription any more. Speed comes off CAN 0x200
     * VehicleStatus and from nowhere else — see VehicleBus. This topic carried
     * the KITTI bag's recorded velocity, which is not this car's speed, so
     * leaving it subscribed would only give it a second way back in.
     */

    /*
     * No IMU or GPS subscription either: both only fed CarInfo, and nothing
     * reads it back — orientation comes from the detection boxes, and no
     * screen shows lat/long/altitude. Same waste as the point cloud, cheaper.
     *
     * Restore together with whatever reads CarInfo, not before it.
     */

    spinThread_ = std::make_unique<RosSpinThread>(node_, this);
    spinThread_->start();
}

QString RosNode::frameId() const {
    QMutexLocker locker(&mutex_);
    return data_.frameId;
}

int RosNode::pointCount() const {
    QMutexLocker locker(&mutex_);
    return data_.points.size();
}


CloudData RosNode::getCloudData() {
    QMutexLocker locker(&mutex_);
    return data_;
}



void RosNode::pointCloudCallback(const sensor_msgs::msg::PointCloud2::ConstSharedPtr msg) {
    // CloudData next;
    // next.frameId = QString::fromStdString(msg->header.frame_id);

    // size_t totalPoints = static_cast<size_t>(msg->width) * msg->height;

    // // Check available fields
    // bool hasIntensity = false;
    // bool hasRing = false;
    // int intensityOffset = -1;
    // int ringOffset = -1;
    // uint8_t intensityDatatype = 0;

    // for (const auto& field : msg->fields) {
    //     if (field.name == "intensity") {
    //         hasIntensity = true;
    //         intensityOffset = field.offset;
    //         intensityDatatype = field.datatype;
    //     }
    //     if (field.name == "ring") {
    //         hasRing = true;
    //         ringOffset = field.offset;
    //     }
    // }

    // try {
    //     sensor_msgs::PointCloud2ConstIterator<float> itX(*msg, "x");
    //     sensor_msgs::PointCloud2ConstIterator<float> itY(*msg, "y");
    //     sensor_msgs::PointCloud2ConstIterator<float> itZ(*msg, "z");

    //     size_t step = std::max<size_t>(1, totalPoints / maxPoints_);
    //     double sx = 0, sy = 0, sz = 0;

    //     next.points.reserve(std::min(totalPoints, static_cast<size_t>(maxPoints_)));

    //     const uint8_t* dataPtr = msg->data.data();
    //     size_t pointStep = msg->point_step;

    //     for (size_t i = 0; i < totalPoints; i += step) {
    //         if (!(itX != itX.end())) break;

    //         float x = *itX, y = *itY, z = *itZ;

    //         if (std::isfinite(x) && std::isfinite(y) && std::isfinite(z)) {
    //             PointData pt;
    //             pt.x = x;
    //             pt.y = y;
    //             pt.z = z;

    //             // Read intensity
    //             if (hasIntensity && intensityOffset >= 0) {
    //                 const uint8_t* intensityPtr = dataPtr + (i * pointStep) + intensityOffset;
    //                 if (intensityDatatype == sensor_msgs::msg::PointField::FLOAT32) {
    //                     pt.intensity = *reinterpret_cast<const float*>(intensityPtr);
    //                 } else if (intensityDatatype == sensor_msgs::msg::PointField::UINT8) {
    //                     pt.intensity = static_cast<float>(*intensityPtr);
    //                 } else if (intensityDatatype == sensor_msgs::msg::PointField::UINT16) {
    //                     pt.intensity = static_cast<float>(*reinterpret_cast<const uint16_t*>(intensityPtr));
    //                 } else {
    //                     pt.intensity = 0.0f;
    //                 }
    //             } else {
    //                 pt.intensity = 0.0f;
    //             }

    //             // Read ring
    //             if (hasRing && ringOffset >= 0) {
    //                 const uint8_t* ringPtr = dataPtr + (i * pointStep) + ringOffset;
    //                 pt.ring = *ringPtr;
    //             } else {
    //                 pt.ring = 0;
    //             }

    //             next.points.append(pt);
    //             sx += x; sy += y; sz += z;

    //             if (next.points.size() == 1) {
    //                 next.minX = next.maxX = x;
    //                 next.minY = next.maxY = y;
    //                 next.minZ = next.maxZ = z;
    //                 next.minIntensity = next.maxIntensity = pt.intensity;
    //                 next.minRing = next.maxRing = pt.ring;
    //             } else {
    //                 next.minX = std::min(next.minX, x);
    //                 next.maxX = std::max(next.maxX, x);
    //                 next.minY = std::min(next.minY, y);
    //                 next.maxY = std::max(next.maxY, y);
    //                 next.minZ = std::min(next.minZ, z);
    //                 next.maxZ = std::max(next.maxZ, z);
    //                 next.minIntensity = std::min(next.minIntensity, pt.intensity);
    //                 next.maxIntensity = std::max(next.maxIntensity, pt.intensity);
    //                 next.minRing = std::min(next.minRing, pt.ring);
    //                 next.maxRing = std::max(next.maxRing, pt.ring);
    //             }
    //         }

    //         for (size_t s = 0; s < step && itX != itX.end(); ++s) {
    //             ++itX; ++itY; ++itZ;
    //         }

    //         if (static_cast<size_t>(next.points.size()) >= static_cast<size_t>(maxPoints_)) break;
    //     }

    //     if (!next.points.isEmpty()) {
    //         next.cx = sx / next.points.size();
    //         next.cy = sy / next.points.size();
    //         next.cz = sz / next.points.size();
    //     }

    // } catch (const std::exception& e) {
    //     qDebug() << "[RosNode] Error parsing point cloud:" << e.what();
    //     return;
    // }

    // {
    //     QMutexLocker locker(&mutex_);
    //     data_ = std::move(next);
    // }

    // emit cloudUpdated();
}


void RosNode::objectDetectionCallback(const object_detection_msgs::msg::Object3dArray::ConstSharedPtr msg){

    QList<DetectionData> detections;

    for (const auto& obj : msg->objects)
    {
        // Filter out low-confidence detections
        if (obj.confidence_score < confThresholdFor(obj.label))
            continue;

        DetectionData d;

        d.label = obj.label;
        d.confidence = obj.confidence_score;
        d.trackId = obj.track_id;

        QVector3D corners[8];

        for (int i = 0; i < 8; ++i)
        {
            const auto& p =
                obj.bounding_box.corners[i];

            corners[i] = QVector3D(
                p.x,
                p.y,
                p.z
                );
        }
        BoxTransform t =
            computeBoxTransform(corners);

        d.position = t.position;
        d.scale = t.scale;
        d.rotation = t.rotation;

        switch (obj.label)
        {
        case 0: // pedestrian
            d.color = Qt::red;
            break;

        case 1: // cyclist
            d.color = Qt::green;
            break;

        case 2: // car
            d.color = Qt::blue;
            break;

        default:
            d.color = Qt::white;
            break;
        }

        detections.append(d);
    }

    detectionSmoother_.update(
        detections);

}

DetectionModel* RosNode::detectionModel() const
{
    return const_cast<DetectionModel*>(
        &detectionModel_);
}

CarInfo *RosNode::carInfo() const
{
    return const_cast<CarInfo*>(&carInfo_);

}
