#pragma once

#include <QObject>
#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QString>
#include <QVariantMap>
#include <QSet>

/*
 * BluetoothManager — A2DP/AVRCP media state for the player UI.
 *
 * Event-driven: BlueZ emits PropertiesChanged for Device1 and MediaPlayer1, so
 * there is no polling. The previous 0.5s poll issued N+3 *blocking* D-Bus calls
 * per tick on the GUI thread, which scales with the number of devices BlueZ has
 * ever cached and stalls the HMI whenever bluetoothd is slow.
 *
 * QML-facing API is unchanged.
 */
class BluetoothManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool     connected     READ connected     NOTIFY connectedChanged)
    Q_PROPERTY(QString  deviceName    READ deviceName    NOTIFY deviceNameChanged)
    Q_PROPERTY(QString  deviceAddress READ deviceAddress NOTIFY deviceAddressChanged)
    Q_PROPERTY(QString  trackTitle    READ trackTitle    NOTIFY trackInfoChanged)
    Q_PROPERTY(QString  trackArtist   READ trackArtist   NOTIFY trackInfoChanged)
    Q_PROPERTY(QString  trackAlbum    READ trackAlbum    NOTIFY trackInfoChanged)
    Q_PROPERTY(QString  playerStatus  READ playerStatus  NOTIFY playerStatusChanged)

public:
    explicit BluetoothManager(QObject* parent = nullptr);

    bool    connected()     const { return m_connected;     }
    QString deviceName()    const { return m_deviceName;    }
    QString deviceAddress() const { return m_deviceAddress; }
    QString trackTitle()    const { return m_trackTitle;    }
    QString trackArtist()   const { return m_trackArtist;   }
    QString trackAlbum()    const { return m_trackAlbum;    }
    QString playerStatus()  const { return m_playerStatus;  }

public slots:
    void play();
    void pause();
    void next();
    void previous();
    void stop();

signals:
    void connectedChanged();
    void deviceNameChanged();
    void deviceAddressChanged();
    void trackInfoChanged();
    void playerStatusChanged();
    void errorOccurred(const QString& message);

private slots:
    void onPropertiesChanged(const QString &interface, const QVariantMap &changed,
                             const QStringList &invalidated);
    void onInterfacesAdded(const QDBusObjectPath &path, const QVariantMap &interfaces);
    void onInterfacesRemoved(const QDBusObjectPath &path, const QStringList &interfaces);
    void onBlueZOwnerChanged(const QString &name, const QString &oldOwner,
                             const QString &newOwner);

private:
    void rescan();                                   // full state refresh (async)
    void selectDevice(const QString &path, const QVariantMap &props);
    void selectPlayer(const QString &path);
    void clearDevice();
    void applyDeviceProps(const QVariantMap &props);
    void applyPlayerProps(const QVariantMap &props);
    void subscribe(const QString &path);
    void sendAvrcpCommand(const QString& command);

    bool    m_connected = false;
    QString m_deviceName;
    QString m_deviceAddress;
    QString m_devicePath;
    QString m_playerPath;
    QString m_trackTitle;
    QString m_trackArtist;
    QString m_trackAlbum;
    QString m_playerStatus;

    QSet<QString> m_subscribed;
    QDBusConnection m_bus;
};
