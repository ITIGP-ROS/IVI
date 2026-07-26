#pragma once

#include <QObject>
#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QStringList>
#include <QTimer>
#include <QFutureWatcher>

class UsbManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(QString mountPath READ mountPath NOTIFY mountPathChanged)
    Q_PROPERTY(QString  driveName READ driveName NOTIFY driveNameChanged)
    Q_PROPERTY(QStringList audioFiles READ audioFiles NOTIFY filesChanged)
    Q_PROPERTY(QStringList videoFiles READ videoFiles NOTIFY filesChanged)

public:
    explicit UsbManager(QObject* parent = nullptr);

    bool connected() const { return m_connected; }
    bool scanning() const { return m_scanning; }
    QString mountPath() const { return m_mountPath; }
    QString driveName() const { return m_driveName; }
    QStringList audioFiles() const { return m_audioFiles; }
    QStringList videoFiles() const { return m_videoFiles; }

    Q_INVOKABLE QString fileName(const QString& path) const;

public slots:
    void disconnectDevice();

signals:
    void connectedChanged();
    void scanningChanged();
    void mountPathChanged();
    void driveNameChanged();
    void filesChanged();
    void errorOccurred(const QString& message);

private slots:
    void onInterfacesAdded(const QDBusObjectPath& path, const QMap<QString, QVariantMap>& interfaces);
    void onInterfacesRemoved(const QDBusObjectPath& path, const QStringList& interfaces);
    void onScanCompleted(const QStringList& audioFiles, const QStringList& videoFiles);

private:
    void init();

    // udisks2 (USB flash drives)
    void scanExistingDrives();
    void mountDrive(const QString& objectPath);
    QVariantMap getProperties(const QString& path, const QString& iface);
    QMap<QString, QStringList> getManagedObjects();
    QStringList extractMountPoints(const QVariant& mountPointsVar);

    // gvfs MTP (phones via USB)
    void scanGvfsMtp();

    // File scanning (shared)
    void scanFiles();
    static void scanDirectory(const QString& dirPath, QStringList& audioOut, QStringList& videoOut);
    void scanDirectoryWithProgress(const QString& dirPath, QStringList& audioOut, QStringList& videoOut);

    bool m_connected = false;
    bool m_scanning = false;
    QString m_mountPath;
    QString m_driveName;
    QString m_objectPath;
    QStringList m_audioFiles;
    QStringList m_videoFiles;

    QDBusConnection m_bus;
    QFutureWatcher<void>* m_scanWatcher = nullptr;

    static const QStringList AUDIO_EXTENSIONS;
    static const QStringList VIDEO_EXTENSIONS;
};