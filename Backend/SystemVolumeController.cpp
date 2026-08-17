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
    case PA_CONTEXT_READY: {
        qDebug() << "PulseAudio: Connected";
        m_ready = true;

        // Follow the server instead of sampling it once. The head unit's output
        // is a USB headset and the remote-mic service loads and unloads a null
        // sink at runtime, so both the default sink and its index change while
        // the app is running; without this we would keep writing to a sink that
        // is no longer the one playing. It also keeps the sliders honest when
        // something else changes the volume.
        pa_context_set_subscribe_callback(m_context, subscribeCallback, this);
        pa_operation *sub = pa_context_subscribe(
            m_context,
            static_cast<pa_subscription_mask_t>(PA_SUBSCRIPTION_MASK_SINK
                                                | PA_SUBSCRIPTION_MASK_SERVER),
            nullptr, nullptr);
        if(sub) pa_operation_unref(sub);

        updateSinkInfo();
        break;
    }
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

    // Ask the server which sink is the default and look up that one by name.
    //
    // This used to walk the whole sink list and keep whichever sink came last,
    // which is only ever right by accident. On a dev laptop with a single sink
    // it is right; on the head unit the remote-mic service loads a null sink
    // (`ivi_mic`) that enumerates after the speakers, so every volume and mute
    // the driver set went to a sink nothing plays out of.
    pa_operation *op = pa_context_get_server_info(m_context, serverInfoCallback, this);
    if(op) pa_operation_unref(op);
}

void SystemVolumeController::serverInfoCallback(pa_context *c, const pa_server_info *i, void *userdata){
    auto *self = static_cast<SystemVolumeController*>(userdata);
    if(!i || !i->default_sink_name){
        qWarning() << "PulseAudio: no default sink reported";
        return;
    }

    pa_operation *op = pa_context_get_sink_info_by_name(c, i->default_sink_name,
                                                        sinkInfoCallback, self);
    if(op) pa_operation_unref(op);
}

void SystemVolumeController::sinkInfoCallback(pa_context *, const pa_sink_info *i, int eol, void *userdata){
    // eol > 0 is the end-of-list marker and eol < 0 an error; neither carries a
    // sink, and `i` is null for both. The old `eol > 0` test let the error case
    // through and dereferenced that null pointer.
    if(eol != 0 || !i) return;
    auto *self = static_cast<SystemVolumeController*>(userdata);

    self->m_sinkIndex = i->index;
    // Straight from the sink: the server validates a submitted pa_cvolume
    // against the sink's channel map and rejects the operation outright on a
    // mismatch, which is why a hardcoded 2 failed against a mono sink.
    self->m_sinkChannels = qMax<uint8_t>(1, i->channel_map.channels);

    // qRound, not truncation. PA stores volume as a fraction of PA_VOLUME_NORM,
    // so most percentages do not survive the round trip exactly — truncating
    // turned 47 back into 46, and since every set is followed by a read-back the
    // slider crept downwards by a percent each time it was touched.
    int newVolume = qRound(pa_cvolume_avg(&i->volume) * 100.0 / PA_VOLUME_NORM);
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
    // PA_VOLUME_NORM is the 0 dB reference, not a ceiling — PulseAudio accepts
    // above it, which is how "allow volume above 100%" works on the desktop.
    // Past 100 this is digital gain: it makes quiet sources usable but will
    // clip material that is already near full scale.
    volume = qBound(0, volume, kMaxVolumePercent);
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
    if(m_sinkIndex == PA_INVALID_INDEX){
        qWarning() << "PulseAudio: default sink not resolved, cannot set volume";
        return;
    }

    pa_cvolume cv;
    pa_cvolume_set(&cv, m_sinkChannels,
                   static_cast<pa_volume_t>(qRound(m_volume * PA_VOLUME_NORM / 100.0)));

    pa_operation *op = pa_context_set_sink_volume_by_index(m_context, m_sinkIndex, &cv, successCallback, this);
    if(op) pa_operation_unref(op);
}

void SystemVolumeController::applyMute(){
    if(!m_ready || !m_context){
        qWarning() << "PulseAudio not ready, cannot set mute";
        return;
    }
    if(m_sinkIndex == PA_INVALID_INDEX){
        qWarning() << "PulseAudio: default sink not resolved, cannot set mute";
        return;
    }

    pa_operation *op = pa_context_set_sink_mute_by_index(m_context, m_sinkIndex, m_muted ? 1 : 0, successCallback, this);
    if(op) pa_operation_unref(op);
}

void SystemVolumeController::subscribeCallback(pa_context *, pa_subscription_event_type_t t,
                                               uint32_t, void *userdata){
    auto *self = static_cast<SystemVolumeController*>(userdata);

    // A sink event covers a volume or mute change made by anything else; a
    // server event covers the default sink itself moving. Both mean re-reading,
    // and updateSinkInfo only ever reads, so this cannot loop back on our own
    // writes — the value it reads matches what we just set and the guards in
    // sinkInfoCallback drop it.
    const unsigned facility = t & PA_SUBSCRIPTION_EVENT_FACILITY_MASK;
    if(facility == PA_SUBSCRIPTION_EVENT_SINK || facility == PA_SUBSCRIPTION_EVENT_SERVER)
        self->updateSinkInfo();
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