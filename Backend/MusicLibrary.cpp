#include "MusicLibrary.hpp"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcessEnvironment>
#include <QStandardPaths>

namespace {

// Kept in step with what the shared MediaPlayer can actually decode.
const QStringList kAudioFilters = {
    QStringLiteral("*.mp3"),  QStringLiteral("*.wav"),
    QStringLiteral("*.aac"),  QStringLiteral("*.flac"),
    QStringLiteral("*.ogg"),  QStringLiteral("*.m4a"),
};

// Where the library lives on the head unit. A system path, not a home
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

MusicLibrary::MusicLibrary(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged,
            this, &MusicLibrary::onDirectoryChanged);

    const QString resolved = defaultFolder();

    // The deployment is expected to ship this directory, but create it if the
    // image did not: it is the fixed library location, so falling back to a
    // home directory on the head unit would only make the failure confusing.
    if (resolved == kEmbeddedMediaDir && !QFileInfo::exists(resolved)) {
        if (!QDir().mkpath(resolved))
            qWarning() << "[music] cannot create" << resolved << "— check permissions";
    }

    setFolder(resolved);
}

QString MusicLibrary::defaultFolder()
{
    const QProcessEnvironment env = QProcessEnvironment::systemEnvironment();

    // An explicit override always wins, on either machine.
    const QString override = env.value(QStringLiteral("IVI_MUSIC_DIR"));
    if (!override.isEmpty())
        return override;

    // On the head unit the location is fixed, whether or not it exists yet —
    // no falling back to $HOME, so the path is the same on every vehicle.
    if (onTegra())
        return kEmbeddedMediaDir;

    // Developer machine: the conventional per-user music directory.
    QStringList candidates;
    const QString xdg = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
    if (!xdg.isEmpty())
        candidates << xdg;

    const QString home = env.value(QStringLiteral("HOME"));
    if (!home.isEmpty())
        candidates << home + QStringLiteral("/Music");

    for (const QString &path : std::as_const(candidates)) {
        if (QFileInfo(path).isDir())
            return path;
    }

    // Nothing exists yet — name the conventional location so the empty state
    // points somewhere the user can actually create.
    return candidates.isEmpty() ? QDir::homePath() + QStringLiteral("/Music")
                                : candidates.first();
}

void MusicLibrary::setFolder(const QString &folder)
{
    if (m_folder == folder)
        return;

    m_folder = folder;
    emit folderChanged();

    rewatch();
    refresh();
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
QString MusicLibrary::watchTarget() const
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

void MusicLibrary::rewatch()
{
    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());

    m_watchedPath = watchTarget();
    if (!m_watchedPath.isEmpty())
        m_watcher.addPath(m_watchedPath);
}

void MusicLibrary::onDirectoryChanged()
{
    // Re-arm whenever the directory we should be watching has moved — the
    // library appearing, vanishing, or an intermediate level being created.
    if (watchTarget() != m_watchedPath)
        rewatch();

    refresh();
}

void MusicLibrary::refresh()
{
    QList<Track> tracks;

    QDir dir(m_folder);
    if (dir.exists()) {
        const QFileInfoList entries =
            dir.entryInfoList(kAudioFilters, QDir::Files | QDir::Readable,
                              QDir::Name | QDir::IgnoreCase);
        tracks.reserve(entries.size());
        for (const QFileInfo &info : entries)
            tracks.append({ info.fileName(), info.absoluteFilePath() });
    } else {
        qWarning() << "[music] library folder does not exist:" << m_folder;
    }

    if (tracks.size() == m_tracks.size()) {
        bool same = true;
        for (int i = 0; i < tracks.size(); ++i) {
            if (tracks[i].path != m_tracks[i].path) {
                same = false;
                break;
            }
        }
        if (same)
            return;
    }

    const int previousCount = int(m_tracks.size());

    beginResetModel();
    m_tracks = std::move(tracks);
    endResetModel();

    // A directory that gained and lost a file in one go keeps the same count;
    // the reset above already refreshed the view, so only signal a real change.
    if (int(m_tracks.size()) != previousCount)
        emit countChanged();
}

int MusicLibrary::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return int(m_tracks.size());
}

QVariant MusicLibrary::data(const QModelIndex &index, int role) const
{
    if (index.row() < 0 || index.row() >= m_tracks.size())
        return {};

    const Track &track = m_tracks.at(index.row());
    switch (role) {
    case FileNameRole: return track.name;
    case FilePathRole: return track.path;
    default:           return {};
    }
}

QHash<int, QByteArray> MusicLibrary::roleNames() const
{
    return {
        { FileNameRole, QByteArrayLiteral("fileName") },
        { FilePathRole, QByteArrayLiteral("filePath") },
    };
}
