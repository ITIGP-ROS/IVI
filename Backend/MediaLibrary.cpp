#include "MediaLibrary.hpp"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcessEnvironment>

namespace {

// Where both libraries live on the head unit. A system path, not a home
// directory: on the target the app may run as a service user with no $HOME
// worth speaking of, and the media set belongs to the vehicle, not to a login.
const QString kEmbeddedMediaDir = QStringLiteral("/var/lib/ivi/media");

/*
 * True when running on the Jetson (or any Tegra board).
 *
 * Detected at runtime rather than through a build flag, because the target
 * image is built from a Yocto recipe we do not control — a -D define would
 * have to be threaded through someone else's recipe to take effect, and would
 * silently do nothing if it were ever dropped.
 */
bool onTegra()
{
    // The device tree is the authoritative check: it comes from the hardware,
    // so it holds on a Yocto image just as it does on a JetPack rootfs.
    // "compatible" is checked first because model strings vary by carrier
    // board while the SoC compatible string does not.
    for (const char *node : { "/proc/device-tree/compatible",
                              "/proc/device-tree/model" }) {
        QFile f{QLatin1String(node)};
        if (!f.open(QIODevice::ReadOnly))
            continue;
        const QByteArray value = f.readAll();
        if (value.contains("tegra") || value.contains("Tegra") || value.contains("Jetson"))
            return true;
    }

    // Fallback for a JetPack/L4T rootfs. Not present on every Yocto build,
    // which is why it is not the primary check.
    return QFileInfo::exists(QStringLiteral("/etc/nv_tegra_release"));
}

} // namespace

MediaLibrary::MediaLibrary(QStringList nameFilters,
                           QStandardPaths::StandardLocation desktopLocation,
                           QString envOverride,
                           QString logTag,
                           QObject *parent)
    : QAbstractListModel(parent)
    , m_nameFilters(std::move(nameFilters))
    , m_desktopLocation(desktopLocation)
    , m_envOverride(std::move(envOverride))
    , m_logTag(std::move(logTag))
{
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged,
            this, &MediaLibrary::onDirectoryChanged);

    const QString resolved = resolveFolder();

    // The deployment is expected to ship this directory, but create it if the
    // image did not: it is the fixed library location, so falling back to a
    // home directory on the head unit would only make the failure confusing.
    if (resolved == kEmbeddedMediaDir && !QFileInfo::exists(resolved)) {
        if (!QDir().mkpath(resolved))
            qWarning().noquote() << m_logTag << "cannot create" << resolved
                                 << "— check permissions";
    }

    setFolder(resolved);
}

MediaLibrary *MediaLibrary::music(QObject *parent)
{
    return new MediaLibrary({ QStringLiteral("*.mp3"),  QStringLiteral("*.wav"),
                              QStringLiteral("*.aac"),  QStringLiteral("*.flac"),
                              QStringLiteral("*.ogg"),  QStringLiteral("*.m4a") },
                            QStandardPaths::MusicLocation,
                            QStringLiteral("IVI_MUSIC_DIR"),
                            QStringLiteral("[music]"),
                            parent);
}

MediaLibrary *MediaLibrary::video(QObject *parent)
{
    return new MediaLibrary({ QStringLiteral("*.mp4"),  QStringLiteral("*.mkv"),
                              QStringLiteral("*.avi"),  QStringLiteral("*.mov"),
                              QStringLiteral("*.wmv"),  QStringLiteral("*.webm"),
                              QStringLiteral("*.m4v") },
                            QStandardPaths::MoviesLocation,
                            QStringLiteral("IVI_VIDEO_DIR"),
                            QStringLiteral("[video]"),
                            parent);
}

QString MediaLibrary::resolveFolder() const
{
    const QProcessEnvironment env = QProcessEnvironment::systemEnvironment();

    // An explicit override always wins, on either machine.
    const QString override = env.value(m_envOverride);
    if (!override.isEmpty())
        return override;

    // On the head unit the location is fixed, whether or not it exists yet —
    // no falling back to $HOME, so the path is the same on every vehicle.
    if (onTegra())
        return kEmbeddedMediaDir;

    // Developer machine: the conventional per-user directory.
    const QString xdg = QStandardPaths::writableLocation(m_desktopLocation);
    if (!xdg.isEmpty())
        return xdg;

    // No XDG configuration at all — fall back to the directory name Qt would
    // have used, so the empty state still names somewhere sensible.
    const QString home = env.value(QStringLiteral("HOME"), QDir::homePath());
    return home + (m_desktopLocation == QStandardPaths::MoviesLocation
                       ? QStringLiteral("/Videos")
                       : QStringLiteral("/Music"));
}

void MediaLibrary::setFolder(const QString &folder)
{
    if (m_folder == folder)
        return;

    m_folder = folder;
    emit folderChanged();

    refresh();      // also arms the watcher on whatever it ends up scanning
}

/*
 * The directory to watch: the library itself when it exists, otherwise the
 * nearest ancestor that does.
 *
 * Watching only the immediate parent is not enough — on a fresh image none of
 * /var/lib/ivi/media exists, so there would be nothing to attach to and the
 * page would stay empty for the whole session. Climbing to the nearest real
 * directory means each level being created wakes us up in turn.
 */
QString MediaLibrary::watchTarget() const
{
    if (m_folder.isEmpty())
        return {};

    QString path = QFileInfo(m_folder).absoluteFilePath();
    while (!path.isEmpty()) {
        if (QFileInfo(path).isDir())
            return path;

        const QString parent = QFileInfo(path).absolutePath();
        if (parent == path)     // reached the root without finding one
            break;
        path = parent;
    }
    return {};
}

