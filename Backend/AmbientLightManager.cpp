#include "AmbientLightManager.hpp"

#include <QDebug>
#include <QSettings>

#include <cerrno>
#include <cstring>

#include <fcntl.h>
#include <linux/can.h>
#include <linux/can/raw.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

/*
 * Bench mode: print the frames instead of putting them on a bus.
 *
 * Flip to 1 to develop on a laptop with no CAN hardware — every frame that
 * would have gone out is written to the terminal in candump's format, and the
 * page behaves as if the ECU were connected instead of greying itself out.
 *
 * Overridable from the build so it never has to be a source edit that risks
 * being committed by accident:
 *     cmake -B build -DAMBIENT_CAN_SIMULATE=ON
 *
 * Default is 0 on purpose: a plain build must target the real bus, or the head
 * unit ships quietly driving nothing.
 */
#ifndef AMBIENT_CAN_SIMULATE
#define AMBIENT_CAN_SIMULATE 0
#endif

namespace {

constexpr canid_t kCanId          = 0x500;   // low priority on purpose
constexpr char    kDefaultIface[] = "can0";
constexpr char    kIfaceEnvVar[]  = "IVI_CAN_IFACE";

// Mode 0 is "off" on the wire; the rest live in AmbientLightManager::Mode*.
constexpr quint8 kModeOff = 0;

/*
 * How often a change may reach the bus. This is the knob — raise it to send
 * less, lower it to track a finger more closely.
 *
 * 100 ms (10 Hz) is chosen from the receiver's cost, not the bus's: one 8-byte
 * standard frame is ~128 bits, so even 20 Hz was only about 0.5% of a 500 kbit
 * bus. What actually costs the ECU is any per-frame logging it does — a 75
 * character line at 115200 baud is ~6.5 ms, a thousand times the cost of
 * handling the frame. 10 Hz still looks continuous on a slider because the
 * strip fades between values anyway.
 */
constexpr int kFlushMs  = 100;

/*
 * How often the current state is restated even when nothing has changed.
 *
 * Sets the worst case for how long the strip stays wrong after the ECU reboots.
 * 3 s costs a third of a frame per second — about 26 bit/s, which is noise next
 * to the 10 Hz burst a single drag produces — so there is no reason to stretch
 * it further just to save bus.
 */
constexpr int kHeartbeatMs = 3000;
constexpr int kReopenMs = 5000;

constexpr char kLogTag[] = "[ambient]";

} // namespace

AmbientLightManager::AmbientLightManager(QObject *parent) : QObject(parent)
{
    m_iface = qEnvironmentVariable(kIfaceEnvVar, QLatin1String(kDefaultIface));

    restore();

    m_flush.setSingleShot(true);
    m_flush.setInterval(kFlushMs);
    connect(&m_flush, &QTimer::timeout, this, &AmbientLightManager::flush);

    m_reopen.setInterval(kReopenMs);
    connect(&m_reopen, &QTimer::timeout, this, [this] {
        if (available()) {
            m_reopen.stop();
            return;
        }
        openBus();
        // Whatever was set before the bus came up has never reached the ECU.
        if (available())
            scheduleFlush();
    });

    m_heartbeat.setInterval(kHeartbeatMs);
    connect(&m_heartbeat, &QTimer::timeout, this, [this] {
        if (!available())
            return;
        // Clearing this defeats the duplicate-payload guard, which is the whole
        // point here: the frame is redundant to us and essential to an ECU that
        // has just come back up knowing nothing.
        m_havePrevious = false;
        scheduleFlush();
    });
    m_heartbeat.start();

    openBus();
    if (available())
        scheduleFlush();     // re-assert the restored state at startup
    else
        m_reopen.start();
}

AmbientLightManager::~AmbientLightManager()
{
    closeBus();
}

