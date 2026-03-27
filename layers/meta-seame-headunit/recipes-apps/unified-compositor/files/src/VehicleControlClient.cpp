#include "VehicleControlClient.h"
#include <QDebug>
#include <functional>

VehicleControlClient::VehicleControlClient(QObject *parent)
    : QObject(parent)
    , m_currentGear("P")
    , m_isConnected(false)
{
    qDebug() << "[UnifiedCompositor] VehicleControlClient created";
}

VehicleControlClient::~VehicleControlClient()
{
    disconnectFromService();
    qDebug() << "[UnifiedCompositor] VehicleControlClient destroyed";
}

void VehicleControlClient::connectToService()
{
    qDebug() << "[UnifiedCompositor] Connecting to VehicleControl service...";

    m_runtime = CommonAPI::Runtime::get();
    if (!m_runtime) {
        qCritical() << "[UnifiedCompositor] Failed to get CommonAPI runtime!";
        emit connectedChanged(false);
        return;
    }

    const std::string domain = "local";
    const std::string instance = "vehiclecontrol.VehicleControl";
    const std::string connection = "UnifiedCompositor_client";

    m_proxy = m_runtime->buildProxy<VehicleControlProxy>(domain, instance, connection);

    if (!m_proxy) {
        qCritical() << "[UnifiedCompositor] Failed to build VehicleControl proxy!";
        emit connectedChanged(false);
        return;
    }

    qDebug() << "[UnifiedCompositor] VehicleControl proxy created";

    m_proxy->getProxyStatusEvent().subscribe(
        std::bind(&VehicleControlClient::onAvailabilityChanged, this, std::placeholders::_1)
    );

    setupEventSubscriptions();
}

void VehicleControlClient::disconnectFromService()
{
    if (m_proxy) {
        m_proxy.reset();
        m_isConnected = false;
        emit connectedChanged(false);
    }
}

void VehicleControlClient::setupEventSubscriptions()
{
    if (!m_proxy) return;

    qDebug() << "[UnifiedCompositor] Subscribing to gearDistanceChanged events...";

    m_proxy->getGearDistanceChangedEvent().subscribe(
        [this](std::string newGear, std::string oldGear, uint16_t /*distance*/, uint64_t timestamp) {
            this->onGearDistanceChanged(newGear, oldGear, timestamp);
        }
    );
}

void VehicleControlClient::onGearDistanceChanged(std::string newGear, std::string oldGear, uint64_t /*timestamp*/)
{
    QString qNewGear = QString::fromStdString(newGear);
    if (m_currentGear != qNewGear) {
        m_currentGear = qNewGear;
        emit currentGearChanged(m_currentGear);
        qDebug() << "[UnifiedCompositor] Gear changed:"
                 << QString::fromStdString(oldGear) << "->" << qNewGear;
    }
}

void VehicleControlClient::onAvailabilityChanged(CommonAPI::AvailabilityStatus status)
{
    bool wasConnected = m_isConnected;
    m_isConnected = (status == CommonAPI::AvailabilityStatus::AVAILABLE);

    if (m_isConnected != wasConnected) {
        qDebug() << "[UnifiedCompositor] VehicleControl service:"
                 << (m_isConnected ? "AVAILABLE" : "NOT AVAILABLE");
        emit connectedChanged(m_isConnected);
    }
}
