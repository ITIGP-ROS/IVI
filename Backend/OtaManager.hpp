#pragma once

#include <QObject>
#include <QSet>
#include <QString>
#include <QTimer>
#include <QFileSystemWatcher>

/*
 * OtaManager — the head unit's half of the OTA approval handshake.
 *
 * Something on this vehicle wants to install firmware. Before it does, a human
 * has to say yes on this screen. This class watches for those requests and
 * writes back the answer.
 *
 * ---------------------------------------------------------------------------
 * THE SPOOL CONTRACT
 *
 * Deliberately files rather than D-Bus, a socket, or ROS. The producers are a
 * POSIX shell script (ivi_ota_agent.sh) and a Python ROS node running as root;
 * this app runs as the unprivileged `weston` user. Files are the only transport
 * all three can speak without new runtime dependencies, and directory ownership
 * becomes the permission model for free.
 *
 *   /run/ota-approval/
 *     offers/<id>.json   0755 root:root    producers write, we read
 *     verdicts/<id>      0730 root:weston  we write, we cannot even list it
 *     notices/<id>.json  0755 root:root    producers write, we read
 *     ui-alive           0664 weston       we touch it, producers stat it
 *
 * `verdicts/` at 0730 is the point of the whole layout: this process can create
 * a file in it but cannot read the directory back. It can answer a question. It
 * cannot ask one, and it cannot see anyone else's answer.
 *
 * An offer is one JSON object:
 *
 *   {
 *     "id":            "esp32-1754994000",   // must match the filename stem
 *     "target":        "esp32",              // ivi | cluster | esp32 | stm32
 *     "version":       "1.4.2",              // optional, "" if unknown
 *     "slot":          "B",                  // optional
 *     "size_bytes":    55574528,             // optional, 0 if unknown
 *     "requested_at":  1754994000,           // unix seconds
 *     "expires_at":    1754994060,           // unix seconds; 0 = never
 *     "auto_accept_ms": 2500,                // optional; see AUTO-ACCEPT below
 *     "stops_vehicle": true                  // approving triggers e-stop
 *   }
 *
 * The verdict file holds exactly one word, "approve" or "deny", written to a
 * temporary name and renamed into place so a producer polling for it can never
 * read a half-written file.
 *
 * PRODUCERS MUST WRITE OFFERS THE SAME WAY — to `<id>.json.tmp` in the same
 * directory, then rename(2) onto `<id>.json`. A plain `cat > offers/x.json`
 * from a shell script is not atomic: inotify fires on the first write and this
 * side reads a truncated file. It recovers on the next poll, so the failure is
 * cosmetic rather than dangerous, which is precisely why it will otherwise go
 * unnoticed until someone is debugging something else at 2am.
 *
 * An offer is withdrawn by unlinking its file. Doing that is how a producer
 * takes the prompt back down when it stops waiting.
 *
 * ---------------------------------------------------------------------------
 * AUTO-ACCEPT
 *
 * The prompt approves itself if nobody touches it for `autoAcceptMs` (9 s).
 * Deny is the deliberate act; letting it ride is consent.
 *
 * 9 s is deliberately the SAME for every target. The prompt a driver sees must
 * not silently change length depending on which ECU is asking — a window you
 * cannot predict is one you cannot learn to react to.
 *
 * That is a real policy choice and worth naming: even at nine seconds this
 * prompt is closer to a notification with a veto than to a gate. A driver who
 * is not already looking at the screen will not stop it. It matches the
 * fail-open stance elsewhere in this handshake — a stale `ui-alive` also means
 * approve — so the vehicle's answer to "nobody is paying attention" is
 * consistently "go ahead" rather than "block forever".
 *
 * Every target honours the full 9 s. The cluster waits 60 s against a 30 s
 * coordinator deadline; the ESP32 waits 10 s against a 9500 ms one. Both
 * give-up points sit after this countdown, so the driver's window is what
 * decides everywhere — see the ESP32 note below for how narrow that second
 * corridor is.
 *
 * Set IVI_OTA_AUTOACCEPT_MS=0 to require an explicit answer instead.
 *
 * An offer may carry `auto_accept_ms` to ask for a SHORTER window. It can never
 * ask for a longer one, and it cannot re-enable auto-accept that this side has
 * turned off — the effective window is min(offer, ours), and zero stays zero.
 * That asymmetry is the whole point: the field exists because the requester
 * knows a deadline we do not. No producer currently uses it to go shorter, since
 * every target is held to the same 9 s; it stays because the next ECU may be
 * tighter still.
 *
 * IT ALSO MEANS RAISING THE NUMBER BELOW IS ONLY HALF THE CHANGE. The clamp is
 * min(), so an offer that asks for 5000 ms still gets 5000 ms no matter how
 * high this ceiling goes. update_coordinator writes `auto_accept_ms` from its
 * own BUDGETS table (update_coordinator/node.py), so the cluster and ESP32
 * paths only see a longer prompt once that table is raised to match.
 *
 * The ESP32 is the tight one. Its firmware blocks for 10000 ms waiting for a
 * verdict on 0x311, asks once, and then abandons the update
 * (ECU/ESP32/src/logs/can.c). The window is not the only cost in that budget —
 * the offer has to be noticed, the card has to drop in, the coordinator polls
 * for the verdict, and the SecOC frame has to be built and sent. A 9 s prompt
 * leaves ~1 s for all of it, which is why the coordinator's deadline sits at
 * 9500 ms: above this countdown, and far enough below the wall to get a frame
 * out. That wall was 5000 ms until recently, and at 5000 ms a 9 s prompt does
 * not fit at all — a board still running that build gives up mid-countdown.
 *
 * ---------------------------------------------------------------------------
 * COMPLETION NOTICES
 *
 * The other direction of the same idea. When an update has actually landed, the
 * producer drops a file in `notices/` and this side shows a 5 s banner saying so
 * — and nothing else. There is no verdict to write and nothing for the driver to
 * answer, so it is a toast, not a prompt: it does not take the screen, it does
 * not dim it, and it does not swallow taps.
 *
 *   {
 *     "id":     "esp32-1754994000",   // must match the filename stem
 *     "target": "esp32",              // REQUIRED: esp32 | stm32 | cluster
 *     "at":     1754994120            // optional, unix seconds
 *   }
 *
 * Write it to `<id>.json.tmp` and rename(2) it into place, exactly as with an
 * offer and for exactly the same reason.
 *
 * EVERY ECU IS ANNOUNCED — `esp32`, `stm32`, `cluster` — BUT NOT `ivi`, which
 * is logged and dropped along with anything unrecognised. The head unit does
 * not announce its own update because that one ends in a reboot: the screen
 * going dark and coming back IS the announcement, and a banner afterwards would
 * only report something the driver just watched happen. It also could not work
 * — /run is a tmpfs, so a notice written before the reboot is not there
 * afterwards.
 *
 * WE CANNOT DELETE THE NOTICE — notices/ is root-owned, like offers/. The
 * producer unlinks it once it has written it; this side only remembers the ids
 * it has already shown, so a file left lying there does not re-toast on every
 * one-second tick. That memory is per-process, which is why a notice is ALSO
 * ignored when it is already older than kNoticeMaxAgeS the first time we see
 * it: without the age check, an uncollected notice would pop up again on the
 * next app restart, announcing an update that finished an hour ago.
 *
 * ---------------------------------------------------------------------------
 * LIVENESS, AND WHY IT MATTERS
 *
 * We touch `ui-alive` once a second. A producer that finds it stale concludes
 * nobody can answer and falls back to its old automatic behaviour rather than
 * blocking updates forever on a head unit that has crashed.
 *
 * The consequence is worth stating plainly: human approval here is ADVISORY,
 * not enforceable. Anyone who can stop this app gets auto-approve back. That is
 * a deliberate availability-over-strictness trade for this vehicle — the
 * producer side has a config knob to invert it.
 *
 * ---------------------------------------------------------------------------
 * The offer directory is polled once a second as well as watched. inotify on
 * tmpfs is reliable, but a watch is silently lost if the directory is replaced
 * rather than modified — which is exactly what happens when the tmpfiles.d
 * fragment recreates /run/ota-approval on a service restart. The poll is the
 * backstop that makes that recoverable instead of fatal.
 */
