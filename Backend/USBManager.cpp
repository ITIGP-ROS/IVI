#include "USBManager.hpp"

#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusArgument>
#include <QDBusVariant>
#include <QDBusMetaType>
#include <QDir>
#include <QFileInfo>
#include <QDirIterator>
#include <QTimer>
#include <QDebug>
#include <unistd.h>
#include <QtConcurrentRun>
#include <QThread>
#include <QMetaObject>
#include <functional>

// udisks2 D-Bus constants
static const QString UDISKS2_SERVICE     = "org.freedesktop.UDisks2";
static const QString UDISKS2_ROOT        = "/org/freedesktop/UDisks2";
static const QString UDISKS2_BLOCK_IFACE = "org.freedesktop.UDisks2.Block";
static const QString UDISKS2_FS_IFACE    = "org.freedesktop.UDisks2.Filesystem";
static const QString DBUS_OBJMGR_IFACE   = "org.freedesktop.DBus.ObjectManager";
static const QString DBUS_PROPS_IFACE    = "org.freedesktop.DBus.Properties";

// Supported extensions
const QStringList UsbManager::AUDIO_EXTENSIONS = {
    "mp3", "wav", "aac", "flac", "ogg", "m4a", "wma", "opus", "aiff"
};
const QStringList UsbManager::VIDEO_EXTENSIONS = {
    "mp4", "mkv", "avi", "mov", "wmv", "webm", "flv", "m4v", "ts"
};

UsbManager::UsbManager(QObject* parent) : QObject(parent) , m_bus(QDBusConnection::systemBus()){
    init();
}

void UsbManager::init(){
    if(!m_bus.isConnected())
        qDebug() << "USB: Cannot connect to system D-Bus — flash drives won't be detected";

    qDBusRegisterMetaType<QMap<QString, QVariantMap>>();

    // Watch udisks2 for flash drives
    m_bus.connect(UDISKS2_SERVICE, UDISKS2_ROOT, DBUS_OBJMGR_IFACE,
        "InterfacesAdded", this,
        SLOT(onInterfacesAdded(QDBusObjectPath, QMap<QString,QVariantMap>)));
    m_bus.connect(UDISKS2_SERVICE, UDISKS2_ROOT, DBUS_OBJMGR_IFACE,
        "InterfacesRemoved", this,
        SLOT(onInterfacesRemoved(QDBusObjectPath, QStringList)));

    // Scan for already-connected devices at startup
    scanExistingDrives();

    if(!m_connected)
        scanGvfsMtp();

    // Poll every 3s
    // Handles: MTP connect/disconnect, delayed mounts
    QTimer* pollTimer = new QTimer(this);
    pollTimer->setInterval(3000);
    connect(pollTimer, &QTimer::timeout, this, [this]() {
        if(!m_connected) {
            scanExistingDrives();
            if(!m_connected) scanGvfsMtp();
        } 
        else {
            // Check if still accessible
            if(!QDir(m_mountPath).exists()) {
                qDebug() << "USB/MTP device removed:" << m_mountPath;
                m_connected  = false;
                m_mountPath  = "";
                m_driveName  = "";
                m_objectPath = "";
                m_audioFiles.clear();
                m_videoFiles.clear();
                emit connectedChanged();
                emit mountPathChanged();
                emit driveNameChanged();
                emit filesChanged();
            }
        }
    });
    pollTimer->start();
}

