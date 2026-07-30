#include "BluetoothHWManager.hpp"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusReply>
#include <QDBusVariant>
#include <QTimer>
#include <QPointer>
#include <QDebug>

// How long discovery runs per scan request. Inquiry starves the ACL link, so a
// head unit must not leave it on: continuous discovery audibly breaks up A2DP.
static constexpr int kDiscoveryWindowMs = 6000;
// Weak, far-away devices are noise in a car. -100 dBm is the floor.
static constexpr short kRssiThreshold = -90;
// Pairing needs a human on the phone; connecting should not take this long.
static constexpr int kPairTimeoutMs    = 60000;
static constexpr int kConnectTimeoutMs = 20000;

BluetoothHWManager::BluetoothHWManager(QObject *parent) : QObject(parent)
{
    BlueZ::registerTypes();

    m_agent = new BluetoothAgent(this);
    connect(m_agent, &BluetoothAgent::confirmationRequested, this,
            [this](const QString &devicePath, uint passkey) {
        BlueZ::properties(this, devicePath, BlueZ::DeviceIface,
                          [this, passkey](const QVariantMap &props) {
            const QString name = props.value(QStringLiteral("Name"),
                                             props.value(QStringLiteral("Alias"),
                                                         QStringLiteral("Unknown"))).toString();
            m_pendingConfirmName = name;
            emit pairingConfirmationRequested(name, passkey);
        });
    });
    connect(m_agent, &BluetoothAgent::cancelled, this,
            [this]() { emit pairingPromptDismissed(); });

    // Keep the connected set in step with the signal the rest of the app
    // already listens to, rather than duplicating the bookkeeping at each of
    // the places that can change it.
    connect(this, &BluetoothHWManager::deviceConnectionChanged,
            this, &BluetoothHWManager::noteConnectionChanged);

    // BlueZ may not be up yet when the HMI starts — a real race on a vehicle
    // where everything boots in parallel. Watch the name so a late bluetoothd
    // (or a restart of it) is picked up instead of leaving Bluetooth dead.
    QDBusConnection::systemBus().connect(
        QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/org/freedesktop/DBus"),
        QStringLiteral("org.freedesktop.DBus"), QStringLiteral("NameOwnerChanged"),
        QStringList{ BlueZ::Service }, QString(),
        this, SLOT(onBlueZOwnerChanged(QString, QString, QString)));

    QDBusConnection::systemBus().connect(
        BlueZ::Service, BlueZ::Root, BlueZ::ObjMgrIface, QStringLiteral("InterfacesAdded"),
        this, SLOT(onInterfacesAdded(QDBusObjectPath, QVariantMap)));

    QDBusConnection::systemBus().connect(
        BlueZ::Service, BlueZ::Root, BlueZ::ObjMgrIface, QStringLiteral("InterfacesRemoved"),
        this, SLOT(onInterfacesRemoved(QDBusObjectPath, QStringList)));

    m_discoveryTimer = new QTimer(this);
    m_discoveryTimer->setSingleShot(true);
    connect(m_discoveryTimer, &QTimer::timeout, this,
            [this]() { collectScanResults(); });

    m_powerVerifyTimer = new QTimer(this);
    m_powerVerifyTimer->setSingleShot(true);
    connect(m_powerVerifyTimer, &QTimer::timeout, this, [this]() {
        if (m_bluetoothEnabled == m_powerRequested) return;   // it landed

        // The Set was accepted but the adapter never changed state. On Linux
        // that is almost always an rfkill soft-block; the daemon reports no
        // error, so without this check the toggle just does nothing forever.
        const QString reason = m_powerRequested
            ? QStringLiteral("Bluetooth is blocked by the system (rfkill)")
            : QStringLiteral("Adapter did not power off");
        qWarning() << "[bt]" << reason;
        emit powerChangeFailed(reason);
        emit bluetoothEnabledChanged(m_bluetoothEnabled);   // snap UI back
    });

    // Deferred: signals emitted straight from a constructor reach nobody, because
    // QML has not connected to us yet. This runs once the event loop starts.
    QTimer::singleShot(0, this, [this]() { bootstrap(); });
}

BluetoothHWManager::~BluetoothHWManager()
{
    if (m_discovering && !m_adapterPath.isEmpty()) {
        QDBusMessage msg = QDBusMessage::createMethodCall(
            BlueZ::Service, m_adapterPath, BlueZ::AdapterIface, QStringLiteral("StopDiscovery"));
        QDBusConnection::systemBus().call(msg, QDBus::NoBlock);
    }
    if (m_agent) m_agent->unregister();
}

