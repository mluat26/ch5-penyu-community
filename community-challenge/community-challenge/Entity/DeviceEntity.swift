import Foundation

/// A sensor device supplying readings for the nest it is currently installed
/// in. `nestID` is projected from the active `device_assignment` row rather
/// than stored directly on the physical device.
///
/// `nestID` is nil while the device is unassigned — a spare, or one recalled
/// from a nest that was deleted. Assignment history remains server-side, while
/// at most one active device may be assigned to a given nest.
struct DeviceEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var nestID: UUID?
    var installedAt: Date

    var isAssigned: Bool { nestID != nil }
}
