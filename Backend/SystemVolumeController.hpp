#pragma once

#include <QObject>
#include <QTimer>
#include <pulse/pulseaudio.h>

class SystemVolumeController : public QObject{
    Q_OBJECT
    Q_PROPERTY(int volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY mutedChanged)

public:
    // Above 100 is software boost past the 0 dB reference. Exposed to QML so the
    // sliders and the C++ clamp cannot drift apart.
    static constexpr int kMaxVolumePercent = 150;
    Q_PROPERTY(int maxVolume READ maxVolume CONSTANT)

    explicit SystemVolumeController(QObject *parent = nullptr);
    ~SystemVolumeController();

    int volume() const;
    int maxVolume() const { return kMaxVolumePercent; }
    bool muted() const;

    Q_INVOKABLE void setVolume(int volume);   // 0 - kMaxVolumePercent
    Q_INVOKABLE void setMuted(bool muted);
    Q_INVOKABLE void toggleMute();

signals:
    void volumeChanged(int volume);
    void mutedChanged(bool muted);

private:
    void connectPulse();
    void updateSinkInfo();
    void applyVolume();
    void applyMute();
    void onPulseStateChanged();
    void iteratePulse();

    static void contextStateCallback(pa_context *c, void *userdata);
    static void sinkInfoCallback(pa_context *c, const pa_sink_info *i, int eol, void *userdata);
    static void successCallback(pa_context *c, int success, void *userdata);

    pa_mainloop *m_mainloop = nullptr;
    pa_context *m_context = nullptr;
    uint32_t m_sinkIndex = 0;
    int m_volume = 50;
    bool m_muted = false;
    bool m_ready = false;
    QTimer *m_pulseTimer = nullptr;
};