// ------------------------------------------------------------- bootstrap ---

void BluetoothHWManager::bootstrap()
{
    BlueZ::managedObjects(this, [this](const DBusManagedObjects &objects) {
        QString adapter;
        QVariantMap adapterProps;

        for (auto it = objects.begin(); it != objects.end(); ++it) {
            const DBusInterfaceMap &ifaces = it.value();
            // Enumerate rather than assuming hci0/hci1 — the adapter index is
            // not stable across boots when USB dongles are involved.
            if (adapter.isEmpty() && ifaces.contains(BlueZ::AdapterIface)) {
                adapter      = it.key().path();
                adapterProps = ifaces.value(BlueZ::AdapterIface);
            }
            if (ifaces.contains(BlueZ::DeviceIface))
                trackDevice(it.key().path(), ifaces.value(BlueZ::DeviceIface));
        }

        if (adapter.isEmpty()) {
            qWarning() << "[bt] no adapter yet — waiting for InterfacesAdded";
            return;
        }
        adoptAdapter(adapter, adapterProps);
    });
}

void BluetoothHWManager::adoptAdapter(const QString &path, const QVariantMap &props)
{
    if (m_adapterPath == path) return;
    m_adapterPath = path;

    QDBusConnection::systemBus().connect(
        BlueZ::Service, m_adapterPath, BlueZ::PropsIface, QStringLiteral("PropertiesChanged"),
        this, SLOT(onAdapterPropertiesChanged(QString, QVariantMap, QStringList)));

    const bool powered = props.value(QStringLiteral("Powered"), false).toBool();
    if (m_bluetoothEnabled != powered) {
        m_bluetoothEnabled = powered;
        emit bluetoothEnabledChanged(m_bluetoothEnabled);
    }
    setDiscovering(props.value(QStringLiteral("Discovering"), false).toBool());

    qInfo() << "[bt] adapter" << m_adapterPath << "powered:" << powered;
    emit adapterPresentChanged(true);

    m_agent->registerWith(this);
}

void BluetoothHWManager::releaseAdapter()
{
    if (m_adapterPath.isEmpty()) return;

    QDBusConnection::systemBus().disconnect(
        BlueZ::Service, m_adapterPath, BlueZ::PropsIface, QStringLiteral("PropertiesChanged"),
        this, SLOT(onAdapterPropertiesChanged(QString, QVariantMap, QStringList)));

    m_adapterPath.clear();
    setDiscovering(false);

    // No adapter means nothing is connected, whether or not BlueZ got around to
    // removing the device interfaces first.
    if (anyDeviceConnected()) {
        m_connectedAddresses.clear();
        emit anyDeviceConnectedChanged(false);
    }

    if (m_bluetoothEnabled) {
        m_bluetoothEnabled = false;
        emit bluetoothEnabledChanged(false);
    }
    emit adapterPresentChanged(false);
    qWarning() << "[bt] adapter removed";
}

void BluetoothHWManager::onBlueZOwnerChanged(const QString &name, const QString &oldOwner,
                                             const QString &newOwner)
{
    Q_UNUSED(oldOwner)
    if (name != BlueZ::Service) return;

    if (newOwner.isEmpty()) {
        qWarning() << "[bt] bluetoothd went away";
        for (const QString &path : m_watchers.keys())
            untrackDevice(path);
        releaseAdapter();
    } else {
        qInfo() << "[bt] bluetoothd available — re-bootstrapping";
        bootstrap();
    }
}

// ---------------------------------------------------------- device churn ---

void BluetoothHWManager::noteConnectionChanged(const QString &address, bool connected)
{
    const bool was = anyDeviceConnected();

    if (connected)
        m_connectedAddresses.insert(address);
    else
        m_connectedAddresses.remove(address);

    if (anyDeviceConnected() != was) {
        qInfo() << "[bt] any device connected:" << anyDeviceConnected();
        emit anyDeviceConnectedChanged(anyDeviceConnected());
    }
}

