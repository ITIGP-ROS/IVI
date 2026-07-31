#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "Backend/BluetoothManager.hpp"
#include "Backend/USBManager.hpp"
#include "Backend/WifiManager.hpp"
#include "Backend/BluetoothHWManager.hpp"
#include "Backend/SystemVolumeController.hpp"
#include "Backend/SpeechManager.hpp"
#include "Backend/MediaLibrary.hpp"
#include "Backend/AmbientLightManager.hpp"

int main(int argc, char *argv[]){
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

    engine.loadFromModule("IVI", "Main");

    return app.exec();
}
