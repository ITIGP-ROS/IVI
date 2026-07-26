#include "BluetoothManager.hpp"
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusArgument>
#include <QDBusVariant>
#include <QDebug>

static const QString BLUEZ_SERVICE      = "org.bluez";
static const QString BLUEZ_ROOT         = "/";
static const QString BLUEZ_DEVICE_IFACE = "org.bluez.Device1";
static const QString BLUEZ_PLAYER_IFACE = "org.bluez.MediaPlayer1";
static const QString DBUS_OBJMGR_IFACE  = "org.freedesktop.DBus.ObjectManager";
static const QString DBUS_PROPS_IFACE   = "org.freedesktop.DBus.Properties";

BluetoothManager::BluetoothManager(QObject* parent) : QObject(parent), m_bus(QDBusConnection::systemBus()){ init(); }

void BluetoothManager::init(){
    if(!m_bus.isConnected()){
        emit errorOccurred("Cannot connect to system D-Bus");
        return;
    }
    // Poll every 0.5 seconds => reads device + track state fresh each time
    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(500);
    connect(m_pollTimer, &QTimer::timeout, this, &BluetoothManager::poll);
    m_pollTimer->start();
    // Run immediately on startup
    poll();
}

//  getManagedObjects — returns map of path → list of interfaces
//  Uses raw QDBusArgument to avoid silent deserialization failures
QMap<QString, QStringList> BluetoothManager::getManagedObjects(){
    QMap<QString, QStringList> result;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        BLUEZ_SERVICE, BLUEZ_ROOT, DBUS_OBJMGR_IFACE, "GetManagedObjects"
    );
    QDBusMessage reply = m_bus.call(msg);

    if(reply.type() == QDBusMessage::ErrorMessage){
        qDebug() << "GetManagedObjects error:" << reply.errorMessage();
        return result;
    }
    if(reply.arguments().isEmpty()) 
        return result;

    const QDBusArgument rootArg = reply.arguments().at(0).value<QDBusArgument>();

    rootArg.beginMap();
    while(!rootArg.atEnd()){
        rootArg.beginMapEntry();

        QDBusObjectPath objPath;
        rootArg >> objPath;

        // Read interface names only (skip property values for speed)
        QStringList ifaces;
        rootArg.beginMap();
        while (!rootArg.atEnd()) {
            rootArg.beginMapEntry();
            QString ifaceName;
            rootArg >> ifaceName;
            ifaces << ifaceName;

            // Must consume the property map even if we don't need it
            QDBusVariant dummy;
            rootArg.beginMap();
            while (!rootArg.atEnd()) {
                rootArg.beginMapEntry();
                QString k; QDBusVariant v;
                rootArg >> k >> v;
                rootArg.endMapEntry();
            }
            rootArg.endMap();
            rootArg.endMapEntry();
        }
        rootArg.endMap();

        result[objPath.path()] = ifaces;
        rootArg.endMapEntry();
    }
    rootArg.endMap();

    return result;
}

//  getProperties - reads all properties for one object/interface
QVariantMap BluetoothManager::getProperties(const QString& path, const QString& iface){
    QVariantMap result;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        BLUEZ_SERVICE, path, DBUS_PROPS_IFACE, "GetAll"
    );
    msg << iface;

    QDBusMessage reply = m_bus.call(msg);
    if (reply.type() == QDBusMessage::ErrorMessage) return result;
    if (reply.arguments().isEmpty()) return result;

    const QDBusArgument arg = reply.arguments().at(0).value<QDBusArgument>();

    arg.beginMap();
    while (!arg.atEnd()) {
        arg.beginMapEntry();
        QString key;
        QDBusVariant val;
        arg >> key >> val;
        result[key] = val.variant();
        arg.endMapEntry();
    }
    arg.endMap();

    return result;
}

