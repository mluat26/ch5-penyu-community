import Foundation

enum UserRole: String, CaseIterable, Identifiable, Sendable {
    case admin
    case ranger
    case viewer

    var id: String { rawValue }
}

struct AppUserEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var organizationID: UUID?
    var role: UserRole?
}
