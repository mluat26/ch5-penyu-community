import Foundation

/// A sensor device supplying readings for the nest it is installed in.
///
/// `nestID` is nil while the device is unassigned — a spare, or one recalled
/// from a nest that was deleted. At most one device may be assigned to a given
/// nest.
struct DeviceEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var nestID: UUID?
    var installedAt: Date

    var isAssigned: Bool { nestID != nil }
}
