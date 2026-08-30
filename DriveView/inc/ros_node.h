#ifndef ROS_NODE_H
#define ROS_NODE_H

#include <QObject>
#include <QThread>
#include <QVector3D>
#include <QVector>
#include <QMutex>
#include <QSet>
#include <QString>
#include <memory>
#include <atomic>

#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/point_cloud2.hpp>
#include "object_detection_msgs/msg/object3d_array.hpp"
#include "object_detection_msgs/msg/object3d.hpp"


#include "detection_model.h"
#include "detection_smoother.h"
#include "car_info.h"
#include "interface_monitor.h"


struct PointData {
    float x, y, z;
    float intensity;
    uint8_t ring;
};

struct CloudData {
    QVector<PointData> points;
    QString frameId = "waiting...";
    float minX = 0, maxX = 0;
    float minY = 0, maxY = 0;
    float minZ = 0, maxZ = 0;
    float minIntensity = 0, maxIntensity = 0;
    uint8_t minRing = 0, maxRing = 0;
    float cx = 0, cy = 0, cz = 0;
};

class RosSpinThread : public QThread {
    Q_OBJECT
public:
    explicit RosSpinThread(std::shared_ptr<rclcpp::Node> node, QObject* parent = nullptr);
    void stop();

protected:
    void run() override;

private:
    std::shared_ptr<rclcpp::Node> node_;
    // The executor lives here, not on run()'s stack, because stop() has to be
    // able to cancel() it from the GUI thread. Clearing a flag cannot end a
    // spin(): it blocks in the middle of a wait and never looks at the flag,
    // so stop() + wait() used to deadlock on shutdown.
    rclcpp::executors::StaticSingleThreadedExecutor exec_;
    std::atomic<bool> running_{true};
};

class RosNode : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString frameId READ frameId NOTIFY cloudUpdated)
    Q_PROPERTY(int pointCount READ pointCount NOTIFY cloudUpdated)

public:
    explicit RosNode(QObject* parent = nullptr);
    ~RosNode() override;

    // Detections are the only thing this node subscribes to, so they are the
    // only thing it needs to be told. The cloud, velocity, IMU and GPS topic
    // names went out with their subscriptions, and maxPoints with the cloud.
    void initialize(const QString& topicDetect);

    QString frameId() const;
    int pointCount() const;

    CloudData getCloudData();


    // getters for the classes ( detection model and car info)
    DetectionModel* detectionModel() const;
    CarInfo* carInfo() const;


signals:
    void cloudUpdated();

private:
    void pointCloudCallback(const sensor_msgs::msg::PointCloud2::ConstSharedPtr msg);
    void objectDetectionCallback(const object_detection_msgs::msg::Object3dArray::ConstSharedPtr msg);

    /*
     * Build/tear down the ROS node. Split out of initialize() because the
     * node must be rebuilt, not just built: Fast DDS scans interfaces once
     * per DomainParticipant, and rmw_fastrtps refcounts one participant per
     * node count — destroying the only node drops it, so the next
     * createNode() scans interfaces afresh.
     *
     * Both run on the GUI thread; destroyNode() joins the spin thread first,
     * so no callback is in flight once it returns.
     */
    void createNode();
    void destroyNode();
    void onAddressesChanged(const QSet<QString>& addrs);

    std::shared_ptr<rclcpp::Node> node_;
    std::unique_ptr<RosSpinThread> spinThread_;

    // Topic name, kept so a rebuild can resubscribe without the caller.
    QString detectTopic_;

    // Watches the kernel for IPv4 address changes, and the address set the
    // live node was built on. Comparing against the latter is what stops a
    // working node from being torn down for no reason.
    InterfaceMonitor* ifMonitor_ = nullptr;
    QSet<QString> nodeAddrs_;
    // No point cloud subscription: the callback is disabled and nothing draws
    // a cloud, so it only cost bandwidth. See RosNode::initialize.

    // detected objects subscription & model
    rclcpp::Subscription<object_detection_msgs::msg::Object3dArray>::SharedPtr detectSub_;
    DetectionModel detectionModel_;
    DetectionSmoother detectionSmoother_;

    // No IMU or GPS subscription. Both fed CarInfo and nothing read what they
    // wrote: no view uses the orientation quaternion, and nothing on any screen
    // shows latitude, longitude or altitude. Speed — the one CarInfo field QML
    // does read — comes off CAN 0x200 VehicleStatus via VehicleBus, never ROS.
    CarInfo carInfo_;




    mutable QMutex mutex_;
    CloudData data_;
    int maxPoints_ = 20000;

};

#endif // ROS_NODE_H