//  scanGvfsMtp — detects phones connected via USB(MTP protocol)
//  Path: /run/user/<uid>/gvfs/mtp:host=DEVICE_NAME/Internal storage
void UsbManager::scanGvfsMtp(){
    QString gvfsBase = QString("/run/user/%1/gvfs").arg(getuid());
    QDir gvfsDir(gvfsBase);

    if(!gvfsDir.exists()) return;

    QStringList entries = gvfsDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    qDebug() << "USB gvfs entries:" << entries;

    for(const QString& entry : entries) {
        if(!entry.startsWith("mtp:") && !entry.startsWith("gphoto2:")) continue;

        QString mtpBase = gvfsBase + "/" + entry;

        QDir mtpDir(mtpBase);
        if(!mtpDir.exists()) continue;

        QStringList storages = mtpDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        qDebug() << "USB MTP storages:" << storages;

        if(storages.isEmpty()) continue;

        // Prefer "Internal storage" if present, otherwise use first
        QString preferred = "Internal storage";
        QString storage   = storages.contains(preferred)
                            ? preferred
                            : storages.first();

        QString storagePath = mtpBase + "/" + storage;

        // Extract device name from entry e.g. "mtp:host=SAMSUNG_SAMSUNG_Android_XYZ"
        QString deviceName = entry;
        int eq = deviceName.indexOf('=');
        if(eq >= 0) deviceName = deviceName.mid(eq + 1);
        deviceName.replace('_', ' ').replace("%20", " ");

        qDebug() << "USB MTP connected:" << storagePath << "Device:" << deviceName;

        m_mountPath  = storagePath;
        m_driveName  = deviceName;
        m_connected  = true;
        m_objectPath = entry;

        emit connectedChanged();
        emit mountPathChanged();
        emit driveNameChanged();

        scanFiles();
        return;
    }
}

//  getManagedObjects
QMap<QString, QStringList> UsbManager::getManagedObjects(){
    QMap<QString, QStringList> result;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        UDISKS2_SERVICE, UDISKS2_ROOT, DBUS_OBJMGR_IFACE, "GetManagedObjects"
    );
    QDBusMessage reply = m_bus.call(msg);
    if(reply.type() == QDBusMessage::ErrorMessage) return result;
    if(reply.arguments().isEmpty()) return result;

    const QDBusArgument rootArg = reply.arguments().at(0).value<QDBusArgument>();

    rootArg.beginMap();
    while(!rootArg.atEnd()) {
        rootArg.beginMapEntry();
        QDBusObjectPath objPath;
        rootArg >> objPath;

        QStringList ifaces;
        rootArg.beginMap();
        while(!rootArg.atEnd()) {
            rootArg.beginMapEntry();
            QString ifaceName;
            rootArg >> ifaceName;
            ifaces << ifaceName;
            rootArg.beginMap();
            while(!rootArg.atEnd()) {
                rootArg.beginMapEntry();
                QString k; QDBusVariant v;
                rootArg >> k >> v;
                rootArg.endMapEntry();
            }
            rootArg.endMap();
            rootArg.endMapEntry();
        }
        rootArg.endMap();
        result[objPath.path()] = ifaces;
        rootArg.endMapEntry();
    }
    rootArg.endMap();
    return result;
}

//  getProperties
QVariantMap UsbManager::getProperties(const QString& path, const QString& iface){
    QVariantMap result;
    QDBusMessage msg = QDBusMessage::createMethodCall(
        UDISKS2_SERVICE, path, DBUS_PROPS_IFACE, "GetAll"
    );
    msg << iface;
    QDBusMessage reply = m_bus.call(msg);
    if(reply.type() == QDBusMessage::ErrorMessage) return result;
    if(reply.arguments().isEmpty()) return result;

    const QDBusArgument arg = reply.arguments().at(0).value<QDBusArgument>();
    arg.beginMap();
    while(!arg.atEnd()) {
        arg.beginMapEntry();
        QString key; QDBusVariant val;
        arg >> key >> val;
        result[key] = val.variant();
        arg.endMapEntry();
    }
    arg.endMap();
    return result;
}

//  extractMountPoints — parses the MountPoints a{ay} D-Bus type
QStringList UsbManager::extractMountPoints(const QVariant& mountPointsVar){
    QStringList result;
    if(!mountPointsVar.canConvert<QDBusArgument>()) return result;

    const QDBusArgument arg = mountPointsVar.value<QDBusArgument>();
    arg.beginArray();
    while(!arg.atEnd()) {
        QByteArray bytes;
        arg >> bytes;
        if(!bytes.isEmpty() && bytes.back() == '\0')
            bytes.chop(1);
        if(!bytes.isEmpty())
            result << QString::fromLocal8Bit(bytes);
    }
    arg.endArray();
    return result;
}

