#pragma once
#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QMap>
#include <QDBusObjectPath>
#include <QDBusArgument>
#include <functional>

/*
 * BlueZ — shared D-Bus plumbing for the Bluetooth backends.
 *
 * Both the settings manager and the media manager used to carry their own
 * hand-rolled copy of GetManagedObjects, with different bugs in each. This is
 * the single implementation.
 *
 * Everything here is ASYNCHRONOUS. A head unit's HMI thread must never block on
 * bluetoothd: a stalled daemon would otherwise freeze the UI for the D-Bus
 * default timeout (25s).
 */

using DBusInterfaceMap   = QMap<QString, QVariantMap>;
using DBusManagedObjects = QMap<QDBusObjectPath, DBusInterfaceMap>;

Q_DECLARE_METATYPE(DBusInterfaceMap)
Q_DECLARE_METATYPE(DBusManagedObjects)

QDBusArgument &operator<<(QDBusArgument &arg, const DBusInterfaceMap &map);
const QDBusArgument &operator>>(const QDBusArgument &arg, DBusInterfaceMap &map);
QDBusArgument &operator<<(QDBusArgument &arg, const DBusManagedObjects &map);
const QDBusArgument &operator>>(const QDBusArgument &arg, DBusManagedObjects &map);

namespace BlueZ {

extern const QString Service;
extern const QString Root;
extern const QString AdapterIface;
extern const QString DeviceIface;
extern const QString PlayerIface;
extern const QString AgentIface;
extern const QString AgentMgrIface;
extern const QString PropsIface;
extern const QString ObjMgrIface;

// Register the custom D-Bus marshalling types. Idempotent; call before use.
void registerTypes();

// Async GetManagedObjects on org.bluez /. Callback runs on the caller's thread.
// `ctx` scopes the callback: if it dies first, the callback is never invoked.
void managedObjects(QObject *ctx, std::function<void(const DBusManagedObjects &)> cb);

// Async org.freedesktop.DBus.Properties.GetAll
void properties(QObject *ctx, const QString &path, const QString &iface,
                std::function<void(const QVariantMap &)> cb);

// Async org.freedesktop.DBus.Properties.Set — fire and forget, errors logged
void setProperty(const QString &path, const QString &iface,
                 const QString &name, const QVariant &value);

// Async method call with no return value. `onError` is optional.
void callMethod(QObject *ctx, const QString &path, const QString &iface,
                const QString &method, const QVariantList &args = {},
                std::function<void(const QString &error)> onError = nullptr);

// A property map that arrived as a nested a{sv} needs manual extraction —
// qdbus_cast silently yields an empty map for some BlueZ payloads (Track).
QVariantMap toVariantMap(const QVariant &v);

} // namespace BlueZ
