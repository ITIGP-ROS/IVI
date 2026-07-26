#include "SystemVolumeController.hpp"
#include <QDebug>
#include <QSocketNotifier>

SystemVolumeController::SystemVolumeController(QObject *parent) : QObject(parent){
    connectPulse();
}

SystemVolumeController::~SystemVolumeController(){
    if(m_pulseTimer) {
        m_pulseTimer->stop();
        delete m_pulseTimer;
    }
    if(m_context) {
        pa_context_disconnect(m_context);
        pa_context_unref(m_context);
    }
    if(m_mainloop) {
        pa_mainloop_free(m_mainloop);
    }
}

void SystemVolumeController::connectPulse(){
    m_mainloop = pa_mainloop_new();
    pa_mainloop_api *api = pa_mainloop_get_api(m_mainloop);

    m_context = pa_context_new(api, "IVI-Dashboard");
    pa_context_set_state_callback(m_context, contextStateCallback, this);
    pa_context_connect(m_context, nullptr, PA_CONTEXT_NOFLAGS, nullptr);

    // Use QTimer to continuously iterate the PulseAudio mainloop
    m_pulseTimer = new QTimer(this);
    m_pulseTimer->setInterval(50); // 50ms
    connect(m_pulseTimer, &QTimer::timeout, this, &SystemVolumeController::iteratePulse);
    m_pulseTimer->start();
}

void SystemVolumeController::iteratePulse(){
    if(!m_mainloop) return;
    int ret = 0;
    pa_mainloop_iterate(m_mainloop, 0, &ret);
}

void SystemVolumeController::contextStateCallback(pa_context *c, void *userdata){
    auto *self = static_cast<SystemVolumeController*>(userdata);
    self->onPulseStateChanged();
}

void SystemVolumeController::onPulseStateChanged(){
    if(!m_context) return;

    switch(pa_context_get_state(m_context)) {
    case PA_CONTEXT_READY:
        qDebug() << "PulseAudio: Connected";
        m_ready = true;
        updateSinkInfo();
        break;
    case PA_CONTEXT_FAILED:
        qWarning() << "PulseAudio: Connection failed -" << pa_strerror(pa_context_errno(m_context));
        m_ready = false;
        break;
    case PA_CONTEXT_TERMINATED:
        qWarning() << "PulseAudio: Connection terminated";
        m_ready = false;
        break;
    default:
        break;
    }
}

void SystemVolumeController::updateSinkInfo(){
    if(!m_ready || !m_context) return;

    pa_operation *op = pa_context_get_sink_info_list(m_context, sinkInfoCallback, this);
    if(op) pa_operation_unref(op);
}

void SystemVolumeController::sinkInfoCallback(pa_context *, const pa_sink_info *i, int eol, void *userdata){
    if(eol > 0) return;
    auto *self = static_cast<SystemVolumeController*>(userdata);
    
    self->m_sinkIndex = i->index;
    int newVolume = static_cast<int>(pa_cvolume_avg(&i->volume) * 100.0 / PA_VOLUME_NORM);
    bool newMuted = i->mute;
    
    if(self->m_volume != newVolume) {
        self->m_volume = newVolume;
        emit self->volumeChanged(self->m_volume);
    }
    if(self->m_muted != newMuted) {
        self->m_muted = newMuted;
        emit self->mutedChanged(self->m_muted);
    }
}

int SystemVolumeController::volume() const{
    return m_volume;
}

bool SystemVolumeController::muted() const{
    return m_muted;
}

void SystemVolumeController::setVolume(int volume){
    volume = qBound(0, volume, 100);
    if(m_volume == volume) return;
    
    m_volume = volume;
    emit volumeChanged(m_volume);
    applyVolume();
}

void SystemVolumeController::setMuted(bool muted){
    if(m_muted == muted) return;
    
    m_muted = muted;
    emit mutedChanged(m_muted);
    applyMute();
}

void SystemVolumeController::toggleMute(){
    setMuted(!m_muted);
}

void SystemVolumeController::applyVolume(){
    if(!m_ready || !m_context){
        qWarning() << "PulseAudio not ready, cannot set volume";
        return;
    }

    pa_cvolume cv;
    pa_cvolume_set(&cv, 2, static_cast<pa_volume_t>(m_volume * PA_VOLUME_NORM / 100.0));

    pa_operation *op = pa_context_set_sink_volume_by_index(m_context, m_sinkIndex, &cv, successCallback, this);
    if(op) pa_operation_unref(op);
}

void SystemVolumeController::applyMute(){
    if(!m_ready || !m_context){
        qWarning() << "PulseAudio not ready, cannot set mute";
        return;
    }

    pa_operation *op = pa_context_set_sink_mute_by_index(m_context, m_sinkIndex, m_muted ? 1 : 0, successCallback, this);
    if(op) pa_operation_unref(op);
}

void SystemVolumeController::successCallback(pa_context *, int success, void *userdata){
    auto *self = static_cast<SystemVolumeController*>(userdata);
    if(!success){
        qWarning() << "PulseAudio operation failed";
    }
    else{
        // Refresh sink info after successful operation to sync state
        self->updateSinkInfo();
    }
}