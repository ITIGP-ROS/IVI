#pragma once
#include <QObject>
#include <QDBusInterface>
#include <QDBusConnection>
#include "WifiCredSender.hpp"

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
    // security: "wpa-psk" (password required) or "open" (password ignored)
    Q_INVOKABLE void connectToHiddenNetwork(const QString &ssid, const QString &password,
                                            const QString &security);
    Q_INVOKABLE void connectToSelectedNetwork(const QString &ssid);
    Q_INVOKABLE void disconnectFromNetwork();
    Q_INVOKABLE void forgetNetwork(const QString &ssid);

signals:
    void wifiEnabledChanged(bool enabled);
    void scanStarted();
    /*
     * One entry per SSID: { "name": QString, "strength": int 0-100,
     * "secured": bool }.
     *
     * A plain QStringList until the list gained a signal-strength icon, which
     * had nothing to read. NetworkManager reports both on the access point
     * objects this already walks, so carrying them costs a property read each.
     * Same shape BluetoothHWManager::scanFinished already uses.
     */
    void scanFinished(QVariantList networks);
    void scanFailed(const QString &reason);
    void connectSuccess(const QString &ssid);
    void connectFailed(const QString &reason);
    void passwordRequired(const QString &ssid);
    void connectedSsidChanged(const QString &ssid);
    void forgetSuccess(const QString &ssid);
    void credentialsSent(const QString &ssid);
    void credentialsFailed(const QString &reason);

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
    // Shared body for both connect entry points. `hidden` sets
    // 802-11-wireless.hidden so NM probes for an SSID that is not beaconed;
    // `open` drops the security block entirely.
    void connectWithSettings(const QString &ssid, const QString &password,
                             bool hidden, bool open);

    QDBusInterface *m_nmInterface;
    WifiCredSender *m_credSender;
    bool            m_wifiEnabled       = false;
    QString         m_pendingSsid;
    // Held only between connectToNetwork() and the activation result, so the
    // credentials can be forwarded to the vehicle host once the AP accepts them.
    QString         m_pendingPassword;
    QString         m_activeConnPath;
    QString         m_connectedSsid;
    QString         m_wirelessDevicePath;
};