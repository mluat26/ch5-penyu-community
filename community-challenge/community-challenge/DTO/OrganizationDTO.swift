import Foundation

/// Wire representation of `public.organization`.
///
/// The table was originally created as `organiztion`; the organization
/// membership migration renamed it, so the spelling now matches this type.
struct OrganizationDTO: Codable, Sendable {
    let id: UUID
    let name: String?
    let createdAt: Date?
    /// The human-readable identifier shown on the profile screen
    /// ("ORG-0000000"), distinct from the primary key.
    let code: String?
    let ownerID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "date_created"
        case code
        case ownerID = "owner_id"
    }
}

extension OrganizationDTO {
    func toEntity() throws -> OrganizationEntity {
        guard let name, !name.isEmpty else {
            throw DataMappingError.missingRequiredValue(field: "organization.name")
        }
        guard let createdAt else {
            throw DataMappingError.missingRequiredValue(field: "organization.date_created")
        }

        return OrganizationEntity(
            id: id,
            name: name,
            createdAt: createdAt,
            code: code,
            ownerID: ownerID
        )
    }
}
