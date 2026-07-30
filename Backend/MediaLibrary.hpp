#pragma once
#include <QAbstractListModel>
#include <QFileSystemWatcher>
#include <QList>
#include <QStandardPaths>
#include <QString>
#include <QStringList>

/*
 * An on-disk media library, listed from C++. One instance per media type —
 * see MediaLibrary::music() and MediaLibrary::video().
 *
 * This deliberately does not use Qt.labs.folderlistmodel: that is a separate
 * QML plugin which is not part of the base qtdeclarative install, and images
 * that omit it fail at load time with "FolderListModel is not a type" — the
 * whole UI, not just the page that used it. Listing a directory is a few lines
 * of QDir, so the runtime dependency is not worth the risk on a head unit.
 *
 * Roles are fileName / filePath, matching what the QML delegates expect.
 */
class MediaLibrary : public QAbstractListModel {
    Q_OBJECT

    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QString folder READ folder WRITE setFolder NOTIFY folderChanged)

public:
    enum Roles {
        FileNameRole = Qt::UserRole + 1,
        FilePathRole,
    };

    /*
     * nameFilters      glob patterns the player can actually decode
     * desktopLocation  XDG directory to use on a developer machine
     * envOverride      environment variable that overrides the location
     * logTag           short prefix for this library's warnings
     */
    MediaLibrary(QStringList nameFilters,
                 QStandardPaths::StandardLocation desktopLocation,
                 QString envOverride,
                 QString logTag,
                 QObject *parent = nullptr);

    // The two libraries the UI uses. Both resolve to /var/lib/ivi/media on the
    // head unit and to the user's own directory on a desktop; they differ only
    // in which file extensions they list.
    static MediaLibrary *music(QObject *parent = nullptr);
    static MediaLibrary *video(QObject *parent = nullptr);

    int      rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int     count()  const { return int(m_entries.size()); }
    QString folder() const { return m_folder; }
    void    setFolder(const QString &folder);

    // Re-read the directory. Called automatically when it changes on disk.
    Q_INVOKABLE void refresh();

signals:
    void countChanged();
    void folderChanged();

private:
    struct Entry {
        QString name;
        QString path;
    };

    /*
     * Where this library lives:
     *
     *   1. $<envOverride>                  — explicit override, always wins
     *   2. /var/lib/ivi/media              — on a Jetson/Tegra board
     *   3. XDG dir, else $HOME/<fallback>  — developer machine
     *
     * Resolved at runtime rather than hardcoded: the developer machine and the
     * target board do not share a username, so a literal /home/<someone>/Music
     * silently lists nothing on the vehicle. On the head unit the path is fixed
     * whether or not it exists yet, so it is identical on every unit.
     */
    QString resolveFolder() const;

    QString watchTarget() const;
    void    rewatch(const QStringList &paths);
    void    diagnoseEmpty() const;
    void    onDirectoryChanged();

    const QStringList                      m_nameFilters;
    const QStandardPaths::StandardLocation m_desktopLocation;
    const QString                          m_envOverride;
    const QString                          m_logTag;

    QString            m_folder;
    QList<Entry>       m_entries;
    QFileSystemWatcher m_watcher;
};
