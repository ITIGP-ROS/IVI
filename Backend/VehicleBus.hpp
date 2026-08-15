#pragma once
#include <QObject>
#include <QSocketNotifier>
#include <QString>
#include <QTimer>

/*
 * VehicleBus — the car's own telemetry, read off CAN.
 *
 * Receive-only. Nothing here ever writes to the bus: this node is a listener on
 * a frame the Tiva broadcasts anyway, so it can never contend for arbitration
 * or disturb the control loop it is watching. Sending lives in
 * AmbientLightManager and WifiCredSender, which own their own sockets.
 *
 * Frame 0x200 VehicleStatus, TIVA -> CLUSTER, DLC 8, 10 Hz, little-endian
 * (see vehicle.dbc in the DBC repo, which is the authority for this layout):
 *
 *   bytes 0-1  speed    u16, 1 LSB = 1 m/min
 *   byte  2    gear     0 = N, 1 = D, 2 = R   (no Park; no parking pawl)
 *   bytes 3-4  trip_m   u16, metres, reset-relative
 *   bytes 5-7  odo_m    u24, metres, lifetime, held in the Tiva's EEPROM
 *
 * The unit is m/min and NOT the 0.1 km/h that the DBC repo's README and
 * HANDOFF_README still describe. Those two documents predate the Tiva v2
 * change (DBC commit "Tiva v2: VehicleStatus + BatteryStatus units/layout");
 * vehicle.dbc itself carries the change and says so in its own comment, so it
 * wins. Decoding this frame with the README's scale reads 6x low and looks
 * merely sluggish rather than obviously broken, which is the dangerous kind of
 * wrong — hence this note rather than a silent constant.
 *
 * The DBC lists CLUSTER as the only receiver of 0x200. That is a statement
 * about intent, not about the wire: CAN is a broadcast bus and the Jetson is a
 * physical node on it, so the frame arrives here regardless. It does matter for
 * one thing — `cantools generate_c_source` filters by node, so a generated
 * decoder built for JETSON would omit VehicleStatus entirely. That is why the
 * decode below is written by hand against the DBC rather than generated.
 */
class VehicleBus : public QObject {
    Q_OBJECT

    // The socket is open. Says nothing about whether the Tiva is talking.
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // Frames are actually arriving. This is the one to trust a reading against.
    Q_PROPERTY(bool live      READ live      NOTIFY liveChanged)

    Q_PROPERTY(double speedMps   READ speedMps   NOTIFY speedChanged)
    Q_PROPERTY(double speedKmh   READ speedKmh   NOTIFY speedChanged)
    Q_PROPERTY(int    gear       READ gear       NOTIFY gearChanged)
    Q_PROPERTY(QString gearLabel READ gearLabel  NOTIFY gearChanged)
    Q_PROPERTY(int    tripMetres READ tripMetres NOTIFY tripMetresChanged)
    Q_PROPERTY(int    odoMetres  READ odoMetres  NOTIFY odoMetresChanged)

public:
    explicit VehicleBus(QObject *parent = nullptr);
    ~VehicleBus() override;

    bool    available()  const { return m_fd >= 0; }
    bool    live()       const { return m_live; }
    double  speedMps()   const { return m_speedMps; }
    double  speedKmh()   const { return m_speedMps * 3.6; }
    int     gear()       const { return m_gear; }
    QString gearLabel()  const;
    int     tripMetres() const { return m_tripMetres; }
    int     odoMetres()  const { return m_odoMetres; }

    enum Gear { GearNeutral = 0, GearDrive = 1, GearReverse = 2 };

signals:
    void availableChanged();
    void liveChanged();
    void speedChanged();
    void gearChanged();
    void tripMetresChanged();
    void odoMetresChanged();

private:
    void openBus();
    void closeBus();
    void readFrames();
    void setLive(bool live);

    int              m_fd       = -1;
    QSocketNotifier *m_notifier = nullptr;

    /*
     * Which SocketCAN interface to listen on. IVI_CAN_IFACE overrides it, the
     * same variable AmbientLightManager reads — the two are different sockets
     * but the same physical bus, and having them disagree about which one would
     * be a trap. Point it at a vcan to replay a candump on a bench.
     */
    QString m_iface;

    bool   m_live       = false;
    double m_speedMps   = 0.0;
    int    m_gear       = GearNeutral;
    int    m_tripMetres = 0;
    int    m_odoMetres  = 0;

    /*
     * How long silence is tolerated before the reading stops being believed.
     *
     * 0x200 is a 10 Hz cyclic frame, so 500 ms is five missed frames — long
     * enough that a scheduling hiccup or a single bus retransmission does not
     * flicker the source, short enough that a dead Tiva does not leave a stale
     * speed on screen for a driver to read as current.
     */
    QTimer m_stale;

    // can0 is rarely up when the UI starts, the same way the network is not.
    // One failed open at boot must not cost the whole session.
    QTimer m_reopen;
};
