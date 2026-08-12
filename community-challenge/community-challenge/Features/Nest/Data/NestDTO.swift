import Foundation

/// Exact wire representation for the future `nests` Supabase table.
struct NestDTO: Codable, Sendable {
    let id: UUID
    let hatcheryID: UUID
    let founderID: UUID?
    let numberOfEggs: Int
    let dateEggsLaid: Date?
    let datePredictedHatch: Date?
    let placeEggsLaid: String?
    let successEggsHatch: Int?
    let failEggsHatch: Int?
    let placementRow: Int?
    let placementColumn: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case hatcheryID = "hatchery_id"
        case founderID = "founder_id"
        case numberOfEggs = "number_of_eggs"
        case dateEggsLaid = "date_eggs_laid"
        case datePredictedHatch = "date_predicted_hatch"
        case placeEggsLaid = "place_eggs_laid"
        case successEggsHatch = "success_eggs_hatch"
        case failEggsHatch = "fail_eggs_hatch"
        case placementRow = "placement_row"
        case placementColumn = "placement_col"
    }
}

struct NestInsertDTO: Encodable, Sendable {
    let hatcheryID: UUID
    let founderID: UUID?
    let numberOfEggs: Int
    let dateEggsLaid: Date?
    let datePredictedHatch: Date?
    let placeEggsLaid: String?
    let placementRow: Int?
    let placementColumn: Int?

    enum CodingKeys: String, CodingKey {
        case hatcheryID = "hatchery_id"
        case founderID = "founder_id"
        case numberOfEggs = "number_of_eggs"
        case dateEggsLaid = "date_eggs_laid"
        case datePredictedHatch = "date_predicted_hatch"
        case placeEggsLaid = "place_eggs_laid"
        case placementRow = "placement_row"
        case placementColumn = "placement_col"
    }
}

struct HatchResultUpdateDTO: Encodable, Sendable {
    let successEggsHatch: Int
    let failEggsHatch: Int

    enum CodingKeys: String, CodingKey {
        case successEggsHatch = "success_eggs_hatch"
        case failEggsHatch = "fail_eggs_hatch"
    }
}

extension NestDTO {
    func toEntity() -> Nest {
        Nest(
            id: id,
            hatcheryID: hatcheryID,
            founderID: founderID,
            numberOfEggs: numberOfEggs,
            dateEggsLaid: dateEggsLaid,
            datePredictedHatch: datePredictedHatch,
            placeEggsLaid: placeEggsLaid,
            successEggsHatch: successEggsHatch,
            failEggsHatch: failEggsHatch,
            placementRow: placementRow,
            placementColumn: placementColumn
        )
    }
}

extension CreateNestInput {
    func toDTO() -> NestInsertDTO {
        NestInsertDTO(
            hatcheryID: hatcheryID,
            founderID: founderID,
            numberOfEggs: numberOfEggs,
            dateEggsLaid: dateEggsLaid,
            datePredictedHatch: datePredictedHatch,
            placeEggsLaid: placeEggsLaid,
            placementRow: placementRow,
            placementColumn: placementColumn
        )
    }
}

extension RecordHatchResultInput {
    func toDTO() -> HatchResultUpdateDTO {
        HatchResultUpdateDTO(
            successEggsHatch: successEggsHatch,
            failEggsHatch: failEggsHatch
        )
    }
}
