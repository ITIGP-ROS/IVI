#pragma once
#include <QAbstractListModel>
#include <QFileSystemWatcher>
#include <QList>
#include <QString>

/*
 * The on-disk music library, listed from C++.
 *
 * This deliberately does not use Qt.labs.folderlistmodel: that is a separate
 * QML plugin which is not part of the base qtdeclarative install, and images
 * that omit it fail at load time with "FolderListModel is not a type" — the
 * whole UI, not just this page. Listing a directory is a few lines of QDir, so
 * the runtime dependency is not worth the risk on a head unit.
 *
 * Roles match the old model's (fileName, filePath) so the delegate is unchanged.
 */
class MusicLibrary : public QAbstractListModel {
    Q_OBJECT

    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QString folder READ folder WRITE setFolder NOTIFY folderChanged)

public:
    enum Roles {
        FileNameRole = Qt::UserRole + 1,
        FilePathRole,
    };

    explicit MusicLibrary(QObject *parent = nullptr);

    int      rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int     count()  const { return int(m_tracks.size()); }
    QString folder() const { return m_folder; }
    void    setFolder(const QString &folder);

    // Re-read the directory. Called automatically when it changes on disk.
    Q_INVOKABLE void refresh();

    /*
     * Where the library lives. Resolved at runtime rather than hardcoded: the
     * developer machine and the target board do not share a username, so a
     * literal /home/<someone>/Music silently lists nothing on the vehicle.
     *
     *   1. $IVI_MUSIC_DIR                — explicit override, always wins
     *   2. /var/lib/ivi/media            — on a Jetson/Tegra board
     *   3. XDG music dir, else $HOME/Music — developer machine
     *
     * On the head unit the path is fixed whether or not it exists yet, so it
     * is identical on every vehicle. On a desktop the first existing candidate
     * wins, falling back to the conventional location so the empty state still
     * names somewhere sensible.
     */
    static QString defaultFolder();

signals:
    void countChanged();
    void folderChanged();

private:
    struct Track {
        QString name;
        QString path;
    };

    QString watchTarget() const;
    void    rewatch();
    void    onDirectoryChanged();

    QString            m_folder;
    QString            m_watchedPath;
    QList<Track>       m_tracks;
    QFileSystemWatcher m_watcher;
};