//  poll — called every 0.5s, reads entire BT state fresh each time
void BluetoothManager::poll(){
    const auto objects = getManagedObjects();

    QString newDevicePath;
    QString newPlayerPath;

    // Find connected device + media player
    for(auto it = objects.begin(); it != objects.end(); ++it) {
        const QString& path       = it.key();
        const QStringList& ifaces = it.value();

        if(ifaces.contains(BLUEZ_DEVICE_IFACE)) {
            QVariantMap props = getProperties(path, BLUEZ_DEVICE_IFACE);
            if(props.value("Connected").toBool()) {
                newDevicePath = path;
            }
        }

        if(ifaces.contains(BLUEZ_PLAYER_IFACE)) {
            newPlayerPath = path;
        }
    }

    // Update connection state
    bool nowConnected = !newDevicePath.isEmpty();

    if(nowConnected != m_connected) {
        m_connected = nowConnected;
        emit connectedChanged();
        qDebug() << (m_connected ? "✅ BT connected" : "❌ BT disconnected");
    }

    if(!m_connected) {
        // Clear everything if disconnected
        if (!m_deviceName.isEmpty()) {
            m_deviceName = m_deviceAddress = m_devicePath = "";
            m_playerPath = m_trackTitle = m_trackArtist = "";
            m_trackAlbum = m_playerStatus = "";
            emit deviceNameChanged();
            emit trackInfoChanged();
            emit playerStatusChanged();
        }
        return;
    }

    m_devicePath = newDevicePath;
    m_playerPath = newPlayerPath;

    // Read device info
    QVariantMap devProps = getProperties(m_devicePath, BLUEZ_DEVICE_IFACE);
    QString newName    = devProps.value("Name").toString();
    QString newAddress = devProps.value("Address").toString();

    if(newName != m_deviceName){
        m_deviceName = newName;
        emit deviceNameChanged();
    }
    if(newAddress != m_deviceAddress){
        m_deviceAddress = newAddress;
        emit deviceAddressChanged();
    }

    // Read player info (track + status)
    if(m_playerPath.isEmpty()){
        qDebug() << "⚠ No MediaPlayer1 yet — play a song on your phone";
        return;
    }

    QVariantMap playerProps = getProperties(m_playerPath, BLUEZ_PLAYER_IFACE);

    // Status
    QString newStatus = playerProps.value("Status").toString();
    if(newStatus != m_playerStatus) {
        m_playerStatus = newStatus;
        emit playerStatusChanged();
        qDebug() << "▶ Status:" << m_playerStatus;
    }

    // Track
    QVariant trackVariant = playerProps.value("Track");
    QVariantMap track;

    // Track is a{sv} — needs manual extraction
    if(trackVariant.canConvert<QDBusArgument>()) {
        const QDBusArgument trackArg = trackVariant.value<QDBusArgument>();
        trackArg.beginMap();
        while (!trackArg.atEnd()) {
            trackArg.beginMapEntry();
            QString k; QDBusVariant v;
            trackArg >> k >> v;
            track[k] = v.variant();
            trackArg.endMapEntry();
        }
        trackArg.endMap();
    } 
    else {
        track = qdbus_cast<QVariantMap>(trackVariant);
    }

    QString newTitle  = track.value("Title").toString();
    QString newArtist = track.value("Artist").toString();
    QString newAlbum  = track.value("Album").toString();

    if(newTitle != m_trackTitle || newArtist != m_trackArtist || newAlbum != m_trackAlbum) {
        m_trackTitle  = newTitle;
        m_trackArtist = newArtist;
        m_trackAlbum  = newAlbum;
        emit trackInfoChanged();
        qDebug() << "🎵" << m_trackTitle << "-" << m_trackArtist;
    }
}

//  AVRCP commands
void BluetoothManager::sendAvrcpCommand(const QString& command){
    if(m_playerPath.isEmpty()){
        emit errorOccurred("No media player - play a song on your phone first");
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(
        BLUEZ_SERVICE, m_playerPath, BLUEZ_PLAYER_IFACE, command
    );

    QDBusMessage reply = m_bus.call(msg);

    if(reply.type() == QDBusMessage::ErrorMessage)
        emit errorOccurred("AVRCP failed: " + reply.errorMessage());
}

void BluetoothManager::play()     { sendAvrcpCommand("Play");     }
void BluetoothManager::pause()    { sendAvrcpCommand("Pause");    }
void BluetoothManager::next()     { sendAvrcpCommand("Next");     }
void BluetoothManager::previous() { sendAvrcpCommand("Previous"); }
void BluetoothManager::stop()     { sendAvrcpCommand("Stop");     }