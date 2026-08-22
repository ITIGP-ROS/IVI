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
        "[\"amigo\", \"weather\", \"cairo\", \"giza\", \"milan\", \"media\", \"settings\", \"wifi\", \"bluetooth\", \"open\", \"back\", \"home\", \"ambient\", \"light\", \"drive\", \"view\", \"navigation\", \
         \"play\", \"pause\", \"resume\", \"stop\", \"next\", \"previous\", \"radio\", \"music\", \"audio\", \"video\", \"volume\", \"up\", \"down\", \"mute\", \"unmute\", \"about\", \"brightness\", \"max\", \"min\", \"[unk]\"]"
    );
    vosk_set_log_level(-1); // silence Vosk logs

    // Watch for the capture device appearing, vanishing, or being swapped.
    // ivi-remote-mic's virtual mic does all three across a service restart.
    m_devices = new QMediaDevices(this);
    connect(m_devices, &QMediaDevices::audioInputsChanged,
            this, &SpeechManager::onInputsChanged);

    m_retry.setInterval(2000);
    connect(&m_retry, &QTimer::timeout, this, [this]() {
        if (!m_listening) startListening();
    });
}

SpeechManager::~SpeechManager(){
    stopListening();
    if(m_recognizer) vosk_recognizer_free(m_recognizer);
    if(m_model)      vosk_model_free(m_model);
}

void SpeechManager::startListening(){
    if(m_listening || !m_recognizer) return;

    if (!openAudio()) {
        // Keep trying rather than reporting a microphone we do not have. This
        // is the boot race: the sound server is usually up within a few
        // seconds of us asking.
        m_retry.start();
        return;
    }

    m_retry.stop();
    m_listening = true;
    emit listeningChanged();
}

bool SpeechManager::openAudio(){
    const QAudioDevice dev = QMediaDevices::defaultAudioInput();
    if (dev.isNull()) {
        if (!m_warnedNoDevice) {
            m_warnedNoDevice = true;
            qWarning() << "[speech] no audio input yet — retrying every"
                       << m_retry.interval() << "ms";
        }
        return false;
    }

    QAudioFormat fmt;
    fmt.setSampleRate(16000);
    fmt.setChannelCount(1);
    fmt.setSampleFormat(QAudioFormat::Int16);

    m_audio = new QAudioSource(dev, fmt, this);
    connect(m_audio, &QAudioSource::stateChanged,
            this, &SpeechManager::onAudioStateChanged);

    m_audioDevice = m_audio->start();

    // start() hands back a QIODevice even when it failed, which is what made
    // the original silently claim to be listening. The error code is the only
    // honest answer.
    if (!m_audioDevice || m_audio->error() != QAudio::NoError) {
        qWarning() << "[speech] could not open" << dev.description()
                   << "- error" << (m_audio ? int(m_audio->error()) : -1);
        closeAudio();
        return false;
    }

    connect(m_audioDevice, &QIODevice::readyRead, this, &SpeechManager::onAudioData);
    m_openDevice     = dev;
    m_warnedNoDevice = false;
    qInfo() << "[speech] listening on" << dev.description();
    return true;
}

void SpeechManager::closeAudio(){
    if (m_audio) {
        m_audio->stop();
        m_audio->deleteLater();
    }
    m_audio       = nullptr;
    m_audioDevice = nullptr;
}

void SpeechManager::onAudioStateChanged(QAudio::State state){
    if (!m_listening || state != QAudio::StoppedState)
        return;
    if (!m_audio || m_audio->error() == QAudio::NoError)
        return;      // a clean stop is stopListening() doing its job

    qWarning() << "[speech] capture stopped unexpectedly (error"
               << int(m_audio->error()) << ") — reopening";
    closeAudio();
    m_listening = false;
    emit listeningChanged();
    startListening();
}

void SpeechManager::onInputsChanged(){
    // Only act on a device swap. The signal also fires for outputs and for
    // devices we are not using.
    const QAudioDevice now = QMediaDevices::defaultAudioInput();

    if (!m_listening) {
        if (!now.isNull()) startListening();   // the mic finally showed up
        return;
    }

    if (now.isNull() || now.id() == m_openDevice.id())
        return;

    qInfo() << "[speech] default input changed to" << now.description()
            << "— reopening";
    closeAudio();
    m_listening = false;
    emit listeningChanged();
    startListening();
}

void SpeechManager::stopListening(){
    m_retry.stop();
    if(!m_listening) return;

    closeAudio();

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