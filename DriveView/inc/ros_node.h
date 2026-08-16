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
#include <sensor_msgs/msg/imu.hpp>
#include <sensor_msgs/msg/nav_sat_fix.hpp>

#include <geometry_msgs/msg/twist_stamped.hpp>
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

    void initialize(const QString& topic,const QString& topic_detect, const QString& velTopic, const QString& imuTopic, const QString& gpsTopic,
                    int maxPoints);

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
    void imuCallback(const sensor_msgs::msg::Imu::ConstSharedPtr msg);
    void gpsCallback(const sensor_msgs::msg::NavSatFix::ConstSharedPtr msg);

    /*
     * Build and tear down the ROS node.
     *
     * Split out of initialize() because the node has to be rebuilt, not just
     * built: Fast DDS scans the host's interfaces once per DomainParticipant
     * and never rescans, so a participant created before the WiFi has an
     * address stays invisible to every other host for as long as the process
     * lives. rmw_fastrtps keeps one participant per context, refcounted by
     * node count, so destroying this process's only node drops the
     * participant and creating the next one scans the interfaces afresh.
     *
     * Both run on the GUI thread; destroyNode() joins the spin thread, so
     * no callback can be in flight once it returns.
     */
    void createNode();
    void destroyNode();
    void onAddressesChanged(const QSet<QString>& addrs);

    std::shared_ptr<rclcpp::Node> node_;
    std::unique_ptr<RosSpinThread> spinThread_;

    // Topic names, kept so a rebuild can resubscribe without the caller.
    QString detectTopic_;
    QString imuTopic_;
    QString gpsTopic_;

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

    // car info subscriptions (IMU and GPS). Speed is NOT among them: it comes
    // off CAN 0x200 VehicleStatus, via VehicleBus.
    rclcpp::Subscription<sensor_msgs::msg::Imu>::SharedPtr imuSub_;
    rclcpp::Subscription<sensor_msgs::msg::NavSatFix>::SharedPtr gpsSub_;
    CarInfo carInfo_;




    mutable QMutex mutex_;
    CloudData data_;
    int maxPoints_ = 20000;

};

#endif // ROS_NODE_H
