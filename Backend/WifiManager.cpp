#include "WifiManager.hpp"
#include <QDBusReply>
#include <QDBusMetaType>
#include <QSet>
#include <QHash>
#include <QCryptographicHash>
#include <QFile>
#include <QSaveFile>
#include <QStandardPaths>
#include <QDebug>

namespace {
// can0 is brought up by systemd-networkd and ivi-app.service is not ordered
// against it, so a boot-time forward can lose that race. Six tries five
// seconds apart covers ~30 s of interface bring-up; past that the problem is
// not timing and repeating will not fix it.
constexpr int kForwardMaxAttempts = 6;
constexpr int kForwardRetryMs     = 5000;
} // namespace

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

    // Forwards credentials to the vehicle host over SecOC CAN after a successful
    // connect; re-emitted so QML only ever has to know about WifiManager.
    m_credSender = new WifiCredSender(this);
    connect(m_credSender, &WifiCredSender::sent,
            this, &WifiManager::credentialsSent);
    connect(m_credSender, &WifiCredSender::failed,
            this, &WifiManager::credentialsFailed);

    // A delivered send is what promotes the digest: until the ECUs have
    // actually been told, "already forwarded" must stay false or a failure at
    // boot would suppress every later attempt for the same network.
    connect(m_credSender, &WifiCredSender::sent, this, [this](const QString &) {
        m_lastSentFp = m_inFlightFp;
        m_inFlightFp.clear();
        m_forwardAttempts = 0;
        m_forwardRetry.stop();
        saveSentDigest();
    });
    connect(m_credSender, &WifiCredSender::failed, this, [this](const QString &reason) {
        m_inFlightFp.clear();
        if (m_forwardSsid.isEmpty())
            return;
        if (m_forwardAttempts >= kForwardMaxAttempts) {
            qWarning().noquote()
                << "[wifi] giving up forwarding credentials for" << m_forwardSsid
                << "after" << m_forwardAttempts << "attempts —" << reason
                << "| the ECUs are still on whatever network they were last told";
            m_forwardSsid.clear();
            return;
        }
        qInfo().noquote() << "[wifi] credential forward failed (" << reason
                          << ") — retry" << (m_forwardAttempts + 1) << "of"
                          << kForwardMaxAttempts << "in"
                          << (kForwardRetryMs / 1000) << "s";
        m_forwardRetry.start(kForwardRetryMs);
    });

    m_forwardRetry.setSingleShot(true);
    connect(&m_forwardRetry, &QTimer::timeout, this, &WifiManager::attemptForward);

    // Before the first scan below, so a restart within the same boot knows the
    // ECUs have already been told and does not repeat the handover.
    loadSentDigest();

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

    // Active connections changed — refresh connected SSID only when not connecting.
    // During a connection, the state=2 handler sets m_connectedSsid directly to
    // avoid racing with this signal path (which can fire before state=2 arrives).
    if (changedProps.contains("ActiveConnections") && m_pendingSsid.isEmpty()) {
        updateConnectedSsid();
    }
}

QString WifiManager::sentDigestPath() const
{
    // RuntimeLocation is XDG_RUNTIME_DIR, i.e. /run/user/1000 for the weston
    // user this runs as. On /run, so it is gone after a reboot and present
    // after a service restart — which is the entire point.
    const QString dir =
        QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    return dir.isEmpty() ? QString()
                         : dir + QStringLiteral("/ivi-wifi-cred-sent");
}

void WifiManager::loadSentDigest()
{
    const QString path = sentDigestPath();
    if (path.isEmpty()) {
        qWarning().noquote()
            << "[wifi] no runtime directory — credentials will be re-forwarded on"
               " every app start, not once per boot";
        return;
    }

    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return;                       // first run this boot; nothing to read

    m_lastSentFp = QByteArray::fromHex(f.readAll().trimmed());
    if (!m_lastSentFp.isEmpty())
        qInfo().noquote() << "[wifi] the ECUs were already given a network this"
                             " boot — not repeating it";
}