void BluetoothHWManager::trackDevice(const QString &path, const QVariantMap &props)
{
    const QString address = props.value(QStringLiteral("Address")).toString();
    if (address.isEmpty() || m_watchers.contains(path)) return;

    auto *watcher = new DeviceWatcher(path, address, this);
    connect(watcher, &DeviceWatcher::connectionChanged,
            this, &BluetoothHWManager::deviceConnectionChanged);
    connect(watcher, &DeviceWatcher::pairedChanged,
            this, &BluetoothHWManager::devicePairedChanged);

    QDBusConnection::systemBus().connect(
        BlueZ::Service, path, BlueZ::PropsIface, QStringLiteral("PropertiesChanged"),
        watcher,
        SLOT(onPropertiesChanged(const QString&, const QVariantMap&, const QStringList&)));

    m_watchers.insert(path, watcher);
    m_addressToPath.insert(address, path);

    if (props.value(QStringLiteral("Connected"), false).toBool())
        emit deviceConnectionChanged(address, true);
}

void BluetoothHWManager::untrackDevice(const QString &path)
{
    DeviceWatcher *watcher = m_watchers.take(path);
    if (!watcher) return;

    QDBusConnection::systemBus().disconnect(
        BlueZ::Service, path, BlueZ::PropsIface, QStringLiteral("PropertiesChanged"),
        watcher,
        SLOT(onPropertiesChanged(const QString&, const QVariantMap&, const QStringList&)));

    const QString address = watcher->address();
    if (m_addressToPath.value(address) == path)
        m_addressToPath.remove(address);

    emit deviceConnectionChanged(address, false);
    watcher->deleteLater();
}

void BluetoothHWManager::onInterfacesAdded(const QDBusObjectPath &path,
                                           const QVariantMap &interfaces)
{
    // interfaces is a{sa{sv}}; Qt hands it to us as a QVariantMap of
    // interface-name -> (nested) property map.
    for (auto it = interfaces.begin(); it != interfaces.end(); ++it) {
        if (it.key() == BlueZ::DeviceIface)
            trackDevice(path.path(), BlueZ::toVariantMap(it.value()));
        else if (it.key() == BlueZ::AdapterIface && m_adapterPath.isEmpty())
            adoptAdapter(path.path(), BlueZ::toVariantMap(it.value()));
    }
}

void BluetoothHWManager::onInterfacesRemoved(const QDBusObjectPath &path,
                                             const QStringList &interfaces)
{
    if (interfaces.contains(BlueZ::DeviceIface))
        untrackDevice(path.path());
    if (interfaces.contains(BlueZ::AdapterIface) && path.path() == m_adapterPath)
        releaseAdapter();
}

// Resolve an address to its object path. Uses the cache when possible and falls
// back to a single async ObjectManager query — never a blocking one.
void BluetoothHWManager::withDevicePath(const QString &address, QObject *ctx,
                                        std::function<void(const QString &)> cb)
{
    const QString cached = m_addressToPath.value(address);
    if (!cached.isEmpty()) { cb(cached); return; }

    BlueZ::managedObjects(ctx, [this, address, cb](const DBusManagedObjects &objects) {
        for (auto it = objects.begin(); it != objects.end(); ++it) {
            const DBusInterfaceMap &ifaces = it.value();
            if (!ifaces.contains(BlueZ::DeviceIface)) continue;
            if (ifaces.value(BlueZ::DeviceIface).value(QStringLiteral("Address")).toString()
                == address) {
                m_addressToPath.insert(address, it.key().path());
                cb(it.key().path());
                return;
            }
        }
        cb(QString());
    });
}

// -------------------------------------------------------------- power -------

void BluetoothHWManager::setBluetoothEnabled(bool enabled)
{
    if (m_adapterPath.isEmpty()) {
        qWarning() << "[bt] no adapter to power" << (enabled ? "on" : "off");
        return;
    }
    if (m_bluetoothEnabled == enabled) return;

    // Do not update m_bluetoothEnabled here — PropertiesChanged is the single
    // source of truth, so the UI can never show a state the adapter is not in.
    //
    // Report failures: an rfkill soft-block makes Set("Powered") fail, and
    // without this the toggle just springs back with no explanation.
    m_powerRequested = enabled;
    m_powerVerifyTimer->start(2500);

    BlueZ::callMethod(this, m_adapterPath, BlueZ::PropsIface, QStringLiteral("Set"),
                      { BlueZ::AdapterIface, QStringLiteral("Powered"),
                        QVariant::fromValue(QDBusVariant(enabled)) },
                      [this, enabled](const QString &error) {
        if (error.isEmpty()) return;   // verified by m_powerVerifyTimer
        m_powerVerifyTimer->stop();

        const bool blocked = error.contains(QStringLiteral("Blocked"), Qt::CaseInsensitive)
                          || error.contains(QStringLiteral("rfkill"), Qt::CaseInsensitive);
        const QString reason = blocked
            ? QStringLiteral("Bluetooth is blocked by the system (rfkill)")
            : error;

        qWarning() << "[bt] cannot power" << (enabled ? "on" : "off") << ":" << reason;
        emit powerChangeFailed(reason);

        // Snap the UI back to what the adapter actually is.
        emit bluetoothEnabledChanged(m_bluetoothEnabled);
    });
}

