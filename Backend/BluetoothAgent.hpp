#pragma once
#include <QObject>
#include <QDBusAbstractAdaptor>
#include <QDBusObjectPath>
#include <QDBusMessage>

/*
 * BluetoothAgent — implements org.bluez.Agent1 for the head unit.
 *
 * BlueZ delegates ALL pairing interaction to a registered agent. Without one,
 * Secure Simple Pairing methods that need user confirmation (numeric comparison
 * and passkey entry — what current phones use) cannot be completed from our HMI.
 *
 * Capability is "DisplayYesNo": we can show a 6-digit passkey and the user
 * confirms it matches the phone. That is the correct profile for a car head unit
 * (a display, no keyboard). "NoInputNoOutput" would silently downgrade every
 * pairing to Just Works, which is weaker and shows the driver nothing.
 *
 * RequestConfirmation uses a DELAYED D-Bus reply: the call is left open while the
 * user decides, then answered from confirmPairing(). Replying immediately would
 * mean accepting a pairing the driver never saw.
 */
class BluetoothAgent : public QObject {
    Q_OBJECT

public:
    explicit BluetoothAgent(QObject *parent = nullptr);

    static const QString AgentPath;
    static const QString Capability;

    // Register with BlueZ and ask to become the system default agent.
    void registerWith(QObject *ctx);
    void unregister();

    // Answer a pending RequestConfirmation / RequestAuthorization.
    void resolvePending(bool accept);
    bool hasPending() const { return m_pendingValid; }

signals:
    // devicePath + human-readable name + the 6-digit code to compare.
    // passkey is 0 for RequestAuthorization (no code to show).
    void confirmationRequested(const QString &devicePath, uint passkey);
    void passkeyDisplayed(const QString &devicePath, uint passkey);
    void pinCodeDisplayed(const QString &devicePath, const QString &pinCode);
    void cancelled();
    void registered(bool ok, const QString &error);

private:
    friend class BluetoothAgentAdaptor;

    void holdReply(const QDBusMessage &msg);

    QDBusMessage m_pending;
    bool         m_pendingValid = false;
    bool         m_registered   = false;
};

/*
 * The D-Bus face of the agent. Kept separate so BluetoothAgent stays a plain
 * QObject that QML-facing code can own and connect to.
 */
class BluetoothAgentAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")

public:
    explicit BluetoothAgentAdaptor(BluetoothAgent *agent);

public slots:
    void    Release();
    void    Cancel();
    QString RequestPinCode(const QDBusObjectPath &device);
    uint    RequestPasskey(const QDBusObjectPath &device);
    void    DisplayPinCode(const QDBusObjectPath &device, const QString &pinCode);
    void    DisplayPasskey(const QDBusObjectPath &device, uint passkey, ushort entered);
    void    RequestConfirmation(const QDBusObjectPath &device, uint passkey,
                                const QDBusMessage &msg);
    void    RequestAuthorization(const QDBusObjectPath &device, const QDBusMessage &msg);
    void    AuthorizeService(const QDBusObjectPath &device, const QString &uuid,
                             const QDBusMessage &msg);

private:
    BluetoothAgent *m_agent;
};
