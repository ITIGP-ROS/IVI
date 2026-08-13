#include "OtaManager.hpp"

#include <algorithm>

#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>

namespace {

constexpr int kTickMs = 1000;

QString defaultRoot()
{
    const QByteArray env = qgetenv("IVI_OTA_APPROVAL_DIR");
    if (!env.isEmpty())
        return QString::fromLocal8Bit(env);
    return QStringLiteral("/run/ota-approval");
}

// An offer id becomes a filename we create in verdicts/. It arrives as the stem
// of a file in a root-owned directory, so it is only semi-trusted — a stem
// cannot contain '/', but pinning the character set means a future producer
// cannot introduce a traversal by changing how it names things.
bool idIsSane(const QString &id)
{
    static const QRegularExpression re(QStringLiteral("^[A-Za-z0-9._-]{1,128}$"));
    return re.match(id).hasMatch() && !id.startsWith(QLatin1Char('.'));
}

} // namespace

OtaManager::OtaManager(QObject *parent)
    : QObject(parent), m_root(defaultRoot())
{
    // Overridable so a demo can require an explicit answer (0) or a test can
    // avoid waiting four real seconds per case.
    bool ok = false;
    const int envMs = qEnvironmentVariableIntValue("IVI_OTA_AUTOACCEPT_MS", &ok);
    if (ok && envMs >= 0)
        m_autoAcceptMs = envMs;

    qInfo().noquote() << "[ota] approval spool:" << m_root;
    qInfo().noquote() << "[ota] auto-accept:"
                      << (m_autoAcceptMs > 0
                              ? QStringLiteral("%1 ms").arg(m_autoAcceptMs)
                              : QStringLiteral("disabled — explicit answer required"));

    connect(&m_watcher, &QFileSystemWatcher::directoryChanged,
            this, &OtaManager::rescan);

    // One timer for everything periodic: the liveness touch, the expiry
    // countdown, re-establishing a lost watch, and the backstop rescan. All of
    // it is a handful of syscalls against tmpfs, so a shared 1 Hz tick costs
    // less than the bookkeeping of separate timers would.
    connect(&m_timer, &QTimer::timeout, this, &OtaManager::tick);
    m_timer.start(kTickMs);

    rescan();
}

QString OtaManager::targetLabel() const
{
    if (m_target == QLatin1String("ivi"))     return tr("Head Unit");
    if (m_target == QLatin1String("cluster")) return tr("Instrument Cluster");
    if (m_target == QLatin1String("esp32"))   return tr("Body Control ECU");
    if (m_target == QLatin1String("stm32"))   return tr("Powertrain ECU");
    // Unknown target: show the raw token rather than inventing a friendly name.
    // A prompt that cannot say what it is updating is one the user should
    // treat with suspicion, and hiding that behind "Vehicle Module" would not
    // help them.
    return m_target.isEmpty() ? tr("Unknown module") : m_target;
}

// The offer may only shorten the window, never lengthen it and never re-enable
// one we have switched off. A producer is trusted to know its own deadline; it
// is not trusted to decide how long a human on this screen gets.
int OtaManager::autoAcceptMs() const
{
    if (m_autoAcceptMs <= 0 || m_offerAutoAcceptMs <= 0)
        return m_autoAcceptMs;
    return qMin(m_autoAcceptMs, m_offerAutoAcceptMs);
}

QString OtaManager::sizeText() const
{
    if (m_sizeBytes <= 0)
        return QString();
    const double mib = double(m_sizeBytes) / (1024.0 * 1024.0);
    return mib < 1.0 ? tr("%1 KB").arg(m_sizeBytes / 1024)
                     : tr("%1 MB").arg(mib, 0, 'f', 1);
}

void OtaManager::tick()
{
    // --- liveness ---------------------------------------------------------
    // Producers stat this file's mtime. Rewriting one byte is what actually
    // moves mtime on every filesystem we care about; QFile::setFileTime would
    // be tidier but is not implemented on all Qt platform backends.
    QFile alive(alivePath());
    if (alive.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        alive.write("1");
        alive.close();
    } else if (!m_warnedMissing) {
        m_warnedMissing = true;
        qWarning().noquote()
            << "[ota] cannot touch" << alivePath()
            << "— producers will treat this head unit as down and auto-approve."
            << "Is the spool provisioned?";
    }

    // --- expiry -----------------------------------------------------------
    if (!m_id.isEmpty() && m_expiresAt > 0) {
        const qint64 now = QDateTime::currentSecsSinceEpoch();
        const int left = int(m_expiresAt - now);
        if (left != m_secondsRemaining) {
            m_secondsRemaining = qMax(0, left);
            emit secondsRemainingChanged();
        }
    }

    // The producer withdraws its own offer when it gives up waiting, which the
    // rescan below notices. We do not answer on the user's behalf when the
    // clock runs out — an unanswered prompt is not a denial, and pretending
    // otherwise would put a verdict on the bus that nobody chose.
    rescan();
}

