#pragma once
#include <QObject>
#include <QDBusInterface>
#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>

class DeviceWatcher : public QObject {
    Q_OBJECT
public:
    explicit DeviceWatcher(const QString &path, const QString &address, QObject *parent = nullptr): QObject(parent), m_path(path), m_address(address) {}

    QString path() const { return m_path; }
    QString address() const { return m_address; }

public slots:
    void onPropertiesChanged(const QString &interface, const QVariantMap &changedProps, const QStringList &invalidatedProps){
        Q_UNUSED(interface) Q_UNUSED(invalidatedProps)
        if (changedProps.contains("Connected"))
            emit connectionChanged(m_address, changedProps["Connected"].toBool());
    }

signals:
    void connectionChanged(const QString &address, bool connected);

private:
    QString m_path;
    QString m_address;
};

class BluetoothHWManager : public QObject {
    Q_OBJECT

    Q_PROPERTY(bool bluetoothEnabled READ  bluetoothEnabled WRITE setBluetoothEnabled NOTIFY bluetoothEnabledChanged)

public:
    explicit BluetoothHWManager(QObject *parent = nullptr);

    bool bluetoothEnabled() const;
    void setBluetoothEnabled(bool enabled);

    Q_INVOKABLE void scanDevices();
    Q_INVOKABLE void pairDevice(const QString &address);
    Q_INVOKABLE void connectDevice(const QString &address);
    Q_INVOKABLE void disconnectDevice(const QString &address);

signals:
    void bluetoothEnabledChanged(bool enabled);
    void scanStarted();
    void scanFinished(QStringList devices);
    void scanFailed(const QString &reason);
    void pairSuccess(const QString &name);
    void pairFailed(const QString &reason);
    void connectSuccess(const QString &name);
    void connectFailed(const QString &reason);
    void disconnectSuccess(const QString &name);               
    void disconnectFailed(const QString &reason);             
    void deviceConnectionChanged(const QString &address, bool connected);

private slots:
    void onAdapterPropertiesChanged(QString interface, QVariantMap changedProps, QStringList invalidatedProps);
    void onInterfacesAdded(const QDBusObjectPath &path, const QVariantMap &interfaces);

private:
    QString         getAdapterPath();
    QString         findDevicePath(const QString &address);
    void            subscribeToDevice(const QString &path, const QString &address);
    void            subscribeToAllKnownDevices();

    QDBusInterface *m_adapterIface     = nullptr;
    bool            m_bluetoothEnabled = false;
    QString         m_adapterPath;
    QStringList     m_subscribedPaths;
};