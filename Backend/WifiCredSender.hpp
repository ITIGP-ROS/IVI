#pragma once
#include <QObject>
#include <QProcess>
#include <QString>

/*
 * WifiCredSender — hands WiFi credentials to the vehicle host over CAN by running
 * the wifi_cred_send tool (SecOC-authenticated, ISO-TP segmented). See
 * Jetson/wifi_cred_sender/README.md for the wire format and exit codes.
 *
 * Credentials go in on stdin, never in argv: anything in argv is readable by every
 * user on the box through `ps aux` and /proc/<pid>/cmdline.
 *
 * Asynchronous by design — the transfer waits on Flow Control from the host, and
 * blocking the GUI thread on that would freeze the head unit.
 *
 * NOTE: exit code 0 means *delivered*, not *accepted*. The host sends no verdict
 * back over CAN, so a MAC or freshness rejection is only visible in its log
 * (slog2info -b can_udp | grep -i wifi).
 */
class WifiCredSender : public QObject {
    Q_OBJECT

public:
    explicit WifiCredSender(QObject *parent = nullptr);

    void setProgram(const QString &p)   { m_program = p; }
    void setInterface(const QString &i) { m_iface   = i; }
    void setKeyPath(const QString &k)   { m_keyPath = k; }

    // Fire-and-forget; the outcome arrives on sent() or failed().
    void send(const QString &ssid, const QString &password);
    bool busy() const;

signals:
    void sent(const QString &ssid);
    void failed(const QString &reason);

private slots:
    void onFinished(int exitCode, QProcess::ExitStatus status);

private:
    static QString describe(int code);
    void report(bool ok, const QString &detail);

    QProcess *m_proc     = nullptr;
    bool      m_reported = true;   // guards against double-reporting one send
    QString   m_ssid;              // SSID of the in-flight send, for the result signal

    // The Yocto recipe (Jetson/yocto-recipe/recipes-apps/wifi-cred-sender) installs
    // to ${bindir} and ${sysconfdir}; a hand-built one usually lands in
    // /usr/local/bin. Resolved at construction — see the .cpp.
    QString m_program;
    QString m_iface   = "can0";
    QString m_keyPath = "/etc/wifi_secoc.key";
};
