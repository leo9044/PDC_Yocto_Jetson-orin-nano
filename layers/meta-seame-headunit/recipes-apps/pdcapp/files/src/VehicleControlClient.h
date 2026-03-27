#ifndef VEHICLECONTROLCLIENT_H
#define VEHICLECONTROLCLIENT_H

#include <QObject>
#include <QString>
#include <CommonAPI/CommonAPI.hpp>
#include <v1/vehiclecontrol/VehicleControlProxy.hpp>

using namespace v1::vehiclecontrol;

/**
 * @brief VehicleControl vsomeip client for PDCApp
 *
 * Subscribes to VehicleControlECU running on Raspberry Pi
 * and receives distance data for PDC visualization
 */
class VehicleControlClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentGear READ currentGear NOTIFY currentGearChanged)
    Q_PROPERTY(int currentDistance READ currentDistance NOTIFY currentDistanceChanged)
    Q_PROPERTY(bool serviceAvailable READ serviceAvailable NOTIFY serviceAvailableChanged)

public:
    explicit VehicleControlClient(QObject *parent = nullptr);
    virtual ~VehicleControlClient();

    // Property getters
    QString currentGear() const { return m_currentGear; }
    int currentDistance() const { return m_currentDistance; }
    bool serviceAvailable() const { return m_serviceAvailable; }

    // Initialize connection
    void initialize();

signals:
    void currentGearChanged(const QString& gear);
    void currentDistanceChanged(int distance);
    void serviceAvailableChanged(bool available);

private:
    // CommonAPI proxy
    std::shared_ptr<VehicleControlProxy<>> m_proxy;
    std::shared_ptr<CommonAPI::Runtime> m_runtime;

    // Current state
    QString m_currentGear;
    int m_currentDistance;
    bool m_serviceAvailable;

    // Event subscriptions
    void setupEventSubscriptions();
    void onGearDistanceChanged(std::string newGear, std::string oldGear, uint16_t distance, uint64_t timestamp);
    void onVehicleStateChanged(std::string gear, uint16_t speed, uint8_t battery, uint64_t timestamp);
    void onAvailabilityChanged(CommonAPI::AvailabilityStatus status);
};

#endif // VEHICLECONTROLCLIENT_H
