#include "BlueZ.hpp"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QPointer>
#include <QDebug>

QDBusArgument &operator<<(QDBusArgument &arg, const DBusInterfaceMap &map)
{
    arg.beginMap(QMetaType::QString, qMetaTypeId<QVariantMap>());
    for (auto it = map.begin(); it != map.end(); ++it) {
        arg.beginMapEntry();
        arg << it.key() << it.value();
        arg.endMapEntry();
    }
    arg.endMap();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, DBusInterfaceMap &map)
{
    arg.beginMap();
    while (!arg.atEnd()) {
        QString key;
        QVariantMap val;
        arg.beginMapEntry();
        arg >> key >> val;
        arg.endMapEntry();
        map[key] = val;
    }
    arg.endMap();
    return arg;
}

QDBusArgument &operator<<(QDBusArgument &arg, const DBusManagedObjects &map)
{
    arg.beginMap(qMetaTypeId<QDBusObjectPath>(), qMetaTypeId<DBusInterfaceMap>());
    for (auto it = map.begin(); it != map.end(); ++it) {
        arg.beginMapEntry();
        arg << it.key() << it.value();
        arg.endMapEntry();
    }
    arg.endMap();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, DBusManagedObjects &map)
{
    arg.beginMap();
    while (!arg.atEnd()) {
        QDBusObjectPath path;
        DBusInterfaceMap ifaces;
        arg.beginMapEntry();
        arg >> path >> ifaces;
        arg.endMapEntry();
        map[path] = ifaces;
    }
    arg.endMap();
    return arg;
}

namespace BlueZ {

const QString Service       = QStringLiteral("org.bluez");
const QString Root          = QStringLiteral("/");
const QString AdapterIface  = QStringLiteral("org.bluez.Adapter1");
const QString DeviceIface   = QStringLiteral("org.bluez.Device1");
const QString PlayerIface   = QStringLiteral("org.bluez.MediaPlayer1");
const QString AgentIface    = QStringLiteral("org.bluez.Agent1");
const QString AgentMgrIface = QStringLiteral("org.bluez.AgentManager1");
const QString PropsIface    = QStringLiteral("org.freedesktop.DBus.Properties");
const QString ObjMgrIface   = QStringLiteral("org.freedesktop.DBus.ObjectManager");

void registerTypes()
{
    static bool done = false;
    if (done) return;
    done = true;
    qDBusRegisterMetaType<DBusInterfaceMap>();
    qDBusRegisterMetaType<DBusManagedObjects>();
}

void managedObjects(QObject *ctx, std::function<void(const DBusManagedObjects &)> cb)
{
    registerTypes();

    QDBusMessage msg = QDBusMessage::createMethodCall(Service, Root, ObjMgrIface,
                                                      QStringLiteral("GetManagedObjects"));
    QDBusPendingCall call = QDBusConnection::systemBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(call, ctx);

    QPointer<QObject> guard(ctx);
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, ctx,
                     [cb, guard](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        if (!guard) return;

        QDBusMessage reply = w->reply();
        DBusManagedObjects result;
        if (reply.type() == QDBusMessage::ErrorMessage) {
            qWarning() << "[bt] GetManagedObjects failed:" << reply.errorMessage();
        } else if (!reply.arguments().isEmpty()) {
            reply.arguments().at(0).value<QDBusArgument>() >> result;
        }
        cb(result);
    });
}

void properties(QObject *ctx, const QString &path, const QString &iface,
                std::function<void(const QVariantMap &)> cb)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(Service, path, PropsIface,
                                                      QStringLiteral("GetAll"));
    msg << iface;

    QDBusPendingCall call = QDBusConnection::systemBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(call, ctx);

    QPointer<QObject> guard(ctx);
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, ctx,
                     [cb, guard](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        if (!guard) return;

        QVariantMap result;
        QDBusMessage reply = w->reply();
        if (reply.type() != QDBusMessage::ErrorMessage && !reply.arguments().isEmpty())
            result = toVariantMap(reply.arguments().at(0));
        cb(result);
    });
}

void setProperty(const QString &path, const QString &iface,
                 const QString &name, const QVariant &value)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(Service, path, PropsIface,
                                                      QStringLiteral("Set"));
    msg << iface << name << QVariant::fromValue(QDBusVariant(value));
    QDBusConnection::systemBus().asyncCall(msg);
}

void callMethod(QObject *ctx, const QString &path, const QString &iface,
                const QString &method, const QVariantList &args,
                std::function<void(const QString &)> onError)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(Service, path, iface, method);
    if (!args.isEmpty())
        msg.setArguments(args);

    QDBusPendingCall call = QDBusConnection::systemBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(call, ctx);

    QPointer<QObject> guard(ctx);
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, ctx,
                     [onError, guard, method](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        if (!guard) return;

        QDBusMessage reply = w->reply();
        if (reply.type() == QDBusMessage::ErrorMessage) {
            if (onError) onError(reply.errorMessage());
            else qWarning() << "[bt]" << method << "failed:" << reply.errorMessage();
        } else if (onError) {
            onError(QString());
        }
    });
}

QVariantMap toVariantMap(const QVariant &v)
{
    QVariantMap out;

    if (v.canConvert<QDBusArgument>()) {
        const QDBusArgument arg = v.value<QDBusArgument>();
        if (arg.currentType() != QDBusArgument::MapType)
            return out;
        arg.beginMap();
        while (!arg.atEnd()) {
            QString key;
            QDBusVariant val;
            arg.beginMapEntry();
            arg >> key >> val;
            arg.endMapEntry();
            out[key] = val.variant();
        }
        arg.endMap();
        return out;
    }

    return v.toMap();
}

} // namespace BlueZ
