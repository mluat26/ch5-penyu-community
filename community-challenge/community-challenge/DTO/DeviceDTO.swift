import Foundation

/// Wire representation of `public.device`.
struct DeviceDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let nestID: UUID?
    let installedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nestID = "nest_id"
        case installedAt = "installed_at"
    }
}

/// Insert payload. `id` and `installed_at` are database-assigned.
struct DeviceInsertDTO: Encodable, Sendable {
    let name: String
    let nestID: UUID?

    enum CodingKeys: String, CodingKey {
        case name
        case nestID = "nest_id"
    }
}

/// Edit payload. Renaming and reassigning are the only supported edits;
/// `installed_at` records when the device first entered service.
struct DeviceUpdateDTO: Encodable, Sendable {
    let name: String
    let nestID: UUID?

    enum CodingKeys: String, CodingKey {
        case name
        case nestID = "nest_id"
    }
}

extension DeviceDTO {
    func toEntity() -> DeviceEntity {
        DeviceEntity(
            id: id,
            name: name,
            nestID: nestID,
            installedAt: installedAt
        )
    }
}

extension RegisterDeviceInput {
    func toDTO() -> DeviceInsertDTO {
        DeviceInsertDTO(name: name, nestID: nestID)
    }
}

extension UpdateDeviceInput {
    func toDTO() -> DeviceUpdateDTO {
        DeviceUpdateDTO(name: name, nestID: nestID)
    }
}