void WifiManager::saveSentDigest() const
{
    const QString path = sentDigestPath();
    if (path.isEmpty() || m_lastSentFp.isEmpty())
        return;

    // Hex, and only the digest: this file must never be somewhere a password
    // could end up. QSaveFile renames into place so a restart cannot read a
    // half-written one and conclude something different was sent.
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning().noquote() << "[wifi] cannot record the forwarded digest in"
                             << path << "-" << f.errorString();
        return;
    }
    f.write(m_lastSentFp.toHex());
    f.write("\n");
    if (!f.commit())
        qWarning().noquote() << "[wifi] could not save" << path
                             << "-" << f.errorString();
}

void WifiManager::forwardCredentials(const QString &ssid, const QDBusObjectPath &connPath)
{
    if (ssid.isEmpty() || connPath.path().isEmpty() || connPath.path() == "/")
        return;

    // Already working on this network. NetworkManager emits ActiveConnections
    // changes several times around a single connect, and letting each one reset
    // the attempt counter would turn a genuine failure into an endless retry.
    if (m_forwardSsid == ssid && (m_credSender->busy() || m_forwardRetry.isActive()))
        return;

    m_forwardSsid     = ssid;
    m_forwardConnPath = connPath;
    m_forwardAttempts = 0;
    m_forwardRetry.stop();
    attemptForward();
}

void WifiManager::attemptForward()
{
    if (m_forwardSsid.isEmpty())
        return;

    ++m_forwardAttempts;

    // Never hand the sender a request while one is out.
    //
    // It answers a concurrent send with failed("already in progress"), and that
    // failure would arrive on the bookkeeping of the send that is STILL RUNNING
    // — clearing m_inFlightFp, so the digest promoted when that one succeeded
    // would be empty and the dedupe below would never match again. Waiting is
    // both simpler and correct.
    if (m_credSender->busy()) {
        m_forwardRetry.start(kForwardRetryMs);
        return;
    }

    // Re-read the PSK on every attempt rather than holding it across the retry
    // window. It costs one D-Bus round trip and means no password lives in a
    // member between a failed send and the next one.
    QDBusInterface connIface(
        "org.freedesktop.NetworkManager",
        m_forwardConnPath.path(),
        "org.freedesktop.NetworkManager.Settings.Connection",
        QDBusConnection::systemBus()
    );

    QDBusReply<NMConnectionSettings> secrets =
        connIface.call("GetSecrets", "802-11-wireless-security");
    if (!secrets.isValid()) {
        // Not retried: a refusal here is a permissions answer, not a timing
        // one, and it will be the same answer in five seconds.
        qWarning().noquote() << "[wifi] cannot read saved PSK for" << m_forwardSsid
                             << "-" << secrets.error().message().trimmed()
                             << "| ECUs will not be told about this network";
        m_forwardSsid.clear();
        return;
    }

    const QString psk = secrets.value()
        .value("802-11-wireless-security")
        .value("psk")
        .toString();

    if (psk.isEmpty()) {
        // An open network, or one whose PSK NetworkManager does not store
        // (agent-owned secret flags). Nothing to hand over either way.
        qInfo().noquote() << "[wifi] no stored PSK for" << m_forwardSsid
                          << "— nothing to forward";
        m_forwardSsid.clear();
        return;
    }

    QCryptographicHash h(QCryptographicHash::Sha256);
    h.addData(m_forwardSsid.toUtf8());
    h.addData(QByteArrayLiteral("\0"));
    h.addData(psk.toUtf8());
    const QByteArray fp = h.result();

    if (fp == m_lastSentFp) {
        // Either we sent this already in this process, or a previous run did
        // and left the digest in /run. NetworkManager emits ActiveConnections
        // changes fairly freely, and a link that flaps would otherwise burn a
        // freshness counter per bounce — the receivers only accept
        // strictly-increasing values, so that is not free.
        qInfo().noquote() << "[wifi] ECUs already have" << m_forwardSsid
                          << "— not resending";
        m_forwardSsid.clear();
        return;
    }

    qInfo().noquote() << "[wifi] forwarding credentials for" << m_forwardSsid
                      << "to the ECUs (attempt" << m_forwardAttempts << ")";
    m_inFlightFp = fp;
    m_credSender->send(m_forwardSsid, psk);
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
            // Deliberately OUTSIDE the change check, and deliberately here
            // rather than only in the connect handler. This function runs at
            // construction and on every ActiveConnections change, which is the
            // only notice we get of a connection NetworkManager made on its
            // own — the boot auto-connect above all. The digest check inside
            // makes calling it repeatedly free.
            forwardCredentials(ssid, connPath);
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

        if (reply.type() == QDBusMessage::ErrorMessage) {
            qWarning() << "Disconnect failed:" << reply.errorMessage();
            return;
        }

        // Optimistically update UI immediately instead of waiting for NM async signal
        if (!m_connectedSsid.isEmpty()) {
            m_connectedSsid = "";
            emit connectedSsidChanged(m_connectedSsid);
        }
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
        m_wirelessDevicePath.clear();
        emit scanFailed("No wireless device found on this machine");
        return;
    }
    m_wirelessDevicePath = wirelessDevicePath;

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

    /*
     * Collect access points, one entry per SSID.
     *
     * Deduplication keeps the STRONGEST access point rather than the first one
     * NetworkManager happens to return. A mesh or a repeater publishes the same
     * SSID from several radios, and taking whichever came back first made the
     * signal icon show a distant node while the phone was sitting next to the
     * near one.
     */
    QVariantList networks;
    QHash<QString, int> indexOfSsid;

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

            const int strength = apIface.property("Strength").toInt();

            /*
             * Three separate flag words have to agree that the AP is open
             * before it can be called open. Flags carries the old PRIVACY bit
             * (WEP), WpaFlags and RsnFlags the WPA/WPA2/WPA3 key management —
             * a WPA2 network leaves PRIVACY set but a WPA3-only one need not,
             * so checking any single word mislabels somebody.
             */
            const uint apFlags  = apIface.property("Flags").toUInt();
            const uint wpaFlags = apIface.property("WpaFlags").toUInt();
            const uint rsnFlags = apIface.property("RsnFlags").toUInt();
            const bool secured  = (apFlags & 0x1u) || wpaFlags || rsnFlags;

            QVariantMap entry;
            entry["name"]     = ssid;
            entry["strength"] = strength;
            entry["secured"]  = secured;

            const auto known = indexOfSsid.constFind(ssid);
            if (known == indexOfSsid.constEnd()) {
                indexOfSsid.insert(ssid, networks.size());
                networks << entry;
            } else if (networks[*known].toMap().value("strength").toInt() < strength) {
                networks[*known] = entry;
            }
        }
    }

    emit scanFinished(networks);
}

