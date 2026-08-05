#include "inc/car_info.h"

CarInfo::CarInfo(QObject *parent)
    : QObject{parent}
{}

double CarInfo::getCurrVel() const
{
    return m_currVel;
}

void CarInfo::setCurrVel(double newCurrVel)
{
    if (qFuzzyCompare(m_currVel, newCurrVel))
        return;
    m_currVel = newCurrVel;
    emit currVelChanged();
}

double CarInfo::getcurrLatitude() const
{
    return m_currLatitude;
}

void CarInfo::setCurrLatitude(double newCurrLatitude)
{
    if (qFuzzyCompare(m_currLatitude, newCurrLatitude))
        return;
    m_currLatitude = newCurrLatitude;
    emit currLatitudeChanged();
}

double CarInfo::getcurrLongitude() const
{
    return m_currLongitude;
}

void CarInfo::setCurrLongitude(double newCurrLongitude)
{
    if (qFuzzyCompare(m_currLongitude, newCurrLongitude))
        return;
    m_currLongitude = newCurrLongitude;
    emit currLongitudeChanged();
}

double CarInfo::getcurrAltitude() const
{
    return m_currAltitude;
}

void CarInfo::setCurrAltitude(double newCurrAltitude)
{
    if (qFuzzyCompare(m_currAltitude, newCurrAltitude))
        return;
    m_currAltitude = newCurrAltitude;
    emit currAltitudeChanged();
}

double CarInfo::getcurrImuX() const
{
    return m_currImuX;
}

void CarInfo::setCurrImuX(double newCurrImuX)
{
    if (qFuzzyCompare(m_currImuX, newCurrImuX))
        return;
    m_currImuX = newCurrImuX;
    emit currImuXChanged();
}

double CarInfo::getcurrImuY() const
{
    return m_currImuY;
}

void CarInfo::setCurrImuY(double newCurrImuY)
{
    if (qFuzzyCompare(m_currImuY, newCurrImuY))
        return;
    m_currImuY = newCurrImuY;
    emit currImuYChanged();
}

double CarInfo::getcurrImuZ() const
{
    return m_currImuZ;
}

void CarInfo::setCurrImuZ(double newCurrImuZ)
{
    if (qFuzzyCompare(m_currImuZ, newCurrImuZ))
        return;
    m_currImuZ = newCurrImuZ;
    emit currImuZChanged();
}

double CarInfo::getcurrImuW() const
{
    return m_currImuW;
}

void CarInfo::setCurrImuW(double newCurrImuW)
{
    if (qFuzzyCompare(m_currImuW, newCurrImuW))
        return;
    m_currImuW = newCurrImuW;
    emit currImuWChanged();
}
