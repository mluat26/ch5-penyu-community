import Foundation

/// Wire representation of the current `public.nest` table.
///
/// The current schema has no `date_predicted_hatch` or `fail_eggs_hatch`
/// columns. Those richer domain fields remain presentation/product work until a
/// reviewed migration adds their persistence contract.
struct NestDTO: Codable, Sendable {
    let id: UUID
    let numberOfEggs: Int
    let dateEggsLaid: Date?
    let placeEggsLaid: Date?
    let successEggsHatch: Int?
    let hatcheryID: UUID?
    let placementRow: Int?
    let placementColumn: Int?
    let founderID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case numberOfEggs = "number_of_eggs"
        case dateEggsLaid = "date_eggs_laid"
        case placeEggsLaid = "place_eggs_laid"
        case successEggsHatch = "success_eggs_hatch"
        case hatcheryID = "hatchery_id"
        case placementRow = "placement_row"
        case placementColumn = "placement_col"
        case founderID = "founder_id"
    }
}

/// Insert payload for the columns currently present in `public.nest`.
struct NestInsertDTO: Encodable, Sendable {
    let numberOfEggs: Int
    let dateEggsLaid: Date?
    let placeEggsLaid: Date?
    let hatcheryID: UUID
    let placementRow: Int?
    let placementColumn: Int?
    let founderID: UUID?

    enum CodingKeys: String, CodingKey {
        case numberOfEggs = "number_of_eggs"
        case dateEggsLaid = "date_eggs_laid"
        case placeEggsLaid = "place_eggs_laid"
        case hatcheryID = "hatchery_id"
        case placementRow = "placement_row"
        case placementColumn = "placement_col"
        case founderID = "founder_id"
    }
}

/// Update payload supported by the current `public.nest` table.
struct HatchResultUpdateDTO: Encodable, Sendable {
    let successEggsHatch: Int

    enum CodingKeys: String, CodingKey {
        case successEggsHatch = "success_eggs_hatch"
    }
}

extension NestDTO {
    func toEntity() throws -> NestEntity {
        guard let hatcheryID else {
            throw DataMappingError.missingRequiredValue(field: "nest.hatchery_id")
        }

        return NestEntity(
            id: id,
            hatcheryID: hatcheryID,
            founderID: founderID,
            numberOfEggs: numberOfEggs,
            dateEggsLaid: dateEggsLaid,
            // Not represented by the current remote schema.
            datePredictedHatch: nil,
            placeEggsLaid: placeEggsLaid,
            successEggsHatch: successEggsHatch,
            // Not represented by the current remote schema.
            failEggsHatch: nil,
            placementRow: placementRow,
            placementColumn: placementColumn
        )
    }
}

extension CreateNestInput {
    func toDTO() throws -> NestInsertDTO {
        guard datePredictedHatch == nil else {
            throw DataMappingError.schemaColumnUnavailable(
                table: "nest",
                column: "date_predicted_hatch"
            )
        }

        return NestInsertDTO(
            numberOfEggs: numberOfEggs,
            dateEggsLaid: dateEggsLaid,
            placeEggsLaid: placeEggsLaid,
            hatcheryID: hatcheryID,
            placementRow: placementRow,
            placementColumn: placementColumn,
            founderID: founderID
        )
    }
}

extension RecordHatchResultInput {
    func toDTO() throws -> HatchResultUpdateDTO {
        guard failEggsHatch == 0 else {
            throw DataMappingError.schemaColumnUnavailable(
                table: "nest",
                column: "fail_eggs_hatch"
            )
        }

        return HatchResultUpdateDTO(successEggsHatch: successEggsHatch)
    }
}
