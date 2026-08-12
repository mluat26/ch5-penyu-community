import Foundation

struct AppUser: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var organizationID: UUID?
    var role: UserRole?
}
