#ifndef CAR_INFO_H
#define CAR_INFO_H

#include <QObject>

class CarInfo : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double currVel READ getCurrVel WRITE setCurrVel NOTIFY currVelChanged FINAL) // velocity

    // GPS data
    Q_PROPERTY(double currLatitude READ getcurrLatitude WRITE setCurrLatitude NOTIFY currLatitudeChanged FINAL)
    Q_PROPERTY(double currLongitude READ getcurrLongitude WRITE setCurrLongitude NOTIFY currLongitudeChanged FINAL)
    Q_PROPERTY(double currAltitude READ getcurrAltitude WRITE setCurrAltitude NOTIFY currAltitudeChanged FINAL)

    // IMU Data  (Orientation)
    Q_PROPERTY(double currImuX READ getcurrImuX WRITE setCurrImuX NOTIFY currImuXChanged FINAL)
    Q_PROPERTY(double currImuY READ getcurrImuY WRITE setCurrImuY NOTIFY currImuYChanged FINAL)
    Q_PROPERTY(double currImuZ READ getcurrImuZ WRITE setCurrImuZ NOTIFY currImuZChanged FINAL)
    Q_PROPERTY(double currImuW READ getcurrImuW WRITE setCurrImuW NOTIFY currImuWChanged FINAL)



public:
    explicit CarInfo(QObject *parent = nullptr);

    double getCurrVel() const;
    void setCurrVel(double newCurrVel);

    double getcurrLatitude() const;
    void setCurrLatitude(double newCurrLatitude);

    double getcurrLongitude() const;
    void setCurrLongitude(double newCurrLongitude);

    double getcurrAltitude() const;
    void setCurrAltitude(double newCurrAltitude);

    double getcurrImuX() const;
    void setCurrImuX(double newCurrImuX);

    double getcurrImuY() const;
    void setCurrImuY(double newCurrImuY);

    double getcurrImuZ() const;
    void setCurrImuZ(double newCurrImuZ);

    double getcurrImuW() const;
    void setCurrImuW(double newCurrImuW);

signals:
    void currVelChanged();

    void currLatitudeChanged();

    void currLongitudeChanged();

    void currAltitudeChanged();

    void currImuXChanged();

    void currImuYChanged();

    void currImuZChanged();

    void currImuWChanged();

private:
    double m_currVel;

    // GPS
    double m_currLatitude;
    double m_currLongitude;
    double m_currAltitude;

    // IMU (Orientation)
    double m_currImuX;
    double m_currImuY;
    double m_currImuZ;
    double m_currImuW;
};

#endif // CAR_INFO_H
