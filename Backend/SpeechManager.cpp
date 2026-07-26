#include "SpeechManager.hpp"
#include <QJsonDocument>
#include <QJsonObject>
#include <QAudioFormat>
#include <QDebug>
#include <QCoreApplication>
#include <QDir>

SpeechManager::SpeechManager(QObject *parent) : QObject(parent){
    vosk_set_log_level(0);

    QString modelPath = QDir(QCoreApplication::applicationDirPath()).filePath("../assets/models/vosk");
    modelPath = QDir::cleanPath(modelPath);
    qDebug() << "Vosk: loading model from:" << modelPath;

    m_model = vosk_model_new(modelPath.toUtf8().constData());
    if(!m_model){
        qWarning() << "Vosk: failed to load model at:" << modelPath;
        return;
    }
    qDebug() << "Vosk: model loaded OK";

    m_recognizer = vosk_recognizer_new(m_model, 16000.0);
    if (!m_recognizer) {
        qWarning() << "Vosk: failed to create recognizer";
        return;
    }

    // Only recognize these words — ignore everything else
    vosk_recognizer_set_grm(m_recognizer,
        "[\"weather\", \"cairo\", \"giza\", \"milan\", \"hvac\", \"media\", \"settings\", \"wifi\", \"bluetooth\", \"open\", \"back\", \"home\", \
         \"play\", \"pause\", \"stop\", \"radio\", \"audio\", \"video\", \"volume\", \"up\", \"down\", \"mute\", \"unmute\", \"about\", \"[unk]\", \
         \"fan\", \"temp\"]"
    );
    vosk_set_log_level(-1); // silence Vosk logs
}

SpeechManager::~SpeechManager(){
    stopListening();
    if(m_recognizer) vosk_recognizer_free(m_recognizer);
    if(m_model)      vosk_model_free(m_model);
}

void SpeechManager::startListening(){
    if(m_listening || !m_recognizer) return;

    QAudioFormat fmt;
    fmt.setSampleRate(16000);
    fmt.setChannelCount(1);
    fmt.setSampleFormat(QAudioFormat::Int16);

    m_audio = new QAudioSource(QMediaDevices::defaultAudioInput(), fmt, this);
    m_audioDevice = m_audio->start();

    connect(m_audioDevice, &QIODevice::readyRead, this, &SpeechManager::onAudioData);

    m_listening = true;
    emit listeningChanged();
}

void SpeechManager::stopListening(){
    if(!m_listening) return;

    m_audio->stop();
    m_audio->deleteLater();
    m_audio = nullptr;
    m_audioDevice = nullptr;

    // Get final result
    const char *res = vosk_recognizer_final_result(m_recognizer);
    QJsonObject obj = QJsonDocument::fromJson(res).object();
    QString text = obj["text"].toString().trimmed();
    if(!text.isEmpty()) emit resultReady(text);

    vosk_recognizer_reset(m_recognizer);

    m_listening = false;
    emit listeningChanged();
}

void SpeechManager::onAudioData(){
    if(!m_audioDevice || !m_recognizer) return;

    QByteArray data = m_audioDevice->readAll();
    if(data.isEmpty()) return;

    int accepted = vosk_recognizer_accept_waveform(
        m_recognizer,
        reinterpret_cast<const char*>(data.constData()),
        data.size()
    );

    if(accepted) {
        // Full sentence recognized
        const char *res = vosk_recognizer_result(m_recognizer);
        QJsonObject obj = QJsonDocument::fromJson(res).object();
        QString text = obj["text"].toString().trimmed();
        if(!text.isEmpty()) emit resultReady(text);
    }
    else {
        // Partial result(live feedback while user is still speaking)
        const char *partial = vosk_recognizer_partial_result(m_recognizer);
        QJsonObject obj = QJsonDocument::fromJson(partial).object();
        m_partial = obj["partial"].toString();
        emit partialResultChanged();
    }
}