class OtaManager : public QObject
{
    Q_OBJECT

    // True whenever there is something on screen to answer.
    Q_PROPERTY(bool requestPending READ requestPending NOTIFY offerChanged)

    Q_PROPERTY(QString target       READ target       NOTIFY offerChanged)
    Q_PROPERTY(QString targetLabel  READ targetLabel  NOTIFY offerChanged)
    Q_PROPERTY(QString version      READ version      NOTIFY offerChanged)
    Q_PROPERTY(QString slot         READ slot         NOTIFY offerChanged)
    Q_PROPERTY(QString sizeText     READ sizeText     NOTIFY offerChanged)
    Q_PROPERTY(bool    stopsVehicle READ stopsVehicle NOTIFY offerChanged)

    // Offers behind the one being shown. Lets the popup say "1 more waiting"
    // instead of silently reappearing after an answer.
    Q_PROPERTY(int queuedCount READ queuedCount NOTIFY offerChanged)

    // Seconds until the current offer expires, or -1 when it never does.
    // Counts down at 1 Hz; the producer withdraws the offer on its own clock,
    // so this is a display of their deadline, not ours.
    Q_PROPERTY(int secondsRemaining READ secondsRemaining NOTIFY secondsRemainingChanged)

    // How long the prompt waits before approving itself, in milliseconds.
    // 0 disables auto-accept entirely. The countdown is owned by the QML side
    // so that it only runs while the prompt is genuinely on screen — an offer
    // arriving behind the splash must not be approved before it is visible.
    //
    // Per-offer, not constant: a requester with a short deadline can shorten it
    // (see AUTO-ACCEPT above). QML must rebind on offerChanged, which it gets
    // for free through the Timer's interval binding.
    Q_PROPERTY(int autoAcceptMs READ autoAcceptMs NOTIFY offerChanged)

public:
    explicit OtaManager(QObject *parent = nullptr);

