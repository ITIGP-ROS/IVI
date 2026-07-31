#pragma once
#include <QColor>
#include <QObject>
#include <QString>
#include <QTimer>

/*
 * AmbientLightManager — the cabin's WS2812 strip, driven over CAN.
 *
 * Intent, not pixels. The head unit sends "static, this colour, this
 * brightness" and the ESP32 renders it; it does not stream frames. Six LEDs is
 * 18 bytes of pixel data, which would need ISO-TP segmentation on every
 * animation tick — a continuous flood on a bus that also carries ultrasonic
 * telemetry and OTA. Sending intent keeps the whole command inside one classic
 * 8-byte frame, and the strip keeps doing the right thing when the head unit
 * reboots.
 *
 * Deliberately no SecOC here, unlike WifiCredSender: a MAC plus freshness would
 * not fit in 8 bytes and would drag ISO-TP back in for what is a comfort
 * feature. The safety envelope belongs in the ESP32 instead — it must refuse
 * unsafe modes whatever arrives on the wire, because anything can inject on a
 * shared bus. Nothing here can be trusted to be the only sender.
 *
 * Frame layout, CAN 0x500 (see kCanId — a high ID on purpose, so decoration
 * always loses arbitration against ultrasonic 0x160 and warnings 0x400):
 *
 *   byte 0  mode        0 = off, 1 = static
 *   byte 1  red
 *   byte 2  green
 *   byte 3  blue
 *   byte 4  brightness  0-255
 *   byte 5  speed       effect period, unused while static
 *   byte 6  zone mask   one bit per LED, 0x3F = all six
 *   byte 7  sequence    rolling, lets the ECU notice a dropped update
 */
class AmbientLightManager : public QObject {
    Q_OBJECT

    Q_PROPERTY(bool   available  READ available  NOTIFY availableChanged)
    Q_PROPERTY(bool   on         READ on         WRITE setOn         NOTIFY onChanged)
    Q_PROPERTY(QColor color      READ color      WRITE setColor      NOTIFY colorChanged)
    Q_PROPERTY(int    brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)
    // 1 static, 2 breathe, 3 chase, 4 scanner, 5 rainbow. Mode 0 on the wire
    // means off and is derived from `on`, so it is never stored here — turning
    // the strip off and back on must return to the effect that was running.
    Q_PROPERTY(int    mode       READ mode       WRITE setMode       NOTIFY modeChanged)
    Q_PROPERTY(int    speed      READ speed      WRITE setSpeed      NOTIFY speedChanged)
    // One bit per LED, bit 0 = first. 0x3F is all six.
    Q_PROPERTY(int    zoneMask   READ zoneMask   WRITE setZoneMask   NOTIFY zoneMaskChanged)

public:
    explicit AmbientLightManager(QObject *parent = nullptr);
    ~AmbientLightManager() override;

    // Not "m_fd >= 0": in simulation there is no descriptor but the page must
    // still behave as though the ECU were there.
    bool   available()  const { return m_open; }
    bool   on()         const { return m_on; }
    QColor color()      const { return m_color; }
    int    brightness() const { return m_brightness; }
    int    mode()       const { return m_mode; }
    int    speed()      const { return m_speed; }
    int    zoneMask()   const { return m_zoneMask; }

    void setOn(bool on);
    void setColor(const QColor &color);
    void setBrightness(int brightness);
    void setMode(int mode);
    void setSpeed(int speed);
    void setZoneMask(int mask);

    static constexpr int ModeStatic  = 1;
    static constexpr int ModeRainbow = 5;
    static constexpr int SpeedMin    = 1;
    static constexpr int SpeedMax    = 10;
    static constexpr int ZoneAll     = 0x3F;

    // Re-assert the current state. For after the ECU reboots — it comes up dark
    // and has no way to ask what it was showing.
    Q_INVOKABLE void resend();

signals:
    void availableChanged();
    void onChanged();
    void colorChanged();
    void brightnessChanged();
    void modeChanged();
    void speedChanged();
    void zoneMaskChanged();

private:
    void openBus();
    void closeBus();
    void scheduleFlush();
    void flush();
    void save() const;
    void restore();

    int  m_fd   = -1;
    bool m_open = false;

    /*
     * Which SocketCAN interface to send on. Overridable with IVI_CAN_IFACE, the
     * same way the media libraries take IVI_MUSIC_DIR — so a bench without the
     * lighting ECU can point this at a vcan and exercise the whole path without
     * having to rename or displace a real can0.
     */
    QString m_iface;

    bool   m_on         = false;
    QColor m_color      = QColor(255, 128, 0);
    int    m_brightness = 128;
    int    m_mode       = ModeStatic;
    int    m_speed      = 5;
    int    m_zoneMask   = ZoneAll;
    quint8 m_sequence   = 0;

    // Last payload actually sent, bytes 0-6 (the sequence counter is excluded
    // because it changes every frame by definition). Lets flush() drop a frame
    // that would tell the ECU nothing it does not already know.
    quint8 m_lastPayload[7] = {};
    bool   m_havePrevious   = false;

    /*
     * Dragging a brightness slider emits changes every frame. Writing one CAN
     * frame per emission would put hundreds on the bus for a single gesture, so
     * changes are collapsed and sent at a fixed rate; the final value always
     * goes out because the timer fires once more after the last change.
     */
    QTimer m_flush;

    // can0 usually is not up yet when the UI starts, same as the network. One
    // failed open at startup must not disable the feature for the session.
    QTimer m_reopen;

    /*
     * Cyclic re-assertion of the current state.
     *
     * The ECU boots dark and keeps no state of its own, so a purely
     * event-driven link leaves it dark forever after it reboots — the head unit
     * has already sent the only frame it was going to send. Re-stating
     * periodically is how state signals normally work on CAN, and it makes an
     * ECU reset heal itself instead of needing someone to poke the UI.
     */
    QTimer m_heartbeat;
};
