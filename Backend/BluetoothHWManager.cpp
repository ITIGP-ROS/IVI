#include "BluetoothHWManager.hpp"
#include <QDBusReply>
#include <QDBusMetaType>
#include <QDBusArgument>
#include <QDBusPendingReply>
#include <QTimer>

// D-Bus custom type registration
typedef QMap<QString, QVariantMap>              DBusInterfaceMap;
typedef QMap<QDBusObjectPath, DBusInterfaceMap> DBusManagedObjects;
Q_DECLARE_METATYPE(DBusInterfaceMap)
Q_DECLARE_METATYPE(DBusManagedObjects)

QDBusArgument &operator<<(QDBusArgument &arg, const DBusInterfaceMap &map){
    arg.beginMap(QMetaType::QString, qMetaTypeId<QVariantMap>());
    for (auto it = map.begin(); it != map.end(); ++it) {
        arg.beginMapEntry();
        arg << it.key() << it.value();
        arg.endMapEntry();
    }
    arg.endMap();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, DBusInterfaceMap &map){
    arg.beginMap();
    while (!arg.atEnd()) {
        QString key;
        QVariantMap val;
        arg.beginMapEntry();
        arg >> key >> val;
        arg.endMapEntry();
        map[key] = val;
    }
    arg.endMap();
    return arg;
}

QDBusArgument &operator<<(QDBusArgument &arg, const DBusManagedObjects &map){
    arg.beginMap(qMetaTypeId<QDBusObjectPath>(), qMetaTypeId<DBusInterfaceMap>());
    for (auto it = map.begin(); it != map.end(); ++it) {
        arg.beginMapEntry();
        arg << it.key() << it.value();
        arg.endMapEntry();
    }
    arg.endMap();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, DBusManagedObjects &map){
    arg.beginMap();
    while (!arg.atEnd()) {
        QDBusObjectPath path;
        DBusInterfaceMap ifaces;
        arg.beginMapEntry();
        arg >> path >> ifaces;
        arg.endMapEntry();
        map[path] = ifaces;
    }
    arg.endMap();
    return arg;
}

// BlueZ D-Bus constants
static const QString BZ_SERVICE = "org.bluez";
static const QString BZ_ADAPTER = "org.bluez.Adapter1";
static const QString BZ_DEVICE  = "org.bluez.Device1";
static const QString BZ_OBJ_MGR = "org.freedesktop.DBus.ObjectManager";
static const QString BZ_PROPS   = "org.freedesktop.DBus.Properties";
static const QString BZ_ROOT    = "/";

// Helper: get all managed BlueZ objects
static DBusManagedObjects getManagedObjects(){
    qDBusRegisterMetaType<DBusInterfaceMap>();
    qDBusRegisterMetaType<DBusManagedObjects>();

    QDBusMessage msg = QDBusMessage::createMethodCall(
        BZ_SERVICE, BZ_ROOT, BZ_OBJ_MGR, "GetManagedObjects");
    QDBusMessage resp = QDBusConnection::systemBus().call(msg);

    DBusManagedObjects result;
    if (resp.type() != QDBusMessage::ErrorMessage)
        resp.arguments().at(0).value<QDBusArgument>() >> result;
    return result;
}

BluetoothHWManager::BluetoothHWManager(QObject *parent) : QObject(parent){
    qDBusRegisterMetaType<DBusInterfaceMap>();
    qDBusRegisterMetaType<DBusManagedObjects>();

    QString adapterPath = getAdapterPath();
    if (adapterPath.isEmpty()) {
        qWarning() << "BluetoothHWManager: No Bluetooth adapter found";
        return;
    }
    m_adapterPath = adapterPath;

    m_adapterIface = new QDBusInterface(
        BZ_SERVICE, adapterPath, BZ_ADAPTER,
        QDBusConnection::systemBus(), this);

    if (m_adapterIface->isValid()) {
        QVariant val = m_adapterIface->property("Powered");
        if (val.isValid())
            m_bluetoothEnabled = val.toBool();
    }

    QDBusConnection::systemBus().connect(
        BZ_SERVICE, adapterPath, BZ_PROPS, "PropertiesChanged",
        this,
        SLOT(onAdapterPropertiesChanged(QString, QVariantMap, QStringList)));

    subscribeToAllKnownDevices();
}

