import Foundation

/// Exact wire representation for the future `organizations` Supabase table.
struct OrganizationDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "date_created"
    }
}

extension OrganizationDTO {
    func toEntity() -> Organization {
        Organization(id: id, name: name, createdAt: createdAt)
    }
}