void MediaLibrary::rewatch(const QStringList &paths)
{
    const QStringList current = m_watcher.directories();
    if (current == paths)
        return;

    if (!current.isEmpty())
        m_watcher.removePaths(current);
    if (!paths.isEmpty())
        m_watcher.addPaths(paths);
}

void MediaLibrary::onDirectoryChanged()
{
    // refresh() re-derives the whole watch set, so this covers the library
    // appearing, vanishing, an intermediate level being created, and a new
    // album folder being dropped in.
    refresh();
}

void MediaLibrary::refresh()
{
    QList<Entry> entries;
    QStringList  toWatch;

    // Watch the nearest existing ancestor even when the library itself is not
    // there yet, so the page fills in the moment it is created.
    const QString anchor = watchTarget();
    if (!anchor.isEmpty())
        toWatch.append(anchor);

    if (QFileInfo(m_folder).isDir()) {
        /*
         * Walk subdirectories, not just the top level. Copying an album in as
         * a folder is the obvious thing to do, and listing only loose files at
         * the root makes that look like an empty library with no error.
         *
         * Breadth-first, so top-level files sort ahead of album contents.
         * NoSymLinks on the directory listing keeps a symlink loop from
         * hanging the scan.
         */
        QStringList queue{ QFileInfo(m_folder).absoluteFilePath() };
        while (!queue.isEmpty()) {
            const QString path = queue.takeFirst();
            if (!toWatch.contains(path))
                toWatch.append(path);

            QDir dir(path);
            const QFileInfoList subs =
                dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks,
                                  QDir::Name | QDir::IgnoreCase);
            for (const QFileInfo &sub : subs)
                queue.append(sub.absoluteFilePath());

            const QFileInfoList found =
                dir.entryInfoList(m_nameFilters, QDir::Files,
                                  QDir::Name | QDir::IgnoreCase);
            for (const QFileInfo &info : found) {
                // Readability is checked per file rather than through
                // QDir::Readable so an unreadable one can be reported instead
                // of silently vanishing from the list.
                if (!info.isReadable()) {
                    qWarning().noquote() << m_logTag << "skipping unreadable file:"
                                         << info.absoluteFilePath();
                    continue;
                }
                entries.append({ info.fileName(), info.absoluteFilePath() });
            }
        }
    } else {
        qWarning().noquote() << m_logTag << "library folder does not exist:" << m_folder;
    }

    rewatch(toWatch);

    if (entries.isEmpty())
        diagnoseEmpty();

    if (entries.size() == m_entries.size()) {
        bool same = true;
        for (int i = 0; i < entries.size(); ++i) {
            if (entries[i].path != m_entries[i].path) {
                same = false;
                break;
            }
        }
        if (same)
            return;
    }

    const int previousCount = int(m_entries.size());

    beginResetModel();
    m_entries = std::move(entries);
    endResetModel();

    // A directory that gained and lost a file in one go keeps the same count;
    // the reset above already refreshed the view, so only signal a real change.
    if (int(m_entries.size()) != previousCount)
        emit countChanged();
}

/*
 * Say why a scan came up empty.
 *
 * On the head unit there is no file manager to check with, so a bare "0
 * tracks" is indistinguishable between the four things that actually cause it:
 * files put somewhere other than the library path, a directory that does not
 * exist, files the app cannot read, and formats this library does not list.
 * One log line separates them.
 */
void MediaLibrary::diagnoseEmpty() const
{
    const QFileInfo info(m_folder);
    if (!info.isDir()) {
        qWarning().noquote() << m_logTag << "empty:" << m_folder
                             << "is not a directory — put media there, or set"
                             << m_envOverride << "to the directory you are using";
        return;
    }
    if (!info.isReadable()) {
        qWarning().noquote() << m_logTag << "empty:" << m_folder
                             << "is not readable by this process — check ownership"
                                " and permissions";
        return;
    }

    // Everything that is there, so a mismatch in extension is visible at a
    // glance. Capped: a wrong path could be something enormous.
    QStringList sample;
    int         total = 0;
    QStringList queue{ info.absoluteFilePath() };
    while (!queue.isEmpty() && total < 200) {
        QDir dir(queue.takeFirst());
        const QFileInfoList subs =
            dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks);
        for (const QFileInfo &sub : subs)
            queue.append(sub.absoluteFilePath());

        const QFileInfoList files = dir.entryInfoList(QDir::Files);
        total += int(files.size());
        for (const QFileInfo &f : files) {
            if (sample.size() >= 5)
                break;
            sample.append(dir.relativeFilePath(f.absoluteFilePath()));
        }
    }

    if (total == 0)
        qWarning().noquote() << m_logTag << "empty:" << m_folder
                             << "contains no files at all";
    else
        qWarning().noquote() << m_logTag << "empty:" << m_folder << "holds" << total
                             << "file(s), none matching" << m_nameFilters.join(u' ')
                             << "— e.g." << sample.join(QStringLiteral(", "));
}

int MediaLibrary::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return int(m_entries.size());
}

QVariant MediaLibrary::data(const QModelIndex &index, int role) const
{
    if (index.row() < 0 || index.row() >= m_entries.size())
        return {};

    const Entry &entry = m_entries.at(index.row());
    switch (role) {
    case FileNameRole: return entry.name;
    case FilePathRole: return entry.path;
    default:           return {};
    }
}

QHash<int, QByteArray> MediaLibrary::roleNames() const
{
    return {
        { FileNameRole, QByteArrayLiteral("fileName") },
        { FilePathRole, QByteArrayLiteral("filePath") },
    };
}
