#include "VehicleBus.hpp"

#include <QDebug>

#include <cerrno>
#include <cstring>

#include <fcntl.h>
#include <linux/can.h>
#include <linux/can/raw.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

namespace {

constexpr canid_t kVehicleStatusId = 0x200;
constexpr char    kDefaultIface[]  = "can0";
constexpr char    kIfaceEnvVar[]   = "IVI_CAN_IFACE";

constexpr int kStaleMs  = 500;
constexpr int kReopenMs = 5000;

constexpr char kLogTag[] = "[vehicle]";

// 1 LSB = 1 m/min. Whole m/min is deliberate on the Tiva's side: 1 m/min is
// 0.017 m/s, finer than the drive can actually hold.
constexpr double kMetresPerMinuteToMps = 1.0 / 60.0;

} // namespace

VehicleBus::VehicleBus(QObject *parent) : QObject(parent)
{
    m_iface = qEnvironmentVariable(kIfaceEnvVar, QLatin1String(kDefaultIface));

    m_stale.setSingleShot(true);
    m_stale.setInterval(kStaleMs);
    connect(&m_stale, &QTimer::timeout, this, [this] { setLive(false); });

    m_reopen.setInterval(kReopenMs);
    connect(&m_reopen, &QTimer::timeout, this, [this] {
        if (available()) {
            m_reopen.stop();
            return;
        }
        openBus();
    });

    openBus();
    if (!available())
        m_reopen.start();
}

VehicleBus::~VehicleBus()
{
    closeBus();
}

QString VehicleBus::gearLabel() const
{
    switch (m_gear) {
    case GearNeutral: return QStringLiteral("N");
    case GearDrive:   return QStringLiteral("D");
    case GearReverse: return QStringLiteral("R");
    default:          return QStringLiteral("?");
    }
}

void VehicleBus::openBus()
{
    if (m_fd >= 0)
        return;

    const int fd = ::socket(PF_CAN, SOCK_RAW, CAN_RAW);
    if (fd < 0) {
        qWarning().noquote() << kLogTag << "cannot create CAN socket:" << std::strerror(errno);
        return;
    }

    /*
     * Filter in the kernel, not here.
     *
     * This bus also carries 100 Hz wheel-tick and steering feedback; waking the
     * GUI thread for every one of those only to drop it is work the head unit
     * has no reason to do. With the filter installed the socket sees roughly 10
     * frames a second.
     *
     * The mask includes CAN_EFF_FLAG on purpose. Matching on CAN_SFF_MASK alone
     * does not compare the flag, so a 29-bit frame whose low 11 bits happened to
     * be 0x200 would pass the filter and be decoded as a VehicleStatus.
     */
    const can_filter filter{ kVehicleStatusId, CAN_SFF_MASK | CAN_EFF_FLAG };
    if (::setsockopt(fd, SOL_CAN_RAW, CAN_RAW_FILTER, &filter, sizeof(filter)) < 0) {
        qWarning().noquote() << kLogTag << "cannot set CAN filter:" << std::strerror(errno);
        ::close(fd);
        return;
    }

    ifreq ifr{};
    const QByteArray ifaceName = m_iface.toLatin1();
    std::strncpy(ifr.ifr_name, ifaceName.constData(), IFNAMSIZ - 1);
    if (::ioctl(fd, SIOCGIFINDEX, &ifr) < 0) {
        // The usual case on a bench with no harness attached, and on the vehicle
        // before the interface is brought up. The reopen timer handles it; this
        // is not worth a warning every five seconds.
        ::close(fd);
        return;
    }

    sockaddr_can addr{};
    addr.can_family  = AF_CAN;
    addr.can_ifindex = ifr.ifr_ifindex;
    if (::bind(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
        qWarning().noquote() << kLogTag << "cannot bind" << m_iface << ":"
                             << std::strerror(errno);
        ::close(fd);
        return;
    }

    // Non-blocking so the drain loop in readFrames() has a way to stop: it reads
    // until EAGAIN, which on a blocking socket would park the GUI thread.
    const int flags = ::fcntl(fd, F_GETFL, 0);
    if (flags >= 0)
        ::fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    m_fd = fd;

    // Delivery lands on the thread that owns this object — the GUI thread — so
    // the property writes below are on the same thread as the QML bindings that
    // read them.
    m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, [this] { readFrames(); });

    qInfo().noquote() << kLogTag << "listening for 0x200 VehicleStatus on" << m_iface;
    emit availableChanged();
}

