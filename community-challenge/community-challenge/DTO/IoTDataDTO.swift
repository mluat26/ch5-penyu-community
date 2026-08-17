import Foundation

/// Read-only wire representation of `public.iotdata`.
///
/// IoT devices never write this shape from the iOS app. A trusted ingest
/// service resolves `nest_id` from `sensor_id` / `public.device.id` before the
/// database row is inserted.
struct IoTDataDTO: Codable, Sendable {
    let id: UUID
    let nestID: UUID
    let sensorID: UUID?
    let position: String?
    let depthCM: Double?
    let temperature: Double?
    let timestamp: Date
    let alert: String?
    let sensorStatus: String?
    let batteryVoltage: Double?
    let signalRSSIDBM: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case nestID = "nest_id"
        case sensorID = "sensor_id"
        case position
        case depthCM = "depth_cm"
        case temperature
        case timestamp
        case alert
        case sensorStatus = "sensor_status"
        case batteryVoltage = "battery_voltage"
        case signalRSSIDBM = "signal_rssi_dbm"
    }
}

extension IoTDataDTO {
    func toEntity() throws -> IoTDataEntity {
        // Temperature is the reason a reading exists. Everything else is
        // context, so only this one blocks the mapping.
        guard let temperature else {
            throw DataMappingError.missingRequiredValue(field: "iotdata.temperature")
        }

        // Unrecognised enum values are dropped rather than thrown on: firmware
        // reporting an unknown status should not hide an otherwise usable
        // temperature from the dashboard.
        return IoTDataEntity(
            id: id,
            nestID: nestID,
            sensorID: sensorID,
            position: position,
            depthCM: depthCM,
            temperatureC: temperature,
            timestamp: timestamp,
            alert: alert.flatMap(AlertLevel.init(rawValue:)),
            sensorStatus: sensorStatus.flatMap(SensorStatus.init(rawValue:)),
            batteryVoltage: batteryVoltage,
            signalRSSIDBM: signalRSSIDBM
        )
    }
}
