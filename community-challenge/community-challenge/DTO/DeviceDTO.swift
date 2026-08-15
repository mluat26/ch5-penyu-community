import Foundation

/// Wire representation of `public.device_current_assignment`.
///
/// The view keeps the app's existing shape while the database retains a full
/// device-assignment history behind it.
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

/// RPC payload for an atomic device registration, rename, or reassignment.
/// A nullable nest ID intentionally means "unassign"; callers never write a
/// mutable `device.nest_id` because that column no longer exists.
struct DeviceSaveDTO: Encodable, Sendable {
    let deviceID: UUID?
    let name: String
    let nestID: UUID?

    enum CodingKeys: String, CodingKey {
        case deviceID = "p_device_id"
        case name = "p_name"
        case nestID = "p_nest_id"
    }
}

/// `save_device` returns the physical device row. The repository follows that
/// up with the assignment projection so callers receive its current nest too.
struct DeviceSaveResultDTO: Decodable, Sendable {
    let id: UUID
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
    func toSaveDTO() -> DeviceSaveDTO {
        DeviceSaveDTO(deviceID: nil, name: name, nestID: nestID)
    }
}

extension UpdateDeviceInput {
    func toSaveDTO(deviceID: UUID) -> DeviceSaveDTO {
        DeviceSaveDTO(deviceID: deviceID, name: name, nestID: nestID)
    }
}
