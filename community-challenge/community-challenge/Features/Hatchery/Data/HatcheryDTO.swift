import Foundation

/// Exact wire representation for the future `hatcheries` Supabase table.
struct HatcheryDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let shape: String
    let numberOfRows: Int
    let numberOfColumns: Int
    let lengthM: Double
    let widthM: Double
    let organizationID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case shape
        case numberOfRows = "number_of_row"
        case numberOfColumns = "number_of_column"
        case lengthM = "length_m"
        case widthM = "width_m"
        case organizationID = "organization_id"
    }
}

struct HatcheryInsertDTO: Encodable, Sendable {
    let name: String
    let shape: String
    let numberOfRows: Int
    let numberOfColumns: Int
    let lengthM: Double
    let widthM: Double
    let organizationID: UUID?

    enum CodingKeys: String, CodingKey {
        case name
        case shape
        case numberOfRows = "number_of_row"
        case numberOfColumns = "number_of_column"
        case lengthM = "length_m"
        case widthM = "width_m"
        case organizationID = "organization_id"
    }
}

extension HatcheryDTO {
    func toEntity() throws -> Hatchery {
        guard let mappedShape = HatcheryShape(rawValue: shape) else {
            throw DataMappingError.invalidEnum(field: "shape", value: shape)
        }

        return Hatchery(
            id: id,
            name: name,
            shape: mappedShape,
            numberOfRows: numberOfRows,
            numberOfColumns: numberOfColumns,
            lengthM: lengthM,
            widthM: widthM,
            organizationID: organizationID
        )
    }
}

extension CreateHatcheryInput {
    func toDTO() -> HatcheryInsertDTO {
        HatcheryInsertDTO(
            name: name,
            shape: shape.rawValue,
            numberOfRows: numberOfRows,
            numberOfColumns: numberOfColumns,
            lengthM: lengthM,
            widthM: widthM,
            organizationID: organizationID
        )
    }
}
