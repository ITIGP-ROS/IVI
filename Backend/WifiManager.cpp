#include "WifiManager.hpp"
#include <QDBusReply>
#include <QDBusMetaType>
#include <QSet>

WifiManager::WifiManager(QObject *parent) : QObject(parent)
{
    m_nmInterface = new QDBusInterface(
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
        QDBusConnection::systemBus(),
        this
    );

    qDBusRegisterMetaType<NMConnectionSettings>();

    // Read initial Wi-Fi enabled state
    QVariant val = m_nmInterface->property("WirelessEnabled");
    if (val.isValid())
        m_wifiEnabled = val.toBool();

    // Subscribe to PropertiesChanged — catches toggles from outside the app
    QDBusConnection::systemBus().connect(
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.DBus.Properties",
        "PropertiesChanged",
        this,
        SLOT(onPropertiesChanged(QString, QVariantMap, QStringList))
    );

    // Read which network is currently connected at startup
    updateConnectedSsid();
}

// Getters 
bool WifiManager::wifiEnabled() const
{
    return m_wifiEnabled;
}

// Toggle Wi-Fi 
void WifiManager::setWifiEnabled(bool enabled)
{
    if (m_wifiEnabled == enabled) return;
    m_nmInterface->setProperty("WirelessEnabled", QVariant::fromValue(enabled));
}

// Slot: system property changed 
void WifiManager::onPropertiesChanged(QString interface,
                                      QVariantMap changedProps,
                                      QStringList invalidatedProps)
{
    Q_UNUSED(interface)
    Q_UNUSED(invalidatedProps)

    if (changedProps.contains("WirelessEnabled")) {
        m_wifiEnabled = changedProps["WirelessEnabled"].toBool();
        emit wifiEnabledChanged(m_wifiEnabled);
    }

    // Active connections changed — refresh connected SSID
    if (changedProps.contains("ActiveConnections")) {
        updateConnectedSsid();
    }
}

// Read currently connected SSID from NetworkManager
void WifiManager::updateConnectedSsid()
{
    QVariant activeConnsVar = m_nmInterface->property("ActiveConnections");
    if (!activeConnsVar.isValid()) {
        m_connectedSsid = "";
        emit connectedSsidChanged(m_connectedSsid);
        return;
    }

    const QList<QDBusObjectPath> activeConns =
        activeConnsVar.value<QList<QDBusObjectPath>>();

    for (const QDBusObjectPath &acPath : activeConns) {
        QDBusInterface acIface(
            "org.freedesktop.NetworkManager",
            acPath.path(),
            "org.freedesktop.NetworkManager.Connection.Active",
            QDBusConnection::systemBus()
        );

        if (acIface.property("Type").toString() != "802-11-wireless") continue;

        QDBusObjectPath connPath =
            acIface.property("Connection").value<QDBusObjectPath>();

        QDBusInterface connIface(
            "org.freedesktop.NetworkManager",
            connPath.path(),
            "org.freedesktop.NetworkManager.Settings.Connection",
            QDBusConnection::systemBus()
        );

        QDBusReply<NMConnectionSettings> settings = connIface.call("GetSettings");
        if (!settings.isValid()) continue;

        QByteArray ssidBytes = settings.value()
            .value("802-11-wireless")
            .value("ssid")
            .toByteArray();

        QString ssid = QString::fromUtf8(ssidBytes);
        if (!ssid.isEmpty()) {
            if (m_connectedSsid != ssid) {
                m_connectedSsid = ssid;
                emit connectedSsidChanged(m_connectedSsid);
            }
            return;
        }
    }

    // No active Wi-Fi connection
    if (!m_connectedSsid.isEmpty()) {
        m_connectedSsid = "";
        emit connectedSsidChanged(m_connectedSsid);
    }
}

// Disconnect from current active Wi-Fi connection
void WifiManager::disconnectFromNetwork()
{
    QVariant activeConnsVar = m_nmInterface->property("ActiveConnections");
    if (!activeConnsVar.isValid()) return;

    const QList<QDBusObjectPath> activeConns =
        activeConnsVar.value<QList<QDBusObjectPath>>();

    for (const QDBusObjectPath &acPath : activeConns) {
        QDBusInterface acIface(
            "org.freedesktop.NetworkManager",
            acPath.path(),
            "org.freedesktop.NetworkManager.Connection.Active",
            QDBusConnection::systemBus()
        );

        if (acIface.property("Type").toString() != "802-11-wireless") continue;

        QDBusMessage reply = m_nmInterface->call(
            "DeactivateConnection",
            QVariant::fromValue(acPath)
        );

        if (reply.type() == QDBusMessage::ErrorMessage)
            qWarning() << "Disconnect failed:" << reply.errorMessage();

        return;
    }
}

