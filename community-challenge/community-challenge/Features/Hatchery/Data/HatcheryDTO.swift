import Foundation

/// Wire representation of the current `public.hatchery` table.
///
/// The database currently spells `number_of_collumn` with two l's. Keep that
/// spelling at this boundary until a reviewed database migration renames it.
struct HatcheryDTO: Codable, Sendable {
    let id: UUID
    let numberOfRows: Int
    let numberOfColumns: Int
    let name: String?
    let shape: String?
    let lengthM: Double?
    let widthM: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case numberOfRows = "number_of_row"
        case numberOfColumns = "number_of_collumn"
        case name
        case shape
        case lengthM = "length_m"
        case widthM = "width_m"
    }
}

/// Insert payload for the current `public.hatchery` table.
struct HatcheryInsertDTO: Encodable, Sendable {
    let numberOfRows: Int
    let numberOfColumns: Int
    let name: String
    let shape: String
    let lengthM: Double
    let widthM: Double

    enum CodingKeys: String, CodingKey {
        case numberOfRows = "number_of_row"
        case numberOfColumns = "number_of_collumn"
        case name
        case shape
        case lengthM = "length_m"
        case widthM = "width_m"
    }
}

extension HatcheryDTO {
    func toEntity() throws -> Hatchery {
        guard let name, !name.isEmpty else {
            throw DataMappingError.missingRequiredValue(field: "hatchery.name")
        }
        guard let shape else {
            throw DataMappingError.missingRequiredValue(field: "hatchery.shape")
        }
        guard let mappedShape = HatcheryShape(rawValue: shape) else {
            throw DataMappingError.invalidEnum(field: "hatchery.shape", value: shape)
        }
        guard let lengthM, let widthM else {
            throw DataMappingError.missingRequiredValue(field: "hatchery dimensions")
        }
        guard numberOfRows > 0, numberOfColumns > 0, lengthM > 0, widthM > 0 else {
            throw DataMappingError.missingRequiredValue(field: "positive hatchery dimensions")
        }

        return Hatchery(
            id: id,
            name: name,
            shape: mappedShape,
            numberOfRows: numberOfRows,
            numberOfColumns: numberOfColumns,
            lengthM: lengthM,
            widthM: widthM,
            // `organization_id` does not exist in the pulled schema yet.
            organizationID: nil
        )
    }
}

extension CreateHatcheryInput {
    func toDTO() throws -> HatcheryInsertDTO {
        guard organizationID == nil else {
            throw DataMappingError.schemaColumnUnavailable(
                table: "hatchery",
                column: "organization_id"
            )
        }

        return HatcheryInsertDTO(
            numberOfRows: numberOfRows,
            numberOfColumns: numberOfColumns,
            name: name,
            shape: shape.rawValue,
            lengthM: lengthM,
            widthM: widthM
        )
    }
}