void VehicleBus::closeBus()
{
    if (m_notifier) {
        m_notifier->setEnabled(false);
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }

    if (m_fd < 0)
        return;

    ::close(m_fd);
    m_fd = -1;
    setLive(false);
    emit availableChanged();
}

void VehicleBus::readFrames()
{
    /*
     * Drain to EAGAIN rather than taking one frame per wake-up, so a burst that
     * queued while the UI was busy does not leave the socket permanently a few
     * frames behind. Bounded in practice by the kernel filter above: only the
     * 10 Hz frame reaches this socket at all.
     */
    for (;;) {
        can_frame frame{};
        const ssize_t n = ::read(m_fd, &frame, sizeof(frame));

        if (n < 0) {
            if (errno == EINTR)
                continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                return;

            qWarning().noquote() << kLogTag << "read failed:" << std::strerror(errno);
            closeBus();        // ENETDOWN and friends — retry when the link returns
            m_reopen.start();
            return;
        }

        // A CAN FD frame read through a classic socket comes back short. Not
        // ours either way.
        if (n != sizeof(frame))
            continue;

        // An error frame carries a diagnostic bitfield in place of a payload,
        // and a remote-request frame carries no payload at all. Decoding either
        // as VehicleStatus would invent a speed out of nothing.
        if (frame.can_id & (CAN_ERR_FLAG | CAN_RTR_FLAG))
            continue;

        const quint8 *d = frame.data;

        /*
         * Each signal is guarded by its own length rather than one check for
         * DLC 8. A sender that shortens the frame — an older Tiva build predates
         * trip_m and odo_m entirely — should still yield a usable speed instead
         * of being dropped whole, and must never be read past its end.
         */
        if (frame.can_dlc >= 2) {
            const quint16 rawMetresPerMinute =
                quint16(d[0]) | (quint16(d[1]) << 8);
            const double mps = rawMetresPerMinute * kMetresPerMinuteToMps;
            if (!qFuzzyCompare(m_speedMps, mps)) {
                m_speedMps = mps;
                emit speedChanged();
            }
        }

        if (frame.can_dlc >= 3 && m_gear != int(d[2])) {
            m_gear = d[2];
            emit gearChanged();
        }

        if (frame.can_dlc >= 5) {
            const int trip = int(quint16(d[3]) | (quint16(d[4]) << 8));
            if (m_tripMetres != trip) {
                m_tripMetres = trip;
                emit tripMetresChanged();
            }
        }

        if (frame.can_dlc >= 8) {
            const int odo = int(quint32(d[5])
                                | (quint32(d[6]) << 8)
                                | (quint32(d[7]) << 16));
            if (m_odoMetres != odo) {
                m_odoMetres = odo;
                emit odoMetresChanged();
            }
        }

        setLive(true);
        m_stale.start();
    }
}

void VehicleBus::setLive(bool live)
{
    if (m_live == live)
        return;
    m_live = live;

    /*
     * The last decoded speed is deliberately left alone when the link drops.
     * Zeroing it here would tell every consumer the car had stopped, which is a
     * different claim from "nobody is saying" — and a car whose Tiva has just
     * gone quiet is more likely still rolling than parked. `live` is the flag
     * that says whether the number means anything; deciding what to show
     * instead belongs to whoever is displaying it.
     */
    if (!live)
        qWarning().noquote() << kLogTag << "no VehicleStatus for" << kStaleMs
                             << "ms — speed is stale";
    else
        qInfo().noquote() << kLogTag << "VehicleStatus live";

    emit liveChanged();
}