// Connect to a broadcast network using a typed password
void WifiManager::connectToNetwork(const QString &ssid, const QString &password)
{
    connectWithSettings(ssid, password, /*hidden*/ false, /*open*/ false);
}

// Connect to a network that does not beacon its SSID. NM will only find it if
// 802-11-wireless.hidden is set, which makes it send directed probe requests.
void WifiManager::connectToHiddenNetwork(const QString &ssid, const QString &password,
                                         const QString &security)
{
    const bool open = (security.compare("open", Qt::CaseInsensitive) == 0);

    if (!open && password.length() < 8) {
        emit connectFailed("Password must be 8+ characters");
        return;
    }

    qInfo().noquote() << "[wifi] adding hidden network:" << ssid
                      << "security:" << (open ? "open" : "wpa-psk");
    connectWithSettings(ssid, password, /*hidden*/ true, open);
}

// Connect to a network — check saved profiles first
void WifiManager::connectWithSettings(const QString &ssid, const QString &password,
                                      bool hidden, bool open)
{
    if (ssid.isEmpty()) {
        emit connectFailed("SSID cannot be empty");
        return;
    }

    // The credential payload sent to the vehicle host is "SSID;PASSWORD", split
    // on the first ';' by the receiver — an SSID containing one cannot round-trip.
    if (ssid.contains(';')) {
        emit connectFailed("SSID must not contain ';'");
        return;
    }

    if (m_wirelessDevicePath.isEmpty()) {
        emit connectFailed("No wireless device available");
        return;
    }

    // Remember it for the vehicle-host handoff once activation succeeds. An open
    // network has nothing to hand over — the host script needs a passphrase.
    m_pendingPassword = open ? QString() : password;

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
                    QVariant::fromValue(QDBusObjectPath(m_wirelessDevicePath)),
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
    wirelessSettings["ssid"] = ssid.toUtf8();
    wirelessSettings["mode"] = "infrastructure";
    // Only for APs that don't beacon their SSID. Setting it unconditionally would
    // make the head unit broadcast every saved SSID in probe requests everywhere.
    if (hidden)
        wirelessSettings["hidden"] = true;

    NMConnectionSettings allSettings;
    allSettings["connection"]      = connectionSettings;
    allSettings["802-11-wireless"] = wirelessSettings;

    if (!open) {
        QVariantMap securitySettings;
        securitySettings["key-mgmt"] = "wpa-psk";
        securitySettings["psk"]      = password;
        allSettings["802-11-wireless-security"] = securitySettings;
    }

    QDBusMessage reply = m_nmInterface->call(
        "AddAndActivateConnection",
        QVariant::fromValue(allSettings),
        QVariant::fromValue(QDBusObjectPath(m_wirelessDevicePath)),
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
    if (m_wirelessDevicePath.isEmpty()) {
        emit connectFailed("No wireless device available");
        return;
    }

    // The password was never typed here; it is recovered from the saved profile
    // below so the vehicle host gets the credentials on every successful connect,
    // not only the first one.
    m_pendingPassword.clear();

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
                // Pull the stored PSK so it can be forwarded to the host on
                // success. Needs root (or a polkit grant); when it is refused
                // the connect still proceeds, just without the handoff.
                QDBusReply<NMConnectionSettings> secrets =
                    connIface.call("GetSecrets", "802-11-wireless-security");
                if (secrets.isValid()) {
                    m_pendingPassword = secrets.value()
                        .value("802-11-wireless-security")
                        .value("psk")
                        .toString();
                } else {
                    qWarning().noquote()
                        << "[wifi] could not read saved PSK for" << ssid
                        << "-" << secrets.error().message().trimmed();
                }

                QDBusMessage reply = m_nmInterface->call(
                    "ActivateConnection",
                    QVariant::fromValue(connPath),
                    QVariant::fromValue(QDBusObjectPath(m_wirelessDevicePath)),
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
    // Disconnect previous watcher to prevent stale signals from overlapping connections
    if (!m_activeConnPath.isEmpty()) {
        QDBusConnection::systemBus().disconnect(
            "org.freedesktop.NetworkManager",
            m_activeConnPath,
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            this,
            SLOT(onActiveConnPropertiesChanged(QString, QVariantMap, QStringList))
        );
    }

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
            // Set directly from m_pendingSsid to avoid racing with the
            // ActiveConnections D-Bus signal (which can fire before this slot)
            if (m_connectedSsid != m_pendingSsid) {
                m_connectedSsid = m_pendingSsid;
                emit connectedSsidChanged(m_connectedSsid);
            }
            // Hand the credentials to the ECUs over SecOC CAN.
            //
            // Resolved from NetworkManager rather than from the password the
            // user just typed, so this path and the auto-connect path are the
            // same code reading the same source. m_pendingPassword is still
            // what BUILDS the profile; it is no longer what forwards it.
            qInfo().noquote() << "[wifi] connected to:" << m_pendingSsid;
            {
                QDBusInterface acIface(
                    "org.freedesktop.NetworkManager",
                    m_activeConnPath,
                    "org.freedesktop.NetworkManager.Connection.Active",
                    QDBusConnection::systemBus()
                );
                forwardCredentials(m_pendingSsid,
                                   acIface.property("Connection").value<QDBusObjectPath>());
            }
            m_pendingPassword.clear();
            m_pendingSsid.clear();
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
            m_pendingPassword.clear();   // never forward a credential the AP rejected
            m_pendingSsid.clear();
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