void AmbientLightManager::openBus()
{
    if (m_open)
        return;

#if AMBIENT_CAN_SIMULATE
    // No socket at all — flush() prints and returns before ever touching m_fd.
    m_open = true;
    qInfo().noquote() << kLogTag << "SIMULATION — frames go to the terminal, not to"
                      << m_iface;
    emit availableChanged();
    return;
#endif

    const int fd = ::socket(PF_CAN, SOCK_RAW, CAN_RAW);
    if (fd < 0) {
        qWarning().noquote() << kLogTag << "cannot create CAN socket:" << std::strerror(errno);
        return;
    }

    ifreq ifr{};
    const QByteArray ifaceName = m_iface.toLatin1();
    std::strncpy(ifr.ifr_name, ifaceName.constData(), IFNAMSIZ - 1);
    if (::ioctl(fd, SIOCGIFINDEX, &ifr) < 0) {
        // The usual case on a bench without the harness attached, and on the
        // vehicle before the interface is brought up. Not an error worth
        // shouting about every five seconds.
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

    // Non-blocking: a bus-off condition or a full transmit queue would
    // otherwise stall write() on the GUI thread and freeze the head unit.
    const int flags = ::fcntl(fd, F_GETFL, 0);
    if (flags >= 0)
        ::fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    m_fd   = fd;
    m_open = true;
    qInfo().noquote() << kLogTag << "using" << m_iface;
    emit availableChanged();
}

void AmbientLightManager::closeBus()
{
    if (m_fd >= 0)
        ::close(m_fd);
    m_fd = -1;

    if (!m_open)
        return;
    m_open = false;
    emit availableChanged();
}

void AmbientLightManager::setOn(bool on)
{
    if (m_on == on)
        return;
    m_on = on;
    emit onChanged();
    save();
    scheduleFlush();
}

void AmbientLightManager::setColor(const QColor &color)
{
    if (!color.isValid() || m_color == color)
        return;
    m_color = color;
    emit colorChanged();
    save();
    scheduleFlush();
}

void AmbientLightManager::setBrightness(int brightness)
{
    const int clamped = qBound(0, brightness, 255);
    if (m_brightness == clamped)
        return;
    m_brightness = clamped;
    emit brightnessChanged();
    save();
    scheduleFlush();
}

void AmbientLightManager::setMode(int mode)
{
    const int clamped = qBound(int(ModeStatic), mode, int(ModeRainbow));
    if (m_mode == clamped)
        return;
    m_mode = clamped;
    emit modeChanged();
    save();
    scheduleFlush();
}

void AmbientLightManager::setSpeed(int speed)
{
    const int clamped = qBound(int(SpeedMin), speed, int(SpeedMax));
    if (m_speed == clamped)
        return;
    m_speed = clamped;
    emit speedChanged();
    save();
    scheduleFlush();
}

void AmbientLightManager::setZoneMask(int mask)
{
    const int clamped = mask & ZoneAll;
    if (m_zoneMask == clamped)
        return;
    m_zoneMask = clamped;
    emit zoneMaskChanged();
    save();
    scheduleFlush();
}

void AmbientLightManager::resend()
{
    scheduleFlush();
}

void AmbientLightManager::scheduleFlush()
{
    // start() on a running single-shot timer restarts it, so a continuous drag
    // sends nothing until it pauses — which is wrong for a slider. isActive()
    // keeps the original deadline, so updates go out at a steady rate and the
    // last one is always carried by the final expiry.
    if (!m_flush.isActive())
        m_flush.start();
}

void AmbientLightManager::flush()
{
    if (!available()) {
        openBus();
        if (!available()) {
            m_reopen.start();
            return;
        }
    }

    can_frame frame{};
    frame.can_id  = kCanId;
    frame.can_dlc = 8;
    frame.data[0] = m_on ? quint8(m_mode) : kModeOff;
    frame.data[1] = quint8(m_color.red());
    frame.data[2] = quint8(m_color.green());
    frame.data[3] = quint8(m_color.blue());
    frame.data[4] = quint8(m_brightness);
    frame.data[5] = quint8(m_speed);
    frame.data[6] = quint8(m_zoneMask);

    /*
     * Drop a frame that says nothing new.
     *
     * A drag repeatedly lands on values it has already sent — the hue bar is
     * the worst, since neighbouring pixels often round to the same colour — and
     * the timer always fires once more after the last change, which would
     * otherwise resend the final state verbatim. Suppressing these is free and
     * costs the ECU nothing to receive.
     */
    if (m_havePrevious
        && std::memcmp(m_lastPayload, frame.data, sizeof(m_lastPayload)) == 0)
        return;

    frame.data[7] = m_sequence++;

#if AMBIENT_CAN_SIMULATE
    std::memcpy(m_lastPayload, frame.data, sizeof(m_lastPayload));
    m_havePrevious = true;

    // candump's layout, so a bench trace and a real one can be read the same way
    // and diffed against each other.
    QString bytes;
    for (int i = 0; i < frame.can_dlc; ++i)
        bytes += QStringLiteral("%1 ").arg(frame.data[i], 2, 16, QLatin1Char('0')).toUpper();
    qInfo().noquote() << QStringLiteral("%1 sim   %2  %3   [%4]  %5")
                             .arg(QLatin1String(kLogTag), m_iface,
                                  QStringLiteral("%1").arg(frame.can_id, 3, 16).toUpper(),
                                  QString::number(frame.can_dlc), bytes.trimmed());
    return;
#endif

    const ssize_t written = ::write(m_fd, &frame, sizeof(frame));
    if (written == sizeof(frame)) {
        // Recorded only once it is genuinely on the wire: a frame that failed
        // to send must not be suppressed as a duplicate on the retry.
        std::memcpy(m_lastPayload, frame.data, sizeof(m_lastPayload));
        m_havePrevious = true;
        return;
    }

    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == ENOBUFS) {
        // Transmit queue full. Nothing is lost that matters: the next flush
        // carries the current state anyway, which is the whole point of
        // sending intent rather than a stream of deltas.
        scheduleFlush();
        return;
    }

    qWarning().noquote() << kLogTag << "write failed:" << std::strerror(errno);
    closeBus();     // ENETDOWN and friends — reopen when the interface returns
    m_reopen.start();
}

