#pragma once
#include <QObject>
#include <QAudio>
#include <QAudioDevice>
#include <QAudioSource>
#include <QMediaDevices>
#include <QThread>
#include <QTimer>
#include "vosk_api.h"

class SpeechManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool listening READ listening NOTIFY listeningChanged)
    Q_PROPERTY(QString partialResult READ partialResult NOTIFY partialResultChanged)

public:
    explicit SpeechManager(QObject *parent = nullptr);
    ~SpeechManager();

    bool    listening()     const { return m_listening; }
    QString partialResult() const { return m_partial;   }

    Q_INVOKABLE void startListening();
    Q_INVOKABLE void stopListening();

signals:
    void listeningChanged();
    void partialResultChanged();
    void resultReady(const QString &text);

private slots:
    void onAudioData();

    // The capture device died, or the set of inputs changed under us.
    void onAudioStateChanged(QAudio::State state);
    void onInputsChanged();

private:
    /*
     * Opening the microphone is RETRIED, and re-done when the device changes.
     *
     * It used to be opened exactly once, from Component.onCompleted, against
     * whatever QMediaDevices::defaultAudioInput() happened to return at that
     * instant — with the result thrown away. Two things broke it, both seen on
     * the head unit:
     *
     *   - ivi-app.service is ordered after weston but NOT after PulseAudio, so
     *     the app regularly wins the race and calls this before there is a
     *     sound server at all (the "PulseAudio not ready" lines in the journal
     *     are the same race hitting the volume control). QAudioSource::start()
     *     then fails, `listening` was set true anyway, and voice input was dead
     *     for the entire life of the process with the UI claiming otherwise.
     *
     *   - The microphone is a virtual device (ivi-remote-mic's null sink plus a
     *     remap source). Restarting that service destroys and recreates it, so
     *     the device this was bound to simply disappears — again permanently,
     *     because nothing reopened it.
     *
     * Playback never showed the problem because Qt reopens the sink per media
     * item, which is why "audio works but voice does not" was the symptom.
     */
    bool openAudio();
    void closeAudio();
    VoskModel      *m_model      = nullptr;
    VoskRecognizer *m_recognizer = nullptr;
    QAudioSource   *m_audio      = nullptr;
    QIODevice      *m_audioDevice = nullptr;
    bool            m_listening  = false;
    QString         m_partial;

    QMediaDevices  *m_devices = nullptr;
    QAudioDevice    m_openDevice;   // what we actually opened, to spot a swap
    QTimer          m_retry;
    bool            m_warnedNoDevice = false;   // one line, not one per retry
};