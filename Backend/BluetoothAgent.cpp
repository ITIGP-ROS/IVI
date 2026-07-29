#include "BluetoothAgent.hpp"
#include "BlueZ.hpp"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDebug>

const QString BluetoothAgent::AgentPath  = QStringLiteral("/org/ivi/btagent");
const QString BluetoothAgent::Capability = QStringLiteral("DisplayYesNo");

BluetoothAgent::BluetoothAgent(QObject *parent) : QObject(parent)
{
    new BluetoothAgentAdaptor(this);   // parented to us by QDBusAbstractAdaptor
}

void BluetoothAgent::registerWith(QObject *ctx)
{
    if (m_registered) return;

    if (!QDBusConnection::systemBus().registerObject(AgentPath, this)) {
        const QString err = QStringLiteral("Cannot export agent at ") + AgentPath;
        qWarning() << "[bt-agent]" << err;
        emit registered(false, err);
        return;
    }

    BlueZ::callMethod(ctx, QStringLiteral("/org/bluez"), BlueZ::AgentMgrIface,
                      QStringLiteral("RegisterAgent"),
                      { QVariant::fromValue(QDBusObjectPath(AgentPath)), Capability },
                      [this, ctx](const QString &error) {
        if (!error.isEmpty()) {
            // AlreadyExists is benign: a previous run of this process left it behind.
            if (!error.contains(QStringLiteral("AlreadyExists"), Qt::CaseInsensitive)) {
                qWarning() << "[bt-agent] RegisterAgent failed:" << error;
                emit registered(false, error);
                return;
            }
        }

        m_registered = true;

        // Become the default agent so BlueZ routes pairing here rather than to
        // bluetoothctl or a desktop agent that may also be running.
        BlueZ::callMethod(ctx, QStringLiteral("/org/bluez"), BlueZ::AgentMgrIface,
                          QStringLiteral("RequestDefaultAgent"),
                          { QVariant::fromValue(QDBusObjectPath(AgentPath)) },
                          [this](const QString &err2) {
            if (!err2.isEmpty())
                qWarning() << "[bt-agent] RequestDefaultAgent failed:" << err2;
            else
                qInfo() << "[bt-agent] registered as default agent, capability"
                        << Capability;
            emit registered(true, QString());
        });
    });
}

void BluetoothAgent::unregister()
{
    if (!m_registered) return;
    m_registered = false;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        BlueZ::Service, QStringLiteral("/org/bluez"), BlueZ::AgentMgrIface,
        QStringLiteral("UnregisterAgent"));
    msg << QVariant::fromValue(QDBusObjectPath(AgentPath));
    QDBusConnection::systemBus().asyncCall(msg);
    QDBusConnection::systemBus().unregisterObject(AgentPath);
}

void BluetoothAgent::holdReply(const QDBusMessage &msg)
{
    // If a previous request is somehow still open, reject it rather than leak
    // an unanswered D-Bus call — BlueZ would stall until its own timeout.
    if (m_pendingValid)
        resolvePending(false);

    msg.setDelayedReply(true);
    m_pending      = msg;
    m_pendingValid = true;
}

void BluetoothAgent::resolvePending(bool accept)
{
    if (!m_pendingValid) return;
    m_pendingValid = false;

    QDBusMessage reply = accept
        ? m_pending.createReply()
        : m_pending.createErrorReply(QStringLiteral("org.bluez.Error.Rejected"),
                                     QStringLiteral("Rejected by user"));

    QDBusConnection::systemBus().send(reply);
    qInfo() << "[bt-agent] pairing" << (accept ? "accepted" : "rejected") << "by user";
}

// ---------------------------------------------------------------- adaptor ---

BluetoothAgentAdaptor::BluetoothAgentAdaptor(BluetoothAgent *agent)
    : QDBusAbstractAdaptor(agent), m_agent(agent)
{
    setAutoRelaySignals(false);
}

void BluetoothAgentAdaptor::Release()
{
    qInfo() << "[bt-agent] released by BlueZ";
}

void BluetoothAgentAdaptor::Cancel()
{
    // The remote side gave up (user cancelled on the phone, or timeout).
    m_agent->resolvePending(false);
    emit m_agent->cancelled();
}

QString BluetoothAgentAdaptor::RequestPinCode(const QDBusObjectPath &device)
{
    // Legacy pre-2.1 pairing. A DisplayYesNo agent has no keyboard to enter a
    // PIN with, so refuse rather than invent one.
    Q_UNUSED(device)
    qWarning() << "[bt-agent] RequestPinCode not supported by a DisplayYesNo agent";
    return QString();
}

uint BluetoothAgentAdaptor::RequestPasskey(const QDBusObjectPath &device)
{
    Q_UNUSED(device)
    qWarning() << "[bt-agent] RequestPasskey not supported by a DisplayYesNo agent";
    return 0;
}

void BluetoothAgentAdaptor::DisplayPinCode(const QDBusObjectPath &device,
                                           const QString &pinCode)
{
    emit m_agent->pinCodeDisplayed(device.path(), pinCode);
}

void BluetoothAgentAdaptor::DisplayPasskey(const QDBusObjectPath &device,
                                           uint passkey, ushort entered)
{
    Q_UNUSED(entered)
    emit m_agent->passkeyDisplayed(device.path(), passkey);
}

void BluetoothAgentAdaptor::RequestConfirmation(const QDBusObjectPath &device,
                                                uint passkey, const QDBusMessage &msg)
{
    // Numeric comparison — the driver must see the code and agree it matches the
    // phone. Hold the call open until they answer.
    m_agent->holdReply(msg);
    emit m_agent->confirmationRequested(device.path(), passkey);
}

void BluetoothAgentAdaptor::RequestAuthorization(const QDBusObjectPath &device,
                                                 const QDBusMessage &msg)
{
    // Just Works pairing: no code to compare, but still a pairing request that
    // the driver should approve rather than something we accept silently.
    m_agent->holdReply(msg);
    emit m_agent->confirmationRequested(device.path(), 0);
}

void BluetoothAgentAdaptor::AuthorizeService(const QDBusObjectPath &device,
                                             const QString &uuid,
                                             const QDBusMessage &msg)
{
    // Profile-level authorization (A2DP, AVRCP, HFP...) on an already-paired
    // device. Prompting per profile on every connect would be unusable in a car,
    // so this is accepted for devices that completed pairing.
    Q_UNUSED(device) Q_UNUSED(uuid) Q_UNUSED(msg)
}
