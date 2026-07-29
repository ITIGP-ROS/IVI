#include "BluetoothManager.hpp"
#include "BlueZ.hpp"
#include <QDBusMessage>
#include <QTimer>
#include <QDebug>

BluetoothManager::BluetoothManager(QObject* parent)
    : QObject(parent), m_bus(QDBusConnection::systemBus())
{
    if (!m_bus.isConnected()) {
        // Deferred so the signal is not emitted before anything is listening.
        QTimer::singleShot(0, this, [this]() {
            emit errorOccurred(QStringLiteral("Cannot connect to system D-Bus"));
        });
        return;
    }

    BlueZ::registerTypes();

    m_bus.connect(BlueZ::Service, BlueZ::Root, BlueZ::ObjMgrIface,
                  QStringLiteral("InterfacesAdded"),
                  this, SLOT(onInterfacesAdded(QDBusObjectPath, QVariantMap)));
    m_bus.connect(BlueZ::Service, BlueZ::Root, BlueZ::ObjMgrIface,
                  QStringLiteral("InterfacesRemoved"),
                  this, SLOT(onInterfacesRemoved(QDBusObjectPath, QStringList)));
    m_bus.connect(QStringLiteral("org.freedesktop.DBus"),
                  QStringLiteral("/org/freedesktop/DBus"),
                  QStringLiteral("org.freedesktop.DBus"),
                  QStringLiteral("NameOwnerChanged"),
                  QStringList{ BlueZ::Service }, QString(),
                  this, SLOT(onBlueZOwnerChanged(QString, QString, QString)));

    QTimer::singleShot(0, this, [this]() { rescan(); });
}

// Full refresh. Only runs at startup, on BlueZ restart, and on object churn —
// not on a timer.
void BluetoothManager::rescan()
{
    BlueZ::managedObjects(this, [this](const DBusManagedObjects &objects) {
        QString devicePath, playerPath;
        QVariantMap deviceProps;

        // Deterministic choice: the connected device with the lowest object path.
        // The old code kept the LAST match, so with two phones paired it drove a
        // non-deterministic one.
        for (auto it = objects.begin(); it != objects.end(); ++it) {
            const DBusInterfaceMap &ifaces = it.value();
            if (!ifaces.contains(BlueZ::DeviceIface)) continue;
            const QVariantMap &p = ifaces.value(BlueZ::DeviceIface);
            if (!p.value(QStringLiteral("Connected"), false).toBool()) continue;

            if (devicePath.isEmpty() || it.key().path() < devicePath) {
                devicePath  = it.key().path();
                deviceProps = p;
            }
        }

        if (devicePath.isEmpty()) { clearDevice(); return; }

        // Prefer the player that belongs to the selected device (its path is a
        // child of the device path) rather than whichever came last.
        for (auto it = objects.begin(); it != objects.end(); ++it) {
            if (!it.value().contains(BlueZ::PlayerIface)) continue;
            const QString p = it.key().path();
            if (p.startsWith(devicePath + QLatin1Char('/'))) { playerPath = p; break; }
            if (playerPath.isEmpty()) playerPath = p;
        }

        selectDevice(devicePath, deviceProps);
        selectPlayer(playerPath);
    });
}