// Subscribe to every device BlueZ already knows at startup
void BluetoothHWManager::subscribeToAllKnownDevices(){
    DBusManagedObjects objects = getManagedObjects();
    for (auto it = objects.begin(); it != objects.end(); ++it) {
        const DBusInterfaceMap &ifaces = it.value();
        if (!ifaces.contains(BZ_DEVICE)) continue;

        const QVariantMap &props = ifaces[BZ_DEVICE];
        QString address   = props.value("Address", "").toString();
        bool    connected = props.value("Connected", false).toBool();

        if (address.isEmpty()) continue;

        subscribeToDevice(it.key().path(), address);

        if (connected)
            emit deviceConnectionChanged(address, true);
    }
}

// Find the first valid Bluetooth adapter path
QString BluetoothHWManager::getAdapterPath(){
    for (const QString &path : { QString("/org/bluez/hci0"),
                                  QString("/org/bluez/hci1") }) {
        QDBusInterface iface(BZ_SERVICE, path, BZ_ADAPTER,
                             QDBusConnection::systemBus());
        if (iface.isValid())
            return path;
    }
    return {};
}

// Find a device's D-Bus path by MAC address
QString BluetoothHWManager::findDevicePath(const QString &address){
    DBusManagedObjects objects = getManagedObjects();
    for (auto it = objects.begin(); it != objects.end(); ++it) {
        const DBusInterfaceMap &ifaces = it.value();
        if (ifaces.contains(BZ_DEVICE)) {
            if (ifaces[BZ_DEVICE].value("Address").toString() == address)
                return it.key().path();
        }
    }
    return {};
}

// Subscribe to a single device's PropertiesChanged signal
void BluetoothHWManager::subscribeToDevice(const QString &path, const QString &address){
    if (m_subscribedPaths.contains(path)) return;
    m_subscribedPaths << path;

    DeviceWatcher *watcher = new DeviceWatcher(path, address, this);

    connect(watcher, &DeviceWatcher::connectionChanged,
            this,    &BluetoothHWManager::deviceConnectionChanged);

    QDBusConnection::systemBus().connect(
        BZ_SERVICE, path, BZ_PROPS, "PropertiesChanged",
        watcher,
        SLOT(onPropertiesChanged(const QString&, const QVariantMap&, const QStringList&))
    );

    // Read and emit current Connected state immediately
    QDBusInterface devIface(BZ_SERVICE, path, BZ_DEVICE,
                            QDBusConnection::systemBus());
    if (devIface.isValid()) {
        bool connected = devIface.property("Connected").toBool();
        emit deviceConnectionChanged(address, connected);
    }
}

// Getters / Setters
bool BluetoothHWManager::bluetoothEnabled() const{
    return m_bluetoothEnabled;
}

void BluetoothHWManager::setBluetoothEnabled(bool enabled){
    if(!m_adapterIface || !m_adapterIface->isValid()) {
        qWarning() << "BluetoothHWManager: No adapter to toggle";
        return;
    }
    if(m_bluetoothEnabled == enabled) 
        return;

    QDBusInterface propsIface(BZ_SERVICE, m_adapterPath, BZ_PROPS,
                              QDBusConnection::systemBus());

    QDBusMessage reply = propsIface.call(
        "Set", BZ_ADAPTER, "Powered",
        QVariant::fromValue(QDBusVariant(enabled))
    );

    if(reply.type() == QDBusMessage::ErrorMessage)
        qWarning() << "BT Set Powered failed:" << reply.errorMessage();
}

// Adapter property changed
void BluetoothHWManager::onAdapterPropertiesChanged(QString interface, QVariantMap changedProps, QStringList invalidatedProps){
    Q_UNUSED(interface) Q_UNUSED(invalidatedProps)

    if (changedProps.contains("Powered")) {
        m_bluetoothEnabled = changedProps["Powered"].toBool();
        emit bluetoothEnabledChanged(m_bluetoothEnabled);
    }
}

