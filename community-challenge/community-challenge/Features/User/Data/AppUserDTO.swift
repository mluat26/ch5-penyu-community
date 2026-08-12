import Foundation

/// Exact wire representation for the future `profiles`/users Supabase table.
struct AppUserDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let organizationID: UUID?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case role
        case organizationID = "organization_id"
    }
}

extension AppUserDTO {
    func toEntity() throws -> AppUser {
        let mappedRole: UserRole?
        if let role {
            guard let value = UserRole(rawValue: role) else {
                throw DataMappingError.invalidEnum(field: "role", value: role)
            }
            mappedRole = value
        } else {
            mappedRole = nil
        }

        return AppUser(
            id: id,
            name: name,
            organizationID: organizationID,
            role: mappedRole
        )
    }
}