void BluetoothManager::subscribe(const QString &path)
{
    if (path.isEmpty() || m_subscribed.contains(path)) return;
    m_subscribed.insert(path);
    m_bus.connect(BlueZ::Service, path, BlueZ::PropsIface,
                  QStringLiteral("PropertiesChanged"), this,
                  SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
}

void BluetoothManager::unsubscribeAll()
{
    for (const QString &path : m_subscribed)
        m_bus.disconnect(BlueZ::Service, path, BlueZ::PropsIface,
                         QStringLiteral("PropertiesChanged"), this,
                         SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
    m_subscribed.clear();
}

void BluetoothManager::selectDevice(const QString &path, const QVariantMap &props)
{
    m_devicePath = path;
    subscribe(path);

    if (!m_connected) {
        m_connected = true;
        emit connectedChanged();
        qInfo() << "[bt-media] connected:" << path;
    }
    applyDeviceProps(props);
}

void BluetoothManager::selectPlayer(const QString &path)
{
    m_playerPath = path;
    if (path.isEmpty()) return;

    subscribe(path);
    BlueZ::properties(this, path, BlueZ::PlayerIface,
                      [this](const QVariantMap &p) { applyPlayerProps(p); });
}

void BluetoothManager::clearDevice()
{
    unsubscribeAll();
    m_devicePath.clear();
    m_playerPath.clear();

    const bool wasConnected = m_connected;
    m_connected = false;

    // Clear unconditionally. The old code gated this on deviceName being
    // non-empty, so a device that never reported a name left stale track and
    // status text on screen after it disconnected.
    if (!m_deviceName.isEmpty() || !m_deviceAddress.isEmpty()) {
        m_deviceName.clear();
        m_deviceAddress.clear();
        emit deviceNameChanged();
        emit deviceAddressChanged();
    }
    if (!m_trackTitle.isEmpty() || !m_trackArtist.isEmpty() || !m_trackAlbum.isEmpty()) {
        m_trackTitle.clear();
        m_trackArtist.clear();
        m_trackAlbum.clear();
        emit trackInfoChanged();
    }
    if (!m_playerStatus.isEmpty()) {
        m_playerStatus.clear();
        emit playerStatusChanged();
    }
    if (wasConnected) {
        emit connectedChanged();
        qInfo() << "[bt-media] disconnected";
    }
}

void BluetoothManager::applyDeviceProps(const QVariantMap &props)
{
    const QString name = props.value(QStringLiteral("Alias"),
                         props.value(QStringLiteral("Name"))).toString();
    const QString addr = props.value(QStringLiteral("Address")).toString();

    if (!name.isEmpty() && name != m_deviceName) {
        m_deviceName = name;
        emit deviceNameChanged();
    }
    if (!addr.isEmpty() && addr != m_deviceAddress) {
        m_deviceAddress = addr;
        emit deviceAddressChanged();
    }
}

void BluetoothManager::applyPlayerProps(const QVariantMap &props)
{
    if (props.contains(QStringLiteral("Status"))) {
        const QString status = props.value(QStringLiteral("Status")).toString();
        if (status != m_playerStatus) {
            m_playerStatus = status;
            emit playerStatusChanged();
        }
    }

    if (props.contains(QStringLiteral("Track"))) {
        const QVariantMap track = BlueZ::toVariantMap(props.value(QStringLiteral("Track")));
        const QString title  = track.value(QStringLiteral("Title")).toString();
        const QString artist = track.value(QStringLiteral("Artist")).toString();
        const QString album  = track.value(QStringLiteral("Album")).toString();

        if (title != m_trackTitle || artist != m_trackArtist || album != m_trackAlbum) {
            m_trackTitle  = title;
            m_trackArtist = artist;
            m_trackAlbum  = album;
            emit trackInfoChanged();
        }
    }
}

void BluetoothManager::onPropertiesChanged(const QString &interface,
                                           const QVariantMap &changed,
                                           const QStringList &invalidated)
{
    Q_UNUSED(invalidated)

    if (interface == BlueZ::PlayerIface) {
        applyPlayerProps(changed);
        return;
    }

    if (interface == BlueZ::DeviceIface) {
        if (changed.contains(QStringLiteral("Connected"))
            && !changed.value(QStringLiteral("Connected")).toBool()) {
            // Our device dropped — re-evaluate in case another phone is still on.
            rescan();
            return;
        }
        applyDeviceProps(changed);
    }
}

void BluetoothManager::onInterfacesAdded(const QDBusObjectPath &path,
                                         const QVariantMap &interfaces)
{
    // A MediaPlayer1 appears when the phone starts playing; a Device1 when a new
    // phone connects. Either changes what we should be showing.
    if (interfaces.contains(BlueZ::PlayerIface)) {
        if (m_playerPath.isEmpty()) selectPlayer(path.path());
        return;
    }
    if (interfaces.contains(BlueZ::DeviceIface))
        rescan();
}

void BluetoothManager::onInterfacesRemoved(const QDBusObjectPath &path,
                                           const QStringList &interfaces)
{
    const QString p = path.path();

    if (interfaces.contains(BlueZ::PlayerIface) && p == m_playerPath) {
        m_playerPath.clear();
        if (!m_playerStatus.isEmpty()) {
            m_playerStatus.clear();
            emit playerStatusChanged();
        }
        if (!m_trackTitle.isEmpty() || !m_trackArtist.isEmpty() || !m_trackAlbum.isEmpty()) {
            m_trackTitle.clear();
            m_trackArtist.clear();
            m_trackAlbum.clear();
            emit trackInfoChanged();
        }
        return;
    }

    if (interfaces.contains(BlueZ::DeviceIface) && p == m_devicePath)
        rescan();
}

void BluetoothManager::onBlueZOwnerChanged(const QString &name, const QString &oldOwner,
                                           const QString &newOwner)
{
    Q_UNUSED(oldOwner)
    if (name != BlueZ::Service) return;

    if (newOwner.isEmpty()) clearDevice();
    else                    rescan();
}

// ---------------------------------------------------------------- AVRCP -----

void BluetoothManager::sendAvrcpCommand(const QString& command)
{
    if (m_playerPath.isEmpty()) {
        emit errorOccurred(QStringLiteral("No media player - play a song on your phone first"));
        return;
    }

    BlueZ::callMethod(this, m_playerPath, BlueZ::PlayerIface, command, {},
                      [this](const QString &error) {
        if (!error.isEmpty())
            emit errorOccurred(QStringLiteral("AVRCP failed: ") + error);
    });
}

void BluetoothManager::play()     { sendAvrcpCommand(QStringLiteral("Play"));     }
void BluetoothManager::pause()    { sendAvrcpCommand(QStringLiteral("Pause"));    }
void BluetoothManager::next()     { sendAvrcpCommand(QStringLiteral("Next"));     }
void BluetoothManager::previous() { sendAvrcpCommand(QStringLiteral("Previous")); }
void BluetoothManager::stop()     { sendAvrcpCommand(QStringLiteral("Stop"));     }
