#ifndef INTERFACE_MONITOR_H
#define INTERFACE_MONITOR_H

#include <QObject>
#include <QSet>
#include <QString>
#include <QTimer>

class QSocketNotifier;

/*
 * Tells you when this machine's set of usable IPv4 addresses changes.
 *
 * Fast DDS enumerates network interfaces once at DomainParticipant creation
 * and never rescans, so a participant built before an interface has an
 * address stays deaf on it forever, even after DHCP hands out a lease.
 * ivi-app starts before DHCP completes, so RosNode needs to know when an
 * address appears so it can rebuild its participant.
 *
 * Uses the kernel's RTNETLINK notifications, not polling, and only fires
 * when the address set actually changed.
 */
class InterfaceMonitor : public QObject
{
    Q_OBJECT

public:
    explicit InterfaceMonitor(QObject* parent = nullptr);
    ~InterfaceMonitor() override;

    // Every non-loopback IPv4 address currently configured on this host, as
    // dotted quads. Read straight from getifaddrs(), so it is the truth at the
    // moment of the call rather than a cached view.
    static QSet<QString> currentIPv4();

    QSet<QString> addresses() const { return addrs_; }

signals:
    // Emitted only when the set actually differs from the previous one.
    void addressesChanged(const QSet<QString>& addresses);

private:
    void onNetlinkActivity();
    void reread();

    int             fd_       = -1;
    QSocketNotifier* notifier_ = nullptr;
    QSet<QString>   addrs_;
    QTimer          debounce_;
};

#endif // INTERFACE_MONITOR_H
