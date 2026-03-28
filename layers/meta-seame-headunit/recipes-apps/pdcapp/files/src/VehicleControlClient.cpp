#include "VehicleControlClient.h"
#include <QDebug>
#include <functional>

VehicleControlClient::VehicleControlClient(QObject *parent)
    : QObject(parent)
    , m_currentGear("P")
    , m_currentDistance(200)  // Default: far distance (no alert)
    , m_serviceAvailable(false)
{
    qDebug() << "[PDCApp] VehicleControlClient created";
}

VehicleControlClient::~VehicleControlClient()
{
    if (m_proxy) {
        m_proxy.reset();
    }
    qDebug() << "[PDCApp] VehicleControlClient destroyed";
}

void VehicleControlClient::initialize()
{
    qDebug() << "[PDCApp] Initializing VehicleControl vsomeip client...";

    // Get CommonAPI runtime
    m_runtime = CommonAPI::Runtime::get();
    if (!m_runtime) {
        qCritical() << "[PDCApp] Failed to get CommonAPI runtime!";
        return;
    }

    // Build proxy
    const std::string domain = "local";
    const std::string instance = "vehiclecontrol.VehicleControl";
    const std::string connection = "PDCApp_client";

    m_proxy = m_runtime->buildProxy<VehicleControlProxy>(domain, instance, connection);

    if (!m_proxy) {
        qCritical() << "[PDCApp] Failed to build VehicleControl proxy!";
        return;
    }

    qDebug() << "[PDCApp] VehicleControl proxy created";
    qDebug() << "   Domain:" << QString::fromStdString(domain);
    qDebug() << "   Instance:" << QString::fromStdString(instance);

    // Subscribe to availability status
    m_proxy->getProxyStatusEvent().subscribe(
        std::bind(&VehicleControlClient::onAvailabilityChanged, this, std::placeholders::_1)
    );

    // Setup event subscriptions
    setupEventSubscriptions();

    qDebug() << "[PDCApp] VehicleControlClient initialized";
}

void VehicleControlClient::setupEventSubscriptions()
{
    if (!m_proxy) {
        qWarning() << "[PDCApp] Cannot setup subscriptions: proxy is null";
        return;
    }

    qDebug() << "[PDCApp] Subscribing to VehicleControl events...";

    // Subscribe to gearDistanceChanged event (primary source for distance)
    m_proxy->getGearDistanceChangedEvent().subscribe(
        [this](std::string newGear, std::string oldGear, uint16_t distance, uint64_t timestamp) {
            this->onGearDistanceChanged(newGear, oldGear, distance, timestamp);
        }
    );

    // Subscribe to vehicleStateChanged event (for gear updates)
    m_proxy->getVehicleStateChangedEvent().subscribe(
        [this](std::string gear, uint16_t speed, uint16_t voltage, int16_t current, uint64_t timestamp) {
            this->onVehicleStateChanged(gear, speed, voltage, current, timestamp);
        }
    );

    qDebug() << "[PDCApp] Event subscriptions setup complete";
}

void VehicleControlClient::onGearDistanceChanged(std::string newGear, std::string oldGear, uint16_t distance, uint64_t timestamp)
{
    Q_UNUSED(oldGear);
    Q_UNUSED(timestamp);

    QString qNewGear = QString::fromStdString(newGear);

    // Update gear if changed
    if (m_currentGear != qNewGear) {
        m_currentGear = qNewGear;
        emit currentGearChanged(m_currentGear);
        qDebug() << "[PDCApp] Gear changed to:" << m_currentGear;
    }

    // Update distance (important for PDC visualization)
    int newDistance = static_cast<int>(distance);
    if (m_currentDistance != newDistance) {
        m_currentDistance = newDistance;
        emit currentDistanceChanged(m_currentDistance);
        qDebug() << "[PDCApp] Distance updated:" << m_currentDistance << "cm";
    }
}

void VehicleControlClient::onVehicleStateChanged(std::string gear, uint16_t speed, uint16_t voltage, int16_t current, uint64_t timestamp)
{
    Q_UNUSED(speed);
    Q_UNUSED(voltage);
    Q_UNUSED(current);
    Q_UNUSED(timestamp);

    QString qGear = QString::fromStdString(gear);

    // Update gear only if changed
    if (m_currentGear != qGear) {
        m_currentGear = qGear;
        emit currentGearChanged(m_currentGear);
    }
}

void VehicleControlClient::onAvailabilityChanged(CommonAPI::AvailabilityStatus status)
{
    bool wasAvailable = m_serviceAvailable;
    m_serviceAvailable = (status == CommonAPI::AvailabilityStatus::AVAILABLE);

    if (m_serviceAvailable != wasAvailable) {
        qDebug() << "[PDCApp] VehicleControl service availability changed:"
                 << (m_serviceAvailable ? "AVAILABLE" : "NOT AVAILABLE");
        emit serviceAvailableChanged(m_serviceAvailable);
    }

    if (m_serviceAvailable) {
        qDebug() << "[PDCApp] VehicleControlECU service is now available!";
    } else {
        qWarning() << "[PDCApp] VehicleControlECU service is not available";
    }
}
