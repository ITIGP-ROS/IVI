#pragma once
#include <QObject>
#include <QDBusInterface>
#include <QDBusConnection>

typedef QMap<QString, QVariantMap> NMConnectionSettings;

class WifiManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool wifiEnabled READ  wifiEnabled WRITE setWifiEnabled NOTIFY wifiEnabledChanged)
    Q_PROPERTY(QString connectedSsid READ  connectedSsid NOTIFY connectedSsidChanged)

public:
    explicit WifiManager(QObject *parent = nullptr);

    bool wifiEnabled()  const;
    QString connectedSsid() const { return m_connectedSsid; }

    void setWifiEnabled(bool enabled);

    Q_INVOKABLE void scanNetworks();
    Q_INVOKABLE void connectToNetwork(const QString &ssid, const QString &password);
    Q_INVOKABLE void connectToSelectedNetwork(const QString &ssid);
    Q_INVOKABLE void disconnectFromNetwork();
    Q_INVOKABLE void forgetNetwork(const QString &ssid);

signals:
    void wifiEnabledChanged(bool enabled);
    void scanStarted();
    void scanFinished(QStringList networks);
    void scanFailed(const QString &reason);
    void connectSuccess(const QString &ssid);
    void connectFailed(const QString &reason);
    void passwordRequired(const QString &ssid);
    void connectedSsidChanged(const QString &ssid);
    void forgetSuccess(const QString &ssid);

private slots:
    void onPropertiesChanged(QString interface,
                             QVariantMap changedProps,
                             QStringList invalidatedProps);
    void onActiveConnPropertiesChanged(QString interface,
                                       QVariantMap changedProps,
                                       QStringList invalidatedProps);

private:
    void watchActiveConnection(const QString &activeConnPath, const QString &ssid);
    void updateConnectedSsid();

    QDBusInterface *m_nmInterface;
    bool            m_wifiEnabled       = false;
    QString         m_pendingSsid;
    QString         m_activeConnPath;
    QString         m_connectedSsid;
    QString         m_wirelessDevicePath;
};