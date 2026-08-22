#pragma once
#include <QObject>
#include <QByteArray>
#include <QDBusInterface>
#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QTimer>
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

    /*
     * Hand SSID + PSK to the ECUs, for whatever profile is active right now.
     *
     * The ESP32 and the Pi only learn a network when this runs, so it has to
     * run on every connect — not only the ones started from this screen. It
     * used to fire only when the user had *just typed* a password, which meant
     * a boot auto-connect, a reconnect after the AP power-cycled, and a switch
     * back to an already-saved network all left the ECUs pointed at whatever
     * network they were last told about.
     *
     * The password is READ BACK FROM NETWORKMANAGER each time rather than
     * remembered. NM owns it (in /data/network/system-connections, 0700 root,
     * which this process cannot read directly), and a second copy in this app
     * would be a second place for it to go stale — a network re-keyed from
     * nmcli or another head unit would keep forwarding the old PSK forever.
     */
    void forwardCredentials(const QString &ssid, const QDBusObjectPath &connPath);
    void attemptForward();
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

    // --- credential forwarding -------------------------------------------
    //
    // Identity of a send, kept as a SHA-256 of "ssid\0psk" rather than the
    // pair itself: enough to answer "have the ECUs already been told exactly
    // this?", and it keeps no password sitting in a member for the life of the
    // process. Re-keying a network changes the digest and forwards again.
    QByteArray      m_inFlightFp;    // digest of the send currently out
    QByteArray      m_lastSentFp;    // digest of the last one that succeeded

    // Retried because can0 is not ordered before this app. systemd-networkd
    // brings the interface up (recipes-connectivity/can-config/can0.network)
    // and ivi-app.service has no After= against it, so a WiFi auto-connect at
    // boot can easily beat CAN — the sender exits 4 and, without this, the one
    // case the forwarding exists for would be the one case it never covers.
    QDBusObjectPath m_forwardConnPath;
    QString         m_forwardSsid;
    int             m_forwardAttempts = 0;
    QTimer          m_forwardRetry;
};