//  scanExistingDrives — udisks2 USB flash drives
void UsbManager::scanExistingDrives(){
    const auto objects = getManagedObjects();

    for(auto it = objects.begin(); it != objects.end(); ++it) {
        const QString& path       = it.key();
        const QStringList& ifaces = it.value();

        if(!ifaces.contains(UDISKS2_FS_IFACE)) continue;

        QVariantMap blockProps = getProperties(path, UDISKS2_BLOCK_IFACE);
        bool isSystem = blockProps.value("HintSystem", true).toBool();
        bool isIgnore = blockProps.value("HintIgnore", false).toBool();
        if(isSystem || isIgnore) continue;

        QVariantMap fsProps = getProperties(path, UDISKS2_FS_IFACE);
        QStringList mountPoints = extractMountPoints(fsProps.value("MountPoints"));

        if(mountPoints.isEmpty()) continue;

        QString mp = mountPoints.first();
        if(mp.startsWith("/boot") || mp == "/" || mp.startsWith("/snap")) continue;

        qDebug() << "USB flash drive found:" << mp;
        mountDrive(path);
        return;
    }
}

// mountDrive - called for already-mounted flash drives
void UsbManager::mountDrive(const QString& objectPath){
    QVariantMap fsProps    = getProperties(objectPath, UDISKS2_FS_IFACE);
    QVariantMap blockProps = getProperties(objectPath, UDISKS2_BLOCK_IFACE);

    QStringList mountPoints = extractMountPoints(fsProps.value("MountPoints"));
    if(mountPoints.isEmpty()) return;

    m_objectPath = objectPath;
    m_mountPath  = mountPoints.first();
    m_connected  = true;
    m_driveName  = blockProps.value("IdLabel").toString();
    if(m_driveName.isEmpty())
        m_driveName = QDir(m_mountPath).dirName();

    qDebug() << "USB flash mounted:" << m_mountPath;

    emit connectedChanged();
    emit mountPathChanged();
    emit driveNameChanged();
    scanFiles();
}

//  onInterfacesAdded — flash drive plugged in
void UsbManager::onInterfacesAdded(const QDBusObjectPath& path,
                                    const QMap<QString, QVariantMap>& interfaces)
{
    if(!interfaces.contains(UDISKS2_FS_IFACE)) return;
    const QString objPath = path.path();
    qDebug() << "USB udisks2 InterfacesAdded:" << objPath;

    // Wait 1.5s for mount to complete
    QTimer::singleShot(1500, this, [this, objPath]() {
        if(!m_connected) mountDrive(objPath);
    });
}

//  onInterfacesRemoved — flash drive removed
void UsbManager::onInterfacesRemoved(const QDBusObjectPath& path, const QStringList& interfaces){
    if(path.path() != m_objectPath) return;
    if(!interfaces.contains(UDISKS2_FS_IFACE)) return;

    qDebug() << "USB flash drive removed";
    m_connected = false; m_mountPath = ""; m_driveName = "";
    m_objectPath = ""; m_audioFiles.clear(); m_videoFiles.clear();
    emit connectedChanged(); emit mountPathChanged();
    emit driveNameChanged(); emit filesChanged();
}

//  scanFiles — recursively find audio and video files
void UsbManager::scanFiles(){
    if(m_mountPath.isEmpty()) return;
    if(m_scanning) return;
    
    m_scanning = true;
    emit scanningChanged();
    
    m_audioFiles.clear();
    m_videoFiles.clear();
    emit filesChanged();
    
    QString path = m_mountPath;
    
    // Use QtConcurrent with progress reporting
    QFuture<void> future = QtConcurrent::run([this, path](){
        QStringList audioOut;
        QStringList videoOut;
        
        // Modified scan that emits progress every 20 files
        scanDirectoryWithProgress(path, audioOut, videoOut);
        
        QMetaObject::invokeMethod(this, [this, audioOut, videoOut]() {
            onScanCompleted(audioOut, videoOut);
        }, Qt::QueuedConnection);
    });
    
    if(!m_scanWatcher) {
        m_scanWatcher = new QFutureWatcher<void>(this);
    }
    m_scanWatcher->setFuture(future);
}