/*
 * Persisted so the cabin comes back the way the driver left it. The ECU cannot
 * help here: it has no storage of its own for this and comes up dark, so the
 * head unit is the only thing that remembers.
 */
void AmbientLightManager::save() const
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("ambient"));
    settings.setValue(QStringLiteral("on"), m_on);
    settings.setValue(QStringLiteral("color"), m_color.name());
    settings.setValue(QStringLiteral("brightness"), m_brightness);
    settings.setValue(QStringLiteral("mode"), m_mode);
    settings.setValue(QStringLiteral("speed"), m_speed);
    settings.setValue(QStringLiteral("zoneMask"), m_zoneMask);
}

void AmbientLightManager::restore()
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("ambient"));
    m_on         = settings.value(QStringLiteral("on"), false).toBool();
    m_brightness = qBound(0, settings.value(QStringLiteral("brightness"), 128).toInt(), 255);
    m_mode       = qBound(int(ModeStatic),
                          settings.value(QStringLiteral("mode"), ModeStatic).toInt(),
                          int(ModeRainbow));
    m_speed      = qBound(int(SpeedMin),
                          settings.value(QStringLiteral("speed"), 5).toInt(),
                          int(SpeedMax));
    // A saved mask of 0 would restore a strip that is "on" but entirely dark,
    // which reads as broken. Fall back to all six.
    m_zoneMask   = settings.value(QStringLiteral("zoneMask"), ZoneAll).toInt() & ZoneAll;
    if (m_zoneMask == 0)
        m_zoneMask = ZoneAll;

    const QColor saved(settings.value(QStringLiteral("color"),
                                      QStringLiteral("#ff8000")).toString());
    if (saved.isValid())
        m_color = saved;
}
