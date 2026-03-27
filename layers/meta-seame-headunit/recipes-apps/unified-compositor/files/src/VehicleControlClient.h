#ifndef VEHICLECONTROLCLIENT_H
#define VEHICLECONTROLCLIENT_H

#include <QObject>
#include <QString>
#include <CommonAPI/CommonAPI.hpp>
#include <v1/vehiclecontrol/VehicleControlProxy.hpp>

using namespace v1::vehiclecontrol;

class VehicleControlClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentGear READ currentGear NOTIFY currentGearChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)

public:
    explicit VehicleControlClient(QObject *parent = nullptr);
    virtual ~VehicleControlClient();

    QString currentGear() const { return m_currentGear; }
    bool connected() const { return m_isConnected; }

public slots:
    void connectToService();
    void disconnectFromService();

signals:
    void currentGearChanged(const QString& gear);
    void connectedChanged(bool connected);

private:
    std::shared_ptr<VehicleControlProxy<>> m_proxy;
    std::shared_ptr<CommonAPI::Runtime> m_runtime;

    QString m_currentGear;
    bool m_isConnected;

    void setupEventSubscriptions();
    void onGearDistanceChanged(std::string newGear, std::string oldGear, uint64_t timestamp);
    void onAvailabilityChanged(CommonAPI::AvailabilityStatus status);
};

#endif // VEHICLECONTROLCLIENT_H