void BluetoothHWManager::onAdapterPropertiesChanged(QString interface,
                                                    QVariantMap changedProps,
                                                    QStringList invalidatedProps)
{
    Q_UNUSED(interface) Q_UNUSED(invalidatedProps)

    if (changedProps.contains(QStringLiteral("Powered"))) {
        m_bluetoothEnabled = changedProps.value(QStringLiteral("Powered")).toBool();
        if (m_powerVerifyTimer && m_bluetoothEnabled == m_powerRequested)
            m_powerVerifyTimer->stop();          // the request landed
        emit bluetoothEnabledChanged(m_bluetoothEnabled);
        if (!m_bluetoothEnabled) setDiscovering(false);
    }
    if (changedProps.contains(QStringLiteral("Discovering")))
        setDiscovering(changedProps.value(QStringLiteral("Discovering")).toBool());
}

void BluetoothHWManager::setDiscovering(bool on)
{
    if (m_discovering != on) {
        m_discovering = on;
        emit discoveringChanged(m_discovering);
    }

    // Invariant: the radio may only be inquiring while we hold an open scan
    // window. Anything else — a StopDiscovery that did not take, a window that
    // closed while a request was in flight, or discovery left over from a
    // previous run — is corrected here.
    //
    // This is the safety net for the bug where discovery stayed on
    // indefinitely: inquiry starves the ACL link and audibly breaks up A2DP,
    // so "eventually stops" is not good enough. If some other client owns the
    // discovery, our StopDiscovery simply fails and nothing is disturbed.
    if (on && !m_scanPending) {
        qWarning() << "[bt] discovery active outside a scan window — stopping";
        stopScan();
    }
}

void BluetoothHWManager::setMediaActive(bool active)
{
    if (m_mediaActive == active) return;
    m_mediaActive = active;

    // If audio starts mid-scan, cut the inquiry short rather than let it chew
    // through the rest of the window.
    if (active && m_scanPending) {
        qInfo() << "[bt] audio started — ending discovery early";
        if (m_discoveryTimer) m_discoveryTimer->stop();
        collectScanResults();
    }
}

// --------------------------------------------------------------- scan -------

void BluetoothHWManager::scanDevices()
{
    if (m_adapterPath.isEmpty()) { emit scanFailed(QStringLiteral("No Bluetooth adapter available")); return; }
    if (!m_bluetoothEnabled)     { emit scanFailed(QStringLiteral("Bluetooth is turned off")); return; }
    if (m_scanPending)           { return; }   // already inside a discovery window

    // Protect playback: an inquiry would break up whatever is streaming.
    if (m_mediaActive) {
        emit scanFailed(QStringLiteral("Not scanning while audio is playing"));
        return;
    }

    m_scanPending = true;
    emit scanStarted();

    // Filter at the daemon: drop far-away noise and restrict to classic BR/EDR,
    // which is what phones use for A2DP/HFP. Cuts both radio time and CPU.
    QVariantMap filter;
    filter[QStringLiteral("Transport")]    = QStringLiteral("bredr");
    filter[QStringLiteral("RSSI")]         = QVariant::fromValue(kRssiThreshold);
    filter[QStringLiteral("DuplicateData")] = false;

    BlueZ::callMethod(this, m_adapterPath, BlueZ::AdapterIface,
                      QStringLiteral("SetDiscoveryFilter"),
                      { filter },
                      [this](const QString &filterError) {
        // A filter failure is not fatal — fall through to an unfiltered scan.
        if (!filterError.isEmpty())
            qWarning() << "[bt] SetDiscoveryFilter failed:" << filterError;

        BlueZ::callMethod(this, m_adapterPath, BlueZ::AdapterIface,
                          QStringLiteral("StartDiscovery"), {},
                          [this](const QString &error) {
            if (!error.isEmpty() && !error.contains(QStringLiteral("InProgress"),
                                                    Qt::CaseInsensitive)) {
                m_scanPending = false;
                emit scanFailed(error);
                return;
            }
            // Bounded window, then stop the radio and report what we found.
            // Restarting the owned timer means repeated scan requests can never
            // stack up multiple pending stops.
            m_discoveryTimer->start(kDiscoveryWindowMs);
        });
    });
}

