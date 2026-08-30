#include "inc/interface_monitor.h"

#include <QDebug>
#include <QSocketNotifier>

#include <arpa/inet.h>
#include <asm/types.h>
#include <cstring>
#include <errno.h>
#include <ifaddrs.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <net/if.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

namespace {
// DHCP produces a burst of netlink messages per lease (offer, confirm, and a
// delete/add pair on re-association), so this debounces to avoid rebuilding
// the participant several times for one connect. Single-shot, armed only by
// a kernel notification — not a poll.
constexpr int kDebounceMs = 1000;

// The netlink read buffer. Address messages are small; this is drained in a
// loop anyway, so the size only affects how many syscalls a burst costs.
constexpr int kBufSize = 8192;
}

InterfaceMonitor::InterfaceMonitor(QObject* parent)
    : QObject(parent)
{
    debounce_.setSingleShot(true);
    debounce_.setInterval(kDebounceMs);
    connect(&debounce_, &QTimer::timeout, this, &InterfaceMonitor::reread);

    // Seed from the current state so the first change is measured against
    // reality rather than against an empty set.
    addrs_ = currentIPv4();

    fd_ = ::socket(AF_NETLINK,
                   SOCK_RAW | SOCK_CLOEXEC | SOCK_NONBLOCK,
                   NETLINK_ROUTE);
    if (fd_ < 0) {
        qWarning() << "[netmon] socket(AF_NETLINK) failed:" << strerror(errno)
                   << "- ROS node will not recover from network changes";
        return;
    }

    struct sockaddr_nl sa {};
    sa.nl_family = AF_NETLINK;
    sa.nl_groups = RTMGRP_IPV4_IFADDR;

    if (::bind(fd_, reinterpret_cast<struct sockaddr*>(&sa), sizeof(sa)) < 0) {
        qWarning() << "[netmon] bind(RTMGRP_IPV4_IFADDR) failed:"
                   << strerror(errno)
                   << "- ROS node will not recover from network changes";
        ::close(fd_);
        fd_ = -1;
        return;
    }

    notifier_ = new QSocketNotifier(fd_, QSocketNotifier::Read, this);
    connect(notifier_, &QSocketNotifier::activated,
            this, &InterfaceMonitor::onNetlinkActivity);

    qDebug() << "[netmon] watching IPv4 address changes; current:"
             << addrs_.values();
}

InterfaceMonitor::~InterfaceMonitor()
{
    if (notifier_)
        notifier_->setEnabled(false);
    if (fd_ >= 0)
        ::close(fd_);
}

QSet<QString> InterfaceMonitor::currentIPv4()
{
    QSet<QString> out;

    struct ifaddrs* list = nullptr;
    if (::getifaddrs(&list) != 0) {
        qWarning() << "[netmon] getifaddrs failed:" << strerror(errno);
        return out;
    }

    for (struct ifaddrs* ifa = list; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET)
            continue;
        // Loopback is always there and never lets DDS reach another host, so
        // counting it would make "we have a network" true even when offline.
        if (ifa->ifa_flags & IFF_LOOPBACK)
            continue;
        if (!(ifa->ifa_flags & IFF_UP) || !(ifa->ifa_flags & IFF_RUNNING))
            continue;

        char buf[INET_ADDRSTRLEN] = {0};
        const auto* in = reinterpret_cast<struct sockaddr_in*>(ifa->ifa_addr);
        if (::inet_ntop(AF_INET, &in->sin_addr, buf, sizeof(buf)))
            out.insert(QString::fromLatin1(buf));
    }

    ::freeifaddrs(list);
    return out;
}

void InterfaceMonitor::onNetlinkActivity()
{
    // Drain the socket. The payload is deliberately not parsed: any
    // RTM_NEWADDR/RTM_DELADDR means "the address list may have moved", and
    // getifaddrs() then gives the authoritative answer. Decoding rtattrs here
    // would be more code and could still disagree with the kernel's final
    // state after a burst.
    char buf[kBufSize];
    bool interesting = false;

    for (;;) {
        const ssize_t got = ::recv(fd_, buf, sizeof(buf), 0);
        if (got < 0) {
            if (errno == EINTR)
                continue;
            if (errno != EAGAIN && errno != EWOULDBLOCK)
                qWarning() << "[netmon] recv failed:" << strerror(errno);
            break;
        }
        if (got == 0)
            break;

        // NLMSG_NEXT decrements its length argument as it walks, so this has
        // to be a mutable copy.
        int len = static_cast<int>(got);
        for (auto* nh = reinterpret_cast<struct nlmsghdr*>(buf);
             NLMSG_OK(nh, static_cast<unsigned>(len));
             nh = NLMSG_NEXT(nh, len)) {
            if (nh->nlmsg_type == NLMSG_DONE)
                break;
            if (nh->nlmsg_type == RTM_NEWADDR || nh->nlmsg_type == RTM_DELADDR)
                interesting = true;
        }
    }

    if (interesting)
        debounce_.start();   // restart: coalesces the whole burst
}

void InterfaceMonitor::reread()
{
    const QSet<QString> now = currentIPv4();
    if (now == addrs_)
        return;              // nothing really changed; stay quiet

    const QSet<QString> before = addrs_;
    addrs_ = now;

    qDebug() << "[netmon] IPv4 changed:" << before.values()
             << "->" << now.values();

    emit addressesChanged(addrs_);
}
