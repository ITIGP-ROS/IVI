#pragma once
#include <QObject>
#include <QDBusObjectPath>
#include <QHash>
#include <QTimer>
#include <QVariantList>
#include "BlueZ.hpp"
#include "BluetoothAgent.hpp"

/*
 * Watches one org.bluez.Device1 object and reports its Connected/Paired changes.
 * One instance per known device; destroyed when BlueZ drops the object.
 */
class DeviceWatcher : public QObject {
    Q_OBJECT
public:
    DeviceWatcher(const QString &path, const QString &address, QObject *parent = nullptr)
        : QObject(parent), m_path(path), m_address(address) {}

    QString path() const    { return m_path; }
    QString address() const { return m_address; }

public slots:
    void onPropertiesChanged(const QString &interface,
                             const QVariantMap &changedProps,
                             const QStringList &invalidatedProps)
    {
        Q_UNUSED(interface) Q_UNUSED(invalidatedProps)
        if (changedProps.contains(QStringLiteral("Connected")))
            emit connectionChanged(m_address,
                                   changedProps.value(QStringLiteral("Connected")).toBool());
        if (changedProps.contains(QStringLiteral("Paired")))
            emit pairedChanged(m_address,
                               changedProps.value(QStringLiteral("Paired")).toBool());
    }

signals:
    void connectionChanged(const QString &address, bool connected);
    void pairedChanged(const QString &address, bool paired);

private:
    QString m_path;
    QString m_address;
};

class BluetoothHWManager : public QObject {
    Q_OBJECT

    Q_PROPERTY(bool bluetoothEnabled READ bluetoothEnabled WRITE setBluetoothEnabled NOTIFY bluetoothEnabledChanged)
    Q_PROPERTY(bool adapterPresent   READ adapterPresent   NOTIFY adapterPresentChanged)
    Q_PROPERTY(bool discovering      READ discovering      NOTIFY discoveringChanged)

public:
    explicit BluetoothHWManager(QObject *parent = nullptr);
    ~BluetoothHWManager() override;

    bool bluetoothEnabled() const { return m_bluetoothEnabled; }
    bool adapterPresent()   const { return !m_adapterPath.isEmpty(); }
    bool discovering()      const { return m_discovering; }
    void setBluetoothEnabled(bool enabled);

    Q_INVOKABLE void scanDevices();
    Q_INVOKABLE void stopScan();

    // Set while A2DP is streaming. Inquiry starves the ACL link, so discovery is
    // refused while there is audio to protect.
    void setMediaActive(bool active);
    Q_INVOKABLE void pairDevice(const QString &address);
    Q_INVOKABLE void connectDevice(const QString &address);
    Q_INVOKABLE void disconnectDevice(const QString &address);
    Q_INVOKABLE void removeDevice(const QString &address);   // unpair / forget

    // Answer the agent's pairing prompt
    Q_INVOKABLE void confirmPairing(bool accept);

signals:
    void bluetoothEnabledChanged(bool enabled);
    void adapterPresentChanged(bool present);
    void discoveringChanged(bool discovering);

    void scanStarted();
    // Each entry: { name, address, paired, trusted, connected, rssi, icon }
    void scanFinished(QVariantList devices);
    void scanFailed(const QString &reason);

    void pairSuccess(const QString &name);
    void pairFailed(const QString &reason);
    void connectSuccess(const QString &name);
    void connectFailed(const QString &reason);
    void disconnectSuccess(const QString &name);
    void disconnectFailed(const QString &reason);
    void removeSuccess(const QString &address);
    // Powering the adapter can fail silently (rfkill soft-block is the common
    // case) — surface it instead of leaving a toggle that does nothing.
    void powerChangeFailed(const QString &reason);
    void deviceConnectionChanged(const QString &address, bool connected);
    void devicePairedChanged(const QString &address, bool paired);

    // Agent prompts — passkey 0 means "no code to compare" (Just Works)
    void pairingConfirmationRequested(const QString &deviceName, uint passkey);
    void pairingPromptDismissed();

private slots:
    void onAdapterPropertiesChanged(QString interface, QVariantMap changedProps,
                                    QStringList invalidatedProps);
    void onInterfacesAdded(const QDBusObjectPath &path, const QVariantMap &interfaces);
    void onInterfacesRemoved(const QDBusObjectPath &path, const QStringList &interfaces);
    void onBlueZOwnerChanged(const QString &name, const QString &oldOwner,
                             const QString &newOwner);

private:
    void bootstrap();                       // find adapter, subscribe, register agent
    void adoptAdapter(const QString &path, const QVariantMap &props);
    void releaseAdapter();
    void trackDevice(const QString &path, const QVariantMap &props);
    void untrackDevice(const QString &path);
    void withDevicePath(const QString &address, QObject *ctx,
                        std::function<void(const QString &path)> cb);
    void collectScanResults();
    void setDiscovering(bool on);

    BluetoothAgent *m_agent = nullptr;

    QString m_adapterPath;
    bool    m_bluetoothEnabled = false;
    bool    m_discovering      = false;
    bool    m_scanPending      = false;
    bool    m_mediaActive      = false;

    // One owned timer rather than a singleShot per scan: overlapping requests
    // cannot then leave a stop pending against a window that already closed.
    QTimer *m_discoveryTimer = nullptr;

    // BlueZ accepts Set("Powered") even when rfkill has the radio soft-blocked,
    // and simply leaves it off — so success has to be confirmed, not assumed.
    QTimer *m_powerVerifyTimer = nullptr;
    bool    m_powerRequested   = false;

    // path -> watcher, and path -> address, so InterfacesRemoved can clean up
    QHash<QString, DeviceWatcher *> m_watchers;
    // address -> path cache, refreshed from ObjectManager signals
    QHash<QString, QString> m_addressToPath;

    QString m_pendingPairAddress;
    QString m_pendingConfirmName;
};
