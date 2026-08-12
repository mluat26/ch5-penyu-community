import Foundation

/// Exact wire representation for the future `temperature_readings` Supabase table.
struct HeatReadingDTO: Codable, Sendable {
    let id: UUID
    let nestID: UUID
    let sensorID: UUID?
    let position: String?
    let depthCM: Double?
    let temperatureC: Double
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
        case temperatureC = "temperature_c"
        case timestamp
        case alert
        case sensorStatus = "sensor_status"
        case batteryVoltage = "battery_voltage"
        case signalRSSIDBM = "signal_rssi_dbm"
    }
}

extension HeatReadingDTO {
    func toEntity() throws -> HeatReading {
        let mappedAlert: AlertLevel?
        if let alert {
            guard let value = AlertLevel(rawValue: alert) else {
                throw DataMappingError.invalidEnum(field: "alert", value: alert)
            }
            mappedAlert = value
        } else {
            mappedAlert = nil
        }

        let mappedSensorStatus: SensorStatus?
        if let sensorStatus {
            guard let value = SensorStatus(rawValue: sensorStatus) else {
                throw DataMappingError.invalidEnum(field: "sensor_status", value: sensorStatus)
            }
            mappedSensorStatus = value
        } else {
            mappedSensorStatus = nil
        }

        return HeatReading(
            id: id,
            nestID: nestID,
            sensorID: sensorID,
            position: position,
            depthCM: depthCM,
            temperatureC: temperatureC,
            timestamp: timestamp,
            alert: mappedAlert,
            sensorStatus: mappedSensorStatus,
            batteryVoltage: batteryVoltage,
            signalRSSIDBM: signalRSSIDBM
        )
    }
}