    bool    requestPending()   const { return !m_id.isEmpty(); }
    QString target()           const { return m_target; }
    QString targetLabel()      const;
    QString version()          const { return m_version; }
    QString slot()             const { return m_slot; }
    QString sizeText()         const;
    bool    stopsVehicle()     const { return m_stopsVehicle; }
    int     queuedCount()      const { return m_queued; }
    int     secondsRemaining() const { return m_secondsRemaining; }
    int     autoAcceptMs()     const;

    // Answer the offer currently on screen. Both consume it and move on to the
    // next queued one, if any.
    Q_INVOKABLE void approve();
    Q_INVOKABLE void deny();

signals:
    void offerChanged();
    void secondsRemainingChanged();

    // A different offer is now on screen. Distinct from offerChanged(), which
    // also fires when only the queue depth moves — the auto-accept countdown
    // restarts on this and must not be nudged by a second offer arriving
    // behind the one being decided.
    void newOffer();

    // Emitted after a verdict is successfully written, so the UI can confirm
    // before dismissing. `approved` is what was sent.
    void verdictSent(const QString &target, bool approved);

    // The verdict could not be written — almost always the spool directory not
    // existing or not being writable. The producer will time out and fall back
    // to its own default, so the user must be told their tap did nothing.
    void verdictFailed(const QString &reason);

    // An update has finished. Purely informational — there is nothing to answer
    // and nothing to write back, so this drives a toast rather than the prompt.
    //
    // Carries nothing: the banner says only that an update is done. The target
    // is logged, not shown, so there is no argument here to go stale.
    void updateCompleted();

private slots:
    void rescan();
    void scanNotices();
    void tick();

private:
    void answer(bool approved);
    void clearCurrent();
    bool writeVerdict(const QString &id, bool approved, QString *error) const;

    // Friendly name for a target token, or an empty string for one we have no
    // name for. targetLabel() is this plus a placeholder for the prompt, which
    // must always say something; the toast prefers to say nothing.
    QString labelFor(const QString &target) const;

    QString offersDir()   const { return m_root + QStringLiteral("/offers"); }
    QString verdictsDir() const { return m_root + QStringLiteral("/verdicts"); }
    QString noticesDir()  const { return m_root + QStringLiteral("/notices"); }
    QString alivePath()   const { return m_root + QStringLiteral("/ui-alive"); }

    // Overridable so the whole handshake can be exercised on a laptop with no
    // root and no /run entry, which is how the UI gets developed:
    //   IVI_OTA_APPROVAL_DIR=/tmp/ota-approval ./appIVI
    QString m_root;
    int     m_autoAcceptMs = 9000;   // our ceiling; an offer may only lower it

    // The offer on screen. Empty id means nothing is pending.
    QString m_id;
    QString m_target;
    QString m_version;
    QString m_slot;
    qint64  m_sizeBytes     = 0;
    bool    m_stopsVehicle  = false;
    qint64  m_expiresAt     = 0;    // unix seconds; 0 = never
    int     m_secondsRemaining = -1;
    int     m_queued        = 0;
    int     m_offerAutoAcceptMs = 0;   // 0 = the offer did not ask for anything

    // Answered ids, so a verdict file that a producer has not collected yet
    // cannot make its offer pop up again on the next rescan.
    QSet<QString> m_answered;

    // Notice ids already toasted. Same job as m_answered, for the same reason:
    // we cannot unlink the file that caused it.
    QSet<QString> m_notified;

    QFileSystemWatcher m_watcher;
    QTimer m_timer;
    bool   m_warnedMissing = false;   // one log line, not one per second
};