void BluetoothHWManager::stopScan()
{
    if (m_adapterPath.isEmpty()) return;
    BlueZ::callMethod(this, m_adapterPath, BlueZ::AdapterIface,
                      QStringLiteral("StopDiscovery"));
}

void BluetoothHWManager::collectScanResults()
{
    stopScan();

    BlueZ::managedObjects(this, [this](const DBusManagedObjects &objects) {
        m_scanPending = false;

        QVariantList devices;
        for (auto it = objects.begin(); it != objects.end(); ++it) {
            const DBusInterfaceMap &ifaces = it.value();
            if (!ifaces.contains(BlueZ::DeviceIface)) continue;

            const QVariantMap &p = ifaces.value(BlueZ::DeviceIface);
            const QString address = p.value(QStringLiteral("Address")).toString();
            if (address.isEmpty()) continue;

            trackDevice(it.key().path(), p);

            const bool paired = p.value(QStringLiteral("Paired"), false).toBool();
            const bool hasRssi = p.contains(QStringLiteral("RSSI"));

            // BlueZ caches every device it has ever seen. Showing all of them
            // means phantom entries for phones that left the car weeks ago —
            // so only surface what is paired (ours) or currently in range.
            if (!paired && !hasRssi) continue;

            QVariantMap d;
            d[QStringLiteral("name")]      = p.value(QStringLiteral("Alias"),
                                             p.value(QStringLiteral("Name"),
                                                     address)).toString();
            d[QStringLiteral("address")]   = address;
            d[QStringLiteral("paired")]    = paired;
            d[QStringLiteral("trusted")]   = p.value(QStringLiteral("Trusted"), false).toBool();
            d[QStringLiteral("connected")] = p.value(QStringLiteral("Connected"), false).toBool();
            d[QStringLiteral("rssi")]      = hasRssi ? p.value(QStringLiteral("RSSI")).toInt() : 0;
            d[QStringLiteral("icon")]      = p.value(QStringLiteral("Icon")).toString();
            devices << d;
        }

        // Deterministic order: paired first, then strongest signal.
        std::sort(devices.begin(), devices.end(),
                  [](const QVariant &a, const QVariant &b) {
            const QVariantMap ma = a.toMap(), mb = b.toMap();
            if (ma[QStringLiteral("paired")].toBool() != mb[QStringLiteral("paired")].toBool())
                return ma[QStringLiteral("paired")].toBool();
            return ma[QStringLiteral("rssi")].toInt() > mb[QStringLiteral("rssi")].toInt();
        });

        emit scanFinished(devices);
    });
}

// --------------------------------------------------------------- pair -------

void BluetoothHWManager::pairDevice(const QString &address)
{
    withDevicePath(address, this, [this, address](const QString &path) {
        if (path.isEmpty()) {
            emit pairFailed(QStringLiteral("Device not found: ") + address);
            return;
        }

        BlueZ::properties(this, path, BlueZ::DeviceIface,
                          [this, path, address](const QVariantMap &props) {
            const QString name = props.value(QStringLiteral("Alias"),
                                 props.value(QStringLiteral("Name"), address)).toString();

            if (props.value(QStringLiteral("Paired"), false).toBool()) {
                // Already paired — make sure it is trusted so it reconnects by itself.
                BlueZ::setProperty(path, BlueZ::DeviceIface, QStringLiteral("Trusted"), true);
                emit pairSuccess(name);
                return;
            }

            m_pendingPairAddress = address;

            // Async: Pair() legitimately blocks for as long as the driver takes to
            // confirm on the phone. A synchronous call here froze the whole HMI.
            QDBusMessage msg = QDBusMessage::createMethodCall(
                BlueZ::Service, path, BlueZ::DeviceIface, QStringLiteral("Pair"));
            QDBusPendingCall call =
                QDBusConnection::systemBus().asyncCall(msg, kPairTimeoutMs);
            auto *watcher = new QDBusPendingCallWatcher(call, this);

            connect(watcher, &QDBusPendingCallWatcher::finished, this,
                    [this, watcher, name, path, address]() {
                watcher->deleteLater();
                if (m_pendingPairAddress == address) m_pendingPairAddress.clear();

                QDBusMessage reply = watcher->reply();
                if (reply.type() == QDBusMessage::ErrorMessage) {
                    emit pairFailed(reply.errorMessage());
                    return;
                }

                // Trusted is what makes the phone reconnect on its own next time
                // the car starts. Without it every drive needs a manual connect.
                BlueZ::setProperty(path, BlueZ::DeviceIface, QStringLiteral("Trusted"), true);
                emit pairSuccess(name);
            });
        });
    });
}