void OtaManager::rescan()
{
    QDir dir(offersDir());

    // (Re)establish the watch. addPath on an already-watched path is a no-op,
    // and directories() is cheap, so this is safe to run every tick.
    if (dir.exists() && !m_watcher.directories().contains(offersDir()))
        m_watcher.addPath(offersDir());

    if (!dir.exists()) {
        if (!m_id.isEmpty())
            clearCurrent();
        return;
    }

    const QFileInfoList entries =
        dir.entryInfoList({QStringLiteral("*.json")}, QDir::Files, QDir::Name);

    // Oldest first, so a queue is answered in the order it arrived. requested_at
    // rather than file mtime: the producer knows when it asked, and mtime moves
    // if an offer is ever rewritten in place.
    struct Offer {
        QString id, target, version, slot;
        qint64  sizeBytes = 0, requestedAt = 0, expiresAt = 0;
        int     autoAcceptMs = 0;
        bool    stopsVehicle = false;
    };
    QList<Offer> offers;

    for (const QFileInfo &fi : entries) {
        const QString id = fi.completeBaseName();
        if (!idIsSane(id) || m_answered.contains(id))
            continue;

        QFile f(fi.absoluteFilePath());
        if (!f.open(QIODevice::ReadOnly))
            continue;

        QJsonParseError err{};
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
        f.close();
        if (err.error != QJsonParseError::NoError || !doc.isObject()) {
            // A producer that writes with `cat > offers/x.json` instead of
            // renaming into place leaves the file readable while it is still
            // half written, and inotify fires on the first byte. That parse
            // failure is transient and resolves on the next tick, so only
            // complain once the file has stopped changing — otherwise the log
            // fills with warnings about offers that are perfectly fine.
            const qint64 ageMs = fi.lastModified().msecsTo(QDateTime::currentDateTime());
            if (ageMs > 2000) {
                qWarning().noquote() << "[ota] ignoring malformed offer"
                                     << fi.fileName() << ":" << err.errorString();
            }
            continue;
        }

        const QJsonObject o = doc.object();

        // The id inside must agree with the filename. They are two independent
        // statements of the same thing, and the verdict is keyed on the
        // filename — if they disagree we would answer a question nobody asked.
        const QString innerId = o.value(QStringLiteral("id")).toString();
        if (!innerId.isEmpty() && innerId != id) {
            qWarning().noquote() << "[ota] offer" << fi.fileName()
                                 << "declares id" << innerId << "— ignoring";
            continue;
        }

        Offer offer;
        offer.id           = id;
        offer.target       = o.value(QStringLiteral("target")).toString();
        offer.version      = o.value(QStringLiteral("version")).toString();
        offer.slot         = o.value(QStringLiteral("slot")).toString();
        offer.sizeBytes    = qint64(o.value(QStringLiteral("size_bytes")).toDouble());
        offer.requestedAt  = qint64(o.value(QStringLiteral("requested_at")).toDouble());
        offer.expiresAt    = qint64(o.value(QStringLiteral("expires_at")).toDouble());
        offer.autoAcceptMs = o.value(QStringLiteral("auto_accept_ms")).toInt();
        offer.stopsVehicle = o.value(QStringLiteral("stops_vehicle")).toBool();
        offers.append(offer);
    }

    std::sort(offers.begin(), offers.end(), [](const Offer &a, const Offer &b) {
        if (a.requestedAt != b.requestedAt)
            return a.requestedAt < b.requestedAt;
        return a.id < b.id;   // stable tiebreak for same-second offers
    });

    // Forget answered ids once their offer file is gone, so the set cannot grow
    // without bound across a long run.
    if (m_answered.size() > 0) {
        QSet<QString> present;
        for (const QFileInfo &fi : entries)
            present.insert(fi.completeBaseName());
        m_answered.intersect(present);
    }

    const int queued = qMax(0, int(offers.size()) - 1);

    if (offers.isEmpty()) {
        if (!m_id.isEmpty()) {
            // Withdrawn by the producer — it gave up, or answered elsewhere.
            qInfo().noquote() << "[ota] offer" << m_id << "withdrawn";
            clearCurrent();
        }
        return;
    }

    const Offer &head = offers.first();

    // Same offer still on screen: only the queue depth can have moved.
    if (head.id == m_id) {
        if (queued != m_queued) {
            m_queued = queued;
            emit offerChanged();
        }
        return;
    }

    m_id           = head.id;
    m_target       = head.target;
    m_version      = head.version;
    m_slot         = head.slot;
    m_sizeBytes    = head.sizeBytes;
    m_stopsVehicle = head.stopsVehicle;
    m_expiresAt    = head.expiresAt;
    m_offerAutoAcceptMs = head.autoAcceptMs;
    m_queued       = queued;
    m_secondsRemaining = m_expiresAt > 0
        ? qMax(0, int(m_expiresAt - QDateTime::currentSecsSinceEpoch()))
        : -1;

    qInfo().noquote() << "[ota] offer" << m_id << "target" << m_target
                      << "version" << (m_version.isEmpty() ? QStringLiteral("?") : m_version)
                      << "auto-accept" << autoAcceptMs() << "ms"
                      << (m_stopsVehicle ? "(stops the vehicle)" : "");

    emit secondsRemainingChanged();

    // offerChanged before newOffer, and the order matters. autoAcceptMs is now
    // per-offer, so the QML countdown must have rebound to THIS offer's window
    // before newOffer() tells it to restart — otherwise a 2.5 s ESP32 prompt
    // starts one full 4 s cycle on the previous offer's interval and overruns
    // the very deadline the field exists to respect.
    emit offerChanged();
    emit newOffer();
}