// Scan for nearby networks
void WifiManager::scanNetworks()
{
    emit scanStarted();

    QDBusReply<QList<QDBusObjectPath>> devicesReply =
        m_nmInterface->call("GetDevices");

    if (!devicesReply.isValid()) {
        emit scanFailed("Cannot get devices: " + devicesReply.error().message());
        return;
    }

    QString wirelessDevicePath;
    for (const QDBusObjectPath &path : devicesReply.value()) {
        QDBusInterface devIface(
            "org.freedesktop.NetworkManager",
            path.path(),
            "org.freedesktop.NetworkManager.Device",
            QDBusConnection::systemBus()
        );
        if (devIface.property("DeviceType").toUInt() == 2) {
            wirelessDevicePath = path.path();
            break;
        }
    }

    if (wirelessDevicePath.isEmpty()) {
        emit scanFailed("No wireless device found on this machine");
        return;
    }

    QDBusInterface deviceIface(
        "org.freedesktop.NetworkManager",
        wirelessDevicePath,
        "org.freedesktop.NetworkManager.Device.Wireless",
        QDBusConnection::systemBus()
    );

    QDBusReply<void> scanReply = deviceIface.call("RequestScan", QVariantMap());
    if (!scanReply.isValid()) {
        emit scanFailed(scanReply.error().message());
        return;
    }

    // Collect access points — deduplicate by SSID
    QStringList networks;
    QSet<QString> seen;

    QDBusReply<QList<QDBusObjectPath>> apReply =
        deviceIface.call("GetAllAccessPoints");

    if (apReply.isValid()) {
        for (const QDBusObjectPath &apPath : apReply.value()) {
            QDBusInterface apIface(
                "org.freedesktop.NetworkManager",
                apPath.path(),
                "org.freedesktop.NetworkManager.AccessPoint",
                QDBusConnection::systemBus()
            );

            QByteArray ssidBytes = apIface.property("Ssid").toByteArray();
            QString ssid = QString::fromUtf8(ssidBytes).trimmed();

            if (ssid.isEmpty()) continue;       // skip hidden networks
            if (seen.contains(ssid)) continue;  // skip duplicate BSSIDs

            seen.insert(ssid);
            networks << ssid;
        }
    }

    emit scanFinished(networks);
}

// Connect to a network — check saved profiles first
void WifiManager::connectToNetwork(const QString &ssid, const QString &password)
{
    if (ssid.isEmpty()) {
        emit connectFailed("SSID cannot be empty");
        return;
    }

    // Check if a saved profile already exists — avoid creating duplicates
    QDBusInterface settingsIface(
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager/Settings",
        "org.freedesktop.NetworkManager.Settings",
        QDBusConnection::systemBus()
    );

    QDBusReply<QList<QDBusObjectPath>> connList =
        settingsIface.call("ListConnections");

    if (connList.isValid()) {
        for (const QDBusObjectPath &connPath : connList.value()) {
            QDBusInterface connIface(
                "org.freedesktop.NetworkManager",
                connPath.path(),
                "org.freedesktop.NetworkManager.Settings.Connection",
                QDBusConnection::systemBus()
            );

            QDBusReply<NMConnectionSettings> settings =
                connIface.call("GetSettings");
            if (!settings.isValid()) continue;

            QByteArray profileSsidBytes = settings.value()
                .value("802-11-wireless")
                .value("ssid")
                .toByteArray();

            QString profileSsid = QString::fromUtf8(profileSsidBytes);

            if (profileSsid == ssid) {
                // Profile exists — activate it without creating a new one
                QDBusMessage reply = m_nmInterface->call(
                    "ActivateConnection",
                    QVariant::fromValue(connPath),
                    QVariant::fromValue(QDBusObjectPath("/")),
                    QVariant::fromValue(QDBusObjectPath("/"))
                );
                if (reply.type() == QDBusMessage::ErrorMessage) {
                    emit connectFailed(reply.errorMessage());
                    return;
                }
                QDBusObjectPath activeConnPath =
                    reply.arguments().at(0).value<QDBusObjectPath>();
                watchActiveConnection(activeConnPath.path(), ssid);
                return;
            }
        }
    }

    // No saved profile — create new connection
    QVariantMap connectionSettings;
    connectionSettings["type"] = "802-11-wireless";
    connectionSettings["id"]   = ssid;

    QVariantMap wirelessSettings;
    wirelessSettings["ssid"]   = ssid.toUtf8();
    wirelessSettings["mode"]   = "infrastructure";
    wirelessSettings["hidden"] = true;

    QVariantMap securitySettings;
    securitySettings["key-mgmt"] = "wpa-psk";
    securitySettings["psk"]      = password;

    NMConnectionSettings allSettings;
    allSettings["connection"]               = connectionSettings;
    allSettings["802-11-wireless"]          = wirelessSettings;
    allSettings["802-11-wireless-security"] = securitySettings;

    QDBusMessage reply = m_nmInterface->call(
        "AddAndActivateConnection",
        QVariant::fromValue(allSettings),
        QVariant::fromValue(QDBusObjectPath("/")),
        QVariant::fromValue(QDBusObjectPath("/"))
    );

    if (reply.type() == QDBusMessage::ErrorMessage) {
        emit connectFailed(reply.errorMessage());
        return;
    }

    QDBusObjectPath activeConnPath =
        reply.arguments().at(1).value<QDBusObjectPath>();
    watchActiveConnection(activeConnPath.path(), ssid);
}

