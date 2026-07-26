#pragma once

#include <QObject>
#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QTimer>
#include <QString>
#include <QVariantMap>
#include <QMap>

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

private:
    void init();
    void poll();                          // called every 0.5s, reads everything fresh
    void sendAvrcpCommand(const QString& command);

    // Returns property map for a given object path + interface
    // using raw QDBusArgument to avoid deserialization issues
    QVariantMap getProperties(const QString& path, const QString& iface);

    // Returns all BlueZ object paths + their interfaces
    // key = object path, value = list of interface names
    QMap<QString, QStringList> getManagedObjects();

    bool m_connected     = false;
    QString m_deviceName;
    QString m_deviceAddress;
    QString m_devicePath;
    QString m_playerPath;
    QString m_trackTitle;
    QString m_trackArtist;
    QString m_trackAlbum;
    QString m_playerStatus;

    QDBusConnection m_bus;
    QTimer* m_pollTimer = nullptr;
};