void OtaManager::approve() { answer(true); }
void OtaManager::deny()    { answer(false); }

void OtaManager::answer(bool approved)
{
    if (m_id.isEmpty())
        return;

    const QString id     = m_id;
    const QString target = m_target;

    QString error;
    if (!writeVerdict(id, approved, &error)) {
        qWarning().noquote() << "[ota] could not answer" << id << ":" << error;
        // Deliberately leave the offer on screen. The tap did nothing, and
        // dismissing the prompt would tell the user the opposite.
        emit verdictFailed(error);
        return;
    }

    qInfo().noquote() << "[ota]" << (approved ? "APPROVED" : "DENIED")
                      << id << "(" << target << ")";

    // Remember it so the offer file, which the producer has not deleted yet,
    // does not re-open the prompt on the next rescan.
    m_answered.insert(id);

    clearCurrent();
    emit verdictSent(target, approved);

    // Surface the next queued offer immediately rather than up to a tick later.
    rescan();
}

bool OtaManager::writeVerdict(const QString &id, bool approved, QString *error) const
{
    if (!idIsSane(id)) {
        *error = tr("Malformed request id");
        return false;
    }

    const QString finalPath = verdictsDir() + QLatin1Char('/') + id;

    // QSaveFile writes to a temporary and renames on commit, so a producer
    // polling for this path either does not see it or sees it complete. It
    // never reads a zero-length file and concludes the answer was empty.
    //
    // Note this works even though verdicts/ is mode 0730 and we cannot list it:
    // creating and renaming need write+execute on the directory, not read.
    QSaveFile f(finalPath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        *error = tr("Cannot write to %1 (%2)").arg(verdictsDir(), f.errorString());
        return false;
    }
    f.write(approved ? "approve\n" : "deny\n");
    if (!f.commit()) {
        *error = tr("Could not save the verdict (%1)").arg(f.errorString());
        return false;
    }
    return true;
}

void OtaManager::clearCurrent()
{
    m_id.clear();
    m_target.clear();
    m_version.clear();
    m_slot.clear();
    m_sizeBytes    = 0;
    m_stopsVehicle = false;
    m_expiresAt    = 0;
    m_offerAutoAcceptMs = 0;
    m_queued       = 0;

    if (m_secondsRemaining != -1) {
        m_secondsRemaining = -1;
        emit secondsRemainingChanged();
    }
    emit offerChanged();
}
