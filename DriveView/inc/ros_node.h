#ifndef ROS_NODE_H
#define ROS_NODE_H

#include <QObject>
#include <QThread>
#include <QVector3D>
#include <QVector>
#include <QMutex>
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
    void velocityCallback(const geometry_msgs::msg::TwistStamped::ConstSharedPtr msg);
    void imuCallback(const sensor_msgs::msg::Imu::ConstSharedPtr msg);
    void gpsCallback(const sensor_msgs::msg::NavSatFix::ConstSharedPtr msg);


    std::shared_ptr<rclcpp::Node> node_;
    std::unique_ptr<RosSpinThread> spinThread_;
    rclcpp::Subscription<sensor_msgs::msg::PointCloud2>::SharedPtr pointCloudSub_;

    // detected objects subscription & model
    rclcpp::Subscription<object_detection_msgs::msg::Object3dArray>::SharedPtr detectSub_;
    DetectionModel detectionModel_;
    DetectionSmoother detectionSmoother_;

    // car info subscription (velocity and IMU)
    rclcpp::Subscription<geometry_msgs::msg::TwistStamped>::SharedPtr velSub_;
    rclcpp::Subscription<sensor_msgs::msg::Imu>::SharedPtr imuSub_;
    rclcpp::Subscription<sensor_msgs::msg::NavSatFix>::SharedPtr gpsSub_;
    CarInfo carInfo_;




    mutable QMutex mutex_;
    CloudData data_;
    int maxPoints_ = 20000;

};

#endif // ROS_NODE_H