// Connect to a network from scan results
void WifiManager::connectToSelectedNetwork(const QString &ssid)
{
    QDBusInterface settingsIface(
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager/Settings",
        "org.freedesktop.NetworkManager.Settings",
        QDBusConnection::systemBus()
    );

    QDBusReply<QList<QDBusObjectPath>> connList =
        settingsIface.call("ListConnections");

    if (connList.isValid()) {
        for (const QDBusObjectPath &connPath : connList.value()) {
            QDBusInterface connIface(
                "org.freedesktop.NetworkManager",
                connPath.path(),
                "org.freedesktop.NetworkManager.Settings.Connection",
                QDBusConnection::systemBus()
            );

            QDBusReply<NMConnectionSettings> settings =
                connIface.call("GetSettings");
            if (!settings.isValid()) continue;

            QByteArray profileSsidBytes = settings.value()
                .value("802-11-wireless")
                .value("ssid")
                .toByteArray();

            if (QString::fromUtf8(profileSsidBytes) == ssid) {
                QDBusMessage reply = m_nmInterface->call(
                    "ActivateConnection",
                    QVariant::fromValue(connPath),
                    QVariant::fromValue(QDBusObjectPath("/")),
                    QVariant::fromValue(QDBusObjectPath("/"))
                );
                if (reply.type() == QDBusMessage::ErrorMessage) {
                    emit connectFailed(reply.errorMessage());
                    return;
                }
                QDBusObjectPath activeConnPath =
                    reply.arguments().at(0).value<QDBusObjectPath>();
                watchActiveConnection(activeConnPath.path(), ssid);
                return;
            }
        }
    }

    // No saved profile — ask for password
    emit passwordRequired(ssid);
}

// Watch active connection state changes
void WifiManager::watchActiveConnection(const QString &activeConnPath,
                                        const QString &ssid)
{
    m_pendingSsid    = ssid;
    m_activeConnPath = activeConnPath;

    QDBusConnection::systemBus().connect(
        "org.freedesktop.NetworkManager",
        activeConnPath,
        "org.freedesktop.DBus.Properties",
        "PropertiesChanged",
        this,
        SLOT(onActiveConnPropertiesChanged(QString, QVariantMap, QStringList))
    );
}

// Slot: active connection state changed
void WifiManager::onActiveConnPropertiesChanged(QString interface,
                                                QVariantMap changedProps,
                                                QStringList invalidatedProps)
{
    Q_UNUSED(interface)
    Q_UNUSED(invalidatedProps)

    if (!changedProps.contains("State")) return;

    uint state = changedProps["State"].toUInt();

    switch (state) {
        case 2: // Activated
            emit connectSuccess(m_pendingSsid);
            updateConnectedSsid();
            QDBusConnection::systemBus().disconnect(
                "org.freedesktop.NetworkManager",
                m_activeConnPath,
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                this,
                SLOT(onActiveConnPropertiesChanged(QString, QVariantMap, QStringList))
            );
            break;

        case 4: // Deactivated = failed
            // Delete the bad profile so next attempt asks for password again
            forgetNetwork(m_pendingSsid);
            emit connectFailed("Wrong password or could not connect to: " + m_pendingSsid);
            updateConnectedSsid();
            QDBusConnection::systemBus().disconnect(
                "org.freedesktop.NetworkManager",
                m_activeConnPath,
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                this,
                SLOT(onActiveConnPropertiesChanged(QString, QMetaType::QVariantMap, QStringList))
            );
            break;

        default:
            break;
    }
}

void WifiManager::forgetNetwork(const QString &ssid)
{
    QDBusInterface settingsIface(
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager/Settings",
        "org.freedesktop.NetworkManager.Settings",
        QDBusConnection::systemBus()
    );

    QDBusReply<QList<QDBusObjectPath>> connList =
        settingsIface.call("ListConnections");

    if (!connList.isValid()) return;

    for (const QDBusObjectPath &connPath : connList.value()) {
        QDBusInterface connIface(
            "org.freedesktop.NetworkManager",
            connPath.path(),
            "org.freedesktop.NetworkManager.Settings.Connection",
            QDBusConnection::systemBus()
        );

        QDBusReply<NMConnectionSettings> settings = connIface.call("GetSettings");
        if (!settings.isValid()) continue;

        QByteArray profileSsidBytes = settings.value()
            .value("802-11-wireless")
            .value("ssid")
            .toByteArray();

        if (QString::fromUtf8(profileSsidBytes) == ssid) {
            QDBusMessage reply = connIface.call("Delete");
            if (reply.type() != QDBusMessage::ErrorMessage)
                emit forgetSuccess(ssid);
            return;
        }
    }
}
