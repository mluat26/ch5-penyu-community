import Foundation

struct OrganizationEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    /// The identifier a person reads and shares ("ORG-0000000"), which is not
    /// the primary key. Absent for organizations created before the membership
    /// migration allocated codes.
    var code: String?

    var displayCode: String { code ?? "—" }
}
