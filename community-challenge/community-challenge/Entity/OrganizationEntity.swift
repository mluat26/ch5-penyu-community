import Foundation

struct OrganizationEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    /// The identifier a person reads and shares ("ORG-0000000"), which is not
    /// the primary key. Absent for organizations created before the membership
    /// migration allocated codes.
    var code: String?
    /// Whoever created the organization's first hatchery. Ownership is recorded
    /// here rather than as a role: a role is per-organization, ownership is
    /// per-hatchery, and only the owner may manage members.
    var ownerID: UUID?

    var displayCode: String { code ?? "—" }
}
