#pragma once
#include <QObject>
#include <QAudioSource>
#include <QMediaDevices>
#include <QThread>
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

private:
    VoskModel      *m_model      = nullptr;
    VoskRecognizer *m_recognizer = nullptr;
    QAudioSource   *m_audio      = nullptr;
    QIODevice      *m_audioDevice = nullptr;
    bool            m_listening  = false;
    QString         m_partial;
};