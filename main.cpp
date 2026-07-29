#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "Backend/BluetoothManager.hpp"
#include "Backend/USBManager.hpp"
#include "Backend/WifiManager.hpp"
#include "Backend/BluetoothHWManager.hpp"
#include "Backend/SystemVolumeController.hpp"
#include "Backend/SpeechManager.hpp"

int main(int argc, char *argv[]){
    QGuiApplication app(argc, argv);

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

    // Speech Recognition Manager
    SpeechManager speechManager;
    engine.rootContext()->setContextProperty("speechManager", &speechManager);

    engine.loadFromModule("IVI", "Main");

    return app.exec();
}