void BluetoothHWManager::confirmPairing(bool accept)
{
    if (!m_agent->hasPending()) return;
    m_agent->resolvePending(accept);
    emit pairingPromptDismissed();
}

void BluetoothHWManager::removeDevice(const QString &address)
{
    if (m_adapterPath.isEmpty()) return;

    withDevicePath(address, this, [this, address](const QString &path) {
        if (path.isEmpty()) return;
        BlueZ::callMethod(this, m_adapterPath, BlueZ::AdapterIface,
                          QStringLiteral("RemoveDevice"),
                          { QVariant::fromValue(QDBusObjectPath(path)) },
                          [this, address](const QString &error) {
            if (error.isEmpty()) emit removeSuccess(address);
            else                 qWarning() << "[bt] RemoveDevice failed:" << error;
        });
    });
}

// ------------------------------------------------------- connect/disconnect --

void BluetoothHWManager::connectDevice(const QString &address)
{
    withDevicePath(address, this, [this, address](const QString &path) {
        if (path.isEmpty()) {
            emit connectFailed(QStringLiteral("Device not found: ") + address);
            return;
        }

        BlueZ::properties(this, path, BlueZ::DeviceIface,
                          [this, path, address](const QVariantMap &props) {
            const QString name = props.value(QStringLiteral("Alias"),
                                 props.value(QStringLiteral("Name"), address)).toString();

            QDBusMessage msg = QDBusMessage::createMethodCall(
                BlueZ::Service, path, BlueZ::DeviceIface, QStringLiteral("Connect"));
            QDBusPendingCall call =
                QDBusConnection::systemBus().asyncCall(msg, kConnectTimeoutMs);
            auto *watcher = new QDBusPendingCallWatcher(call, this);

            connect(watcher, &QDBusPendingCallWatcher::finished, this,
                    [this, watcher, name, path]() {
                watcher->deleteLater();
                QDBusMessage reply = watcher->reply();
                if (reply.type() == QDBusMessage::ErrorMessage) {
                    emit connectFailed(reply.errorMessage());
                    return;
                }
                BlueZ::setProperty(path, BlueZ::DeviceIface, QStringLiteral("Trusted"), true);
                emit connectSuccess(name);
            });
        });
    });
}

void BluetoothHWManager::disconnectDevice(const QString &address)
{
    withDevicePath(address, this, [this, address](const QString &path) {
        if (path.isEmpty()) {
            emit disconnectFailed(QStringLiteral("Device not found: ") + address);
            return;
        }

        BlueZ::properties(this, path, BlueZ::DeviceIface,
                          [this, path, address](const QVariantMap &props) {
            const QString name = props.value(QStringLiteral("Alias"),
                                 props.value(QStringLiteral("Name"), address)).toString();

            QDBusMessage msg = QDBusMessage::createMethodCall(
                BlueZ::Service, path, BlueZ::DeviceIface, QStringLiteral("Disconnect"));
            QDBusPendingCall call =
                QDBusConnection::systemBus().asyncCall(msg, kConnectTimeoutMs);
            auto *watcher = new QDBusPendingCallWatcher(call, this);

            connect(watcher, &QDBusPendingCallWatcher::finished, this,
                    [this, watcher, name]() {
                watcher->deleteLater();
                QDBusMessage reply = watcher->reply();
                if (reply.type() == QDBusMessage::ErrorMessage)
                    emit disconnectFailed(reply.errorMessage());
                else
                    emit disconnectSuccess(name);
            });
        });
    });
}
