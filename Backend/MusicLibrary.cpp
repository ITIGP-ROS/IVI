#include "MusicLibrary.hpp"

#include <QDebug>
#include <QDir>
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

} // namespace

MusicLibrary::MusicLibrary(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged,
            this, &MusicLibrary::refresh);

    setFolder(defaultFolder());
}

QString MusicLibrary::defaultFolder()
{
    const QProcessEnvironment env = QProcessEnvironment::systemEnvironment();

    QStringList candidates;
    const QString override = env.value(QStringLiteral("IVI_MUSIC_DIR"));
    if (!override.isEmpty())
        candidates << override;

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

void MusicLibrary::rewatch()
{
    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());

    if (!m_folder.isEmpty() && QFileInfo(m_folder).isDir())
        m_watcher.addPath(m_folder);
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
