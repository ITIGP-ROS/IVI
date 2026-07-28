#include "WifiCredSender.hpp"
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <QFileInfo>
#include <QDebug>

// ISO-TP plus Flow Control is sub-second; anything near this means the bridge is gone.
static constexpr int kSendTimeoutMs = 10000;

WifiCredSender::WifiCredSender(QObject *parent) : QObject(parent)
{
    // The recipe installs into ${bindir}; a hand-built binary usually sits in
    // /usr/local/bin. Prefer whichever actually exists so a path mismatch does
    // not surface as a bare "Cannot start" at connect time.
    const QStringList candidates {
        "/usr/bin/wifi_cred_send",
        "/usr/local/bin/wifi_cred_send"
    };
    m_program = candidates.first();
    bool found = false;
    for (const QString &c : candidates) {
        if (QFileInfo(c).isExecutable()) { m_program = c; found = true; break; }
    }

    if (found)
        qInfo().noquote() << "[wifi-cred] sender:" << m_program;
    else
        qWarning().noquote() << "[wifi-cred] sender NOT FOUND in"
                             << candidates.join(", ")
                             << "— sends will fail until it is installed";
}

bool WifiCredSender::busy() const
{
    return m_proc && m_proc->state() != QProcess::NotRunning;
}

void WifiCredSender::send(const QString &ssid, const QString &password)
{
    if (ssid.isEmpty() || password.isEmpty()) {
        emit failed(tr("No credentials to send"));
        return;
    }

    // The receiver splits the payload on the first ';', so an SSID containing one
    // would be silently mangled on the host side.
    if (ssid.contains(';')) {
        emit failed(tr("SSID must not contain ';'"));
        return;
    }

    if (busy()) {
        emit failed(tr("A credential transfer is already in progress"));
        return;
    }

    delete m_proc;                 // reap the previous, already-finished process
    m_proc     = new QProcess(this);
    m_ssid     = ssid;
    m_reported = false;

    connect(m_proc, &QProcess::finished, this, &WifiCredSender::onFinished);
    connect(m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart)
            report(false, tr("Cannot start %1").arg(m_program));
    });

    // Argument-vector form goes straight to execve() with no shell, so an SSID
    // containing spaces, quotes, $ or ; cannot become injection.
    const QStringList args {"--stdin", "--json", "-i", m_iface, "-k", m_keyPath};

    qInfo().noquote() << "[wifi-cred] sending credentials for SSID:" << ssid;
    qInfo().noquote() << "[wifi-cred] exec:" << m_program << args.join(' ')
                      << "(credentials on stdin)";
    if (!QFileInfo(m_keyPath).isReadable())
        qWarning().noquote() << "[wifi-cred] key not readable:" << m_keyPath;

    m_proc->start(m_program, args);

    // Don't leave a stuck child holding the CAN socket forever.
    QTimer::singleShot(kSendTimeoutMs, m_proc, [this]() {
        if (busy()) {
            m_proc->kill();
            report(false, tr("Timed out talking to the CAN bus"));
        }
    });

    // SSID on line 1, password on line 2 — nothing lands in argv.
    m_proc->write(ssid.toUtf8() + '\n' + password.toUtf8() + '\n');
    m_proc->closeWriteChannel();
}

void WifiCredSender::onFinished(int exitCode, QProcess::ExitStatus status)
{
    if (status == QProcess::CrashExit) {
        report(false, tr("Credential sender crashed"));
        return;
    }

    // --json prints exactly one line; the password is never included in it.
    QString detail;
    const QJsonDocument doc =
        QJsonDocument::fromJson(m_proc->readAllStandardOutput().trimmed());
    if (doc.isObject())
        detail = doc.object().value("message").toString();
    if (detail.isEmpty())
        detail = QString::fromUtf8(m_proc->readAllStandardError()).trimmed();
    if (detail.isEmpty())
        detail = describe(exitCode);

    qInfo().noquote() << "[wifi-cred] sender exited with code" << exitCode;
    report(exitCode == 0, detail);
}

void WifiCredSender::report(bool ok, const QString &detail)
{
    if (m_reported) return;        // a timeout kill also fires finished()
    m_reported = true;

    if (ok) {
        qInfo().noquote() << "[wifi-cred] OK — delivered to host:" << detail;
        emit sent(m_ssid);
    } else {
        qWarning().noquote() << "[wifi-cred] FAILED:" << detail;
        emit failed(detail);
    }
}

// Exit codes per Jetson/wifi_cred_sender/README.md
QString WifiCredSender::describe(int code)
{
    switch (code) {
        case 0:  return tr("Delivered to the vehicle host");
        case 2:  return tr("Invalid SSID or password");
        case 3:  return tr("SecOC key missing or malformed");
        case 4:  return tr("CAN interface unavailable");
        case 5:  return tr("No response from the host (is the CAN bridge running?)");
        case 6:  return tr("Credentials too long");
        default: return tr("Unknown error (%1)").arg(code);
    }
}
