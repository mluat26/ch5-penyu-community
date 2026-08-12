import Foundation

/// Wire representation of the current `public.organiztion` table.
///
/// The table name is misspelled in the database. Keep the correct Swift name
/// and use `organiztion` only when a future repository selects the table.
struct OrganizationDTO: Codable, Sendable {
    let id: UUID
    let name: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "date_created"
    }
}

extension OrganizationDTO {
    func toEntity() throws -> Organization {
        guard let name, !name.isEmpty else {
            throw DataMappingError.missingRequiredValue(field: "organiztion.name")
        }
        guard let createdAt else {
            throw DataMappingError.missingRequiredValue(field: "organiztion.date_created")
        }

        return Organization(id: id, name: name, createdAt: createdAt)
    }
}