void BluetoothHWManager::onInterfacesAdded(const QDBusObjectPath &path, const QVariantMap &interfaces){
    Q_UNUSED(path) Q_UNUSED(interfaces)
}

// Scan for nearby Bluetooth devices
void BluetoothHWManager::scanDevices(){
    if(!m_adapterIface || !m_adapterIface->isValid()) {
        emit scanFailed("No Bluetooth adapter available");
        return;
    }
    if(!m_bluetoothEnabled) {
        emit scanFailed("Bluetooth is turned off");
        return;
    }

    emit scanStarted();

    QDBusReply<void> reply = m_adapterIface->call("StartDiscovery");
    if (!reply.isValid()) {
        emit scanFailed(reply.error().message());
        return;
    }

    QTimer::singleShot(8000, this, [this]() {
        m_adapterIface->call("StopDiscovery");

        DBusManagedObjects objects = getManagedObjects();
        QStringList devices;

        for (auto it = objects.begin(); it != objects.end(); ++it) {
            const DBusInterfaceMap &ifaces = it.value();
            if (!ifaces.contains(BZ_DEVICE)) continue;

            const QVariantMap &props = ifaces[BZ_DEVICE];
            QString name      = props.value("Name",      "Unknown").toString();
            QString address   = props.value("Address",   "").toString();
            bool    connected = props.value("Connected", false).toBool();

            if (address.isEmpty()) continue;

            devices << name + "|" + address + "|" + (connected ? "1" : "0");
            subscribeToDevice(it.key().path(), address);
        }

        emit scanFinished(devices);
    });
}

// Pair with a device by MAC address
void BluetoothHWManager::pairDevice(const QString &address){
    QString path = findDevicePath(address);
    if (path.isEmpty()) {
        emit pairFailed("Device not found: " + address);
        return;
    }

    QDBusInterface devIface(BZ_SERVICE, path, BZ_DEVICE,
                            QDBusConnection::systemBus());
    QString name = devIface.property("Name").toString();

    if (devIface.property("Paired").toBool()) {
        emit pairSuccess(name + " (already paired)");
        return;
    }

    QDBusReply<void> reply = devIface.call("Pair");
    if (!reply.isValid()) {
        emit pairFailed(reply.error().message());
        return;
    }

    emit pairSuccess(name);
}

// Connect to a device — async so UI shows "Connecting..." state
void BluetoothHWManager::connectDevice(const QString &address){
    QString path = findDevicePath(address);
    if (path.isEmpty()) {
        emit connectFailed("Device not found: " + address);
        return;
    }

    QDBusInterface *devIface = new QDBusInterface(
        BZ_SERVICE, path, BZ_DEVICE,
        QDBusConnection::systemBus(), this);

    QString name = devIface->property("Name").toString();

    QDBusPendingCall call = devIface->asyncCall("Connect");
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);

    connect(watcher, &QDBusPendingCallWatcher::finished,
            this, [this, watcher, name, devIface](QDBusPendingCallWatcher *) {
        QDBusPendingReply<> reply = *watcher;
        if (reply.isError())
            emit connectFailed(reply.error().message());
        else
            emit connectSuccess(name);
        watcher->deleteLater();
        devIface->deleteLater();
    });
}

// Disconnect from a device — async
void BluetoothHWManager::disconnectDevice(const QString &address){
    QString path = findDevicePath(address);
    if (path.isEmpty()) {
        emit disconnectFailed("Device not found: " + address);
        return;
    }

    QDBusInterface *devIface = new QDBusInterface(
        BZ_SERVICE, path, BZ_DEVICE,
        QDBusConnection::systemBus(), this);

    QString name = devIface->property("Name").toString();

    QDBusPendingCall call = devIface->asyncCall("Disconnect");
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);

    connect(watcher, &QDBusPendingCallWatcher::finished,
            this, [this, watcher, name, devIface](QDBusPendingCallWatcher *) {
        QDBusPendingReply<> reply = *watcher;
        if (reply.isError())
            emit disconnectFailed(reply.error().message());
        else
            emit disconnectSuccess(name);
        watcher->deleteLater();
        devIface->deleteLater();
    });
}