void UsbManager::scanDirectoryWithProgress(const QString& dirPath, QStringList& audioOut, QStringList& videoOut){
    static const QStringList skipFolders = {"Android", ".thumbnails", ".cache", "com.", 
        ".trashed", ".stfolder", ".stversions", "node_modules", ".git", 
        "System Volume Information", "$RECYCLE.BIN", "Photos", "DCIM"};
    
    QDir dir(dirPath);
    if(!dir.exists()) return;
    
    dir.setFilter(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot);
    dir.setSorting(QDir::Name);
    
    QFileInfoList entries = dir.entryInfoList();
    int counter = 0;
    
    for(const QFileInfo& info : entries) {
        if(!m_scanning) return;  // Check for cancellation
        
        if(info.isDir()) {
            QString dirName = info.fileName();
            bool shouldSkip = false;
            for(const QString& skip : skipFolders) {
                if(dirName.startsWith(skip, Qt::CaseInsensitive)) {
                    shouldSkip = true;
                    break;
                }
            }
            if(!shouldSkip) {
                scanDirectoryWithProgress(info.filePath(), audioOut, videoOut);
            }
            // If shouldSkip, we don't recurse(directory is skipped)
        } 
        else if(info.isFile()) {
            QString ext = info.suffix().toLower();
            if(AUDIO_EXTENSIONS.contains(ext)) {
                audioOut << info.filePath();
            } 
            else if(VIDEO_EXTENSIONS.contains(ext)) {
                videoOut << info.filePath();
            }
            
            // Emit progress every 20 files
            if(++counter % 20 == 0) {
                QStringList tempAudio = audioOut;
                QStringList tempVideo = videoOut;
                QMetaObject::invokeMethod(this, [this, tempAudio, tempVideo]() {
                    if(m_scanning) {
                        m_audioFiles = tempAudio;
                        m_videoFiles = tempVideo;
                        emit filesChanged();
                    }
                }, Qt::QueuedConnection);
            }
        }
    }
}

void UsbManager::onScanCompleted(const QStringList& audioFiles, const QStringList& videoFiles){
    m_audioFiles = audioFiles;
    m_videoFiles = videoFiles;
    m_scanning = false;
    
    emit scanningChanged();
    emit filesChanged();
    
    qDebug() << "USB scan complete:" 
             << m_audioFiles.size() << "audio," 
             << m_videoFiles.size() << "video files";
}

void UsbManager::scanDirectory(const QString& dirPath, QStringList& audioOut, QStringList& videoOut){
    static const QStringList skipFolders = {
        "Android", ".thumbnails", ".cache", "com.", ".trashed", 
        ".stfolder", ".stversions", "node_modules", ".git",
        "System Volume Information", "$RECYCLE.BIN"
    };
    
    int fileCount = 0;
    const int MAX_FILES = 5000;
    
    // Manual recursion to support skipping directories in Qt6
    std::function<void(const QString&)> scanRecursive = [&](const QString& currentPath) {
        if(fileCount >= MAX_FILES) return;
        
        QDir dir(currentPath);
        if(!dir.exists()) return;
        
        dir.setFilter(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot);
        QFileInfoList entries = dir.entryInfoList();
        
        for(const QFileInfo& info : entries) {
            if(fileCount >= MAX_FILES) break;
            
            if(info.isDir()) {
                QString dirName = info.fileName();
                bool shouldSkip = false;
                for(const QString& skip : skipFolders) {
                    if(dirName.startsWith(skip, Qt::CaseInsensitive)) {
                        shouldSkip = true;
                        break;
                    }
                }
                if(!shouldSkip) {
                    scanRecursive(info.filePath());
                }
            } else {
                QString ext = info.suffix().toLower();
                if(AUDIO_EXTENSIONS.contains(ext)) {
                    audioOut << info.filePath();
                    fileCount++;
                } else if(VIDEO_EXTENSIONS.contains(ext)) {
                    videoOut << info.filePath();
                    fileCount++;
                }
                
                if(fileCount % 100 == 0) {
                    QThread::msleep(1);
                }
            }
        }
    };
    
    scanRecursive(dirPath);
}

QString UsbManager::fileName(const QString& path) const{ return QFileInfo(path).completeBaseName(); }

void UsbManager::disconnectDevice(){
    m_scanning = false;  // Signal thread to stop
    emit scanningChanged();
    
    if(m_scanWatcher && m_scanWatcher->isRunning()) {
        m_scanWatcher->waitForFinished();  // Wait for thread to finish
    }
    
    m_connected = false;
    m_mountPath = "";
    m_driveName = "";
    m_audioFiles.clear();
    m_videoFiles.clear();
    emit connectedChanged();
    emit mountPathChanged();
    emit driveNameChanged();
    emit filesChanged();
}