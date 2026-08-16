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
 * This exists for one reason: Fast DDS enumerates the host's network
 * interfaces once, when the DomainParticipant is created, and the Humble line
 * never rescans. A participant built while the WiFi has no address is deaf and
 * mute on that NIC forever — it does not announce itself there, does not join
 * the discovery multicast group there, and does not advertise a reachable
 * unicast locator. Connecting to WiFi afterwards does not repair it; only
 * building a new participant does.
 *
 * That is exactly the head unit's boot order. ivi-app starts a second or so
 * before DHCP hands out the lease, so out of the box the app can never see the
 * detection publisher, no matter what the user does in the WiFi settings page.
 *
 * So RosNode needs to know when an address appears. It must NOT learn that by
 * polling, and it must not tear down a working ROS node on a guess: this
 * reports the kernel's own RTNETLINK notifications, and only when the address
 * set genuinely changed.
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
