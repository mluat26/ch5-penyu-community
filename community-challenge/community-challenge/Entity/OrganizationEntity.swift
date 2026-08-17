import Foundation

struct OrganizationEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
}
