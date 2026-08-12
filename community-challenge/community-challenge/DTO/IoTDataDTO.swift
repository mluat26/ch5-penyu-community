import Foundation

/// Wire representation of the current `public.iotdata` table.
///
/// It intentionally has no `toEntity()` mapper yet: the table does not record
/// when a reading was made, while `HeatReadingEntity` requires that timestamp
/// to calculate a trustworthy dashboard.
struct IoTDataDTO: Codable, Sendable {
    let id: UUID
    let nestID: UUID
    let sensorID: UUID?
    let temperature: Double?
    let alert: String?

    enum CodingKeys: String, CodingKey {
        case id
        case nestID = "nest_id"
        case sensorID = "sensor_id"
        case temperature
        case alert
    }
}
