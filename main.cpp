#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <memory>
#include <rclcpp/rclcpp.hpp>
#include "Backend/BluetoothManager.hpp"
#include "Backend/USBManager.hpp"
#include "Backend/WifiManager.hpp"
#include "Backend/BluetoothHWManager.hpp"
#include "Backend/SystemVolumeController.hpp"
#include "Backend/SpeechManager.hpp"
#include "Backend/MediaLibrary.hpp"
#include "Backend/AmbientLightManager.hpp"
#include "DriveView/inc/ros_node.h"
#include "DriveView/inc/detection_instancing.h"
#include "Backend/OtaManager.hpp"

int main(int argc, char *argv[]){
    rclcpp::init(argc, argv);

    QGuiApplication app(argc, argv);

    // Required before any QML Settings element will work. Without these,
    // QSettings refuses to initialise ("The following application identifiers
    // have not been set") and every saved value — the weather city, the last
    // reading shown on the launcher — is silently discarded at every boot.
    QGuiApplication::setOrganizationName(QStringLiteral("IVI"));
    QGuiApplication::setOrganizationDomain(QStringLiteral("ivi.local"));
    QGuiApplication::setApplicationName(QStringLiteral("IVI"));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    // Media Player Managers
    BluetoothManager btManager;
    UsbManager usbManager;
    engine.rootContext()->setContextProperty("btManager", &btManager);
    engine.rootContext()->setContextProperty("usbManager", &usbManager);

    // Local media libraries. Listed in C++ so the UI does not depend on the
    // Qt.labs.folderlistmodel QML plugin being present in the target image.
    MediaLibrary *musicLibrary = MediaLibrary::music(&app);
    MediaLibrary *videoLibrary = MediaLibrary::video(&app);
    engine.rootContext()->setContextProperty("musicLibrary", musicLibrary);
    engine.rootContext()->setContextProperty("videoLibrary", videoLibrary);
    qInfo().noquote() << "[music] library folder:" << musicLibrary->folder();
    qInfo().noquote() << "[video] library folder:" << videoLibrary->folder();
    
    // Settings Managers
    WifiManager wifiManager;
    BluetoothHWManager bluetoothManager;
    engine.rootContext()->setContextProperty("WifiManager", &wifiManager);
    engine.rootContext()->setContextProperty("BluetoothManager", &bluetoothManager);

    // Inquiry starves the ACL link and audibly breaks up A2DP, so the settings
    // page must not scan while the media side is playing.
    QObject::connect(&btManager, &BluetoothManager::playerStatusChanged,
                     &bluetoothManager, [&btManager, &bluetoothManager]() {
        bluetoothManager.setMediaActive(
            btManager.playerStatus().compare("playing", Qt::CaseInsensitive) == 0);
    });

    // System Volume Controller
    SystemVolumeController systemVolumeController;
    engine.rootContext()->setContextProperty("systemVolume", &systemVolumeController);

    // Cabin ambient lighting, over CAN to the ESP32
    AmbientLightManager ambientLight;
    engine.rootContext()->setContextProperty("AmbientLight", &ambientLight);

    // Speech Recognition Manager
    SpeechManager speechManager;
    engine.rootContext()->setContextProperty("speechManager", &speechManager);

    // --- DriveView: 3D surroundings visualization (ROS2) ---
    RosNode *rosNode = new RosNode(&app);
    rosNode->initialize("/kitti/velo", "/object_detections_3d",
                        "/kitti/oxts/gps/vel", "/kitti/oxts/imu",
                        "/kitti/oxts/gps/fix", 20000);
    engine.rootContext()->setContextProperty("rosNodeInstance", rosNode);
    engine.rootContext()->setContextProperty("detectionModel", rosNode->detectionModel());
    engine.rootContext()->setContextProperty("carInfo", rosNode->carInfo());

    std::unique_ptr<DetectionInstancing> planeInstancing =
        std::make_unique<DetectionInstancing>();
    std::unique_ptr<DetectionInstancing> cubeInstancing =
        std::make_unique<DetectionInstancing>();
    std::unique_ptr<DetectionInstancing> carInstancing =
        std::make_unique<DetectionInstancing>();
    planeInstancing->setLabelFilter(0);
    cubeInstancing->setLabelFilter(1);
    carInstancing->setLabelFilter(2);
    for (DetectionInstancing *inst : {
             planeInstancing.get(), cubeInstancing.get(), carInstancing.get() })
        inst->setModel(rosNode->detectionModel());
    engine.rootContext()->setContextProperty("planeInstancing", planeInstancing.get());
    engine.rootContext()->setContextProperty("cubeInstancing", cubeInstancing.get());
    engine.rootContext()->setContextProperty("carInstancing", carInstancing.get());
    // OTA approval. Watches the spool for firmware-update requests from the
    // update coordinator and the OTA agent, and writes back the user's answer.
    // Constructed last so its first scan happens with everything else already
    // up — an offer can be waiting from before this app started.
    OtaManager otaManager;
    engine.rootContext()->setContextProperty("otaManager", &otaManager);

    engine.loadFromModule("IVI", "Main");

    int result = app.exec();

    rclcpp::shutdown();
    return result;
}
