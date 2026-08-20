import Foundation

/// Wire representation of the current `public.nest` table.
struct NestDTO: Codable, Sendable {
    let id: UUID
    let numberOfEggs: Int
    let dateEggsLaid: Date?
    let datePredictedHatch: Date?
    let bucketID: String?
    let nestNumber: String?
    let latitude: Double?
    let longitude: Double?
    let locationAddress: String?
    let successEggsHatch: Int?
    let failEggsHatch: Int?
    let eggsUnhatched: Int?
    let hatcheryID: UUID?
    let placementRow: Int?
    let placementColumn: Int?
    let founderID: UUID?
    let nextInspectionDate: Date?
    /// Read-only. Deliberately absent from the insert and update payloads: this
    /// is a `timestamptz`, and the shared encoder writes every Date as
    /// `yyyy-MM-dd` (SupabaseConfig.swift), so sending it would truncate an
    /// audit timestamp to local midnight. Postgres supplies it.
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case numberOfEggs = "number_of_eggs"
        case dateEggsLaid = "date_eggs_laid"
        case datePredictedHatch = "date_predicted_hatch"
        case bucketID = "bucket_id"
        case nestNumber = "nest_number"
        case latitude
        case longitude
        case locationAddress = "location_address"
        case successEggsHatch = "success_eggs_hatch"
        case failEggsHatch = "fail_eggs_hatch"
        case eggsUnhatched = "eggs_unhatched"
        case hatcheryID = "hatchery_id"
        case placementRow = "placement_row"
        case placementColumn = "placement_col"
        case founderID = "founder_id"
        case nextInspectionDate = "next_inspection_date"
        case createdAt = "created_at"
    }
}

/// Insert payload for the columns currently present in `public.nest`.
struct NestInsertDTO: Encodable, Sendable {
    let numberOfEggs: Int
    let dateEggsLaid: Date?
    let datePredictedHatch: Date?
    let bucketID: String?
    let nestNumber: String?
    let latitude: Double?
    let longitude: Double?
    let locationAddress: String?
    let hatcheryID: UUID
    let placementRow: Int?
    let placementColumn: Int?
    let founderID: UUID?
    let nextInspectionDate: Date?

    enum CodingKeys: String, CodingKey {
        case numberOfEggs = "number_of_eggs"
        case dateEggsLaid = "date_eggs_laid"
        case datePredictedHatch = "date_predicted_hatch"
        case bucketID = "bucket_id"
        case nestNumber = "nest_number"
        case latitude
        case longitude
        case locationAddress = "location_address"
        case hatcheryID = "hatchery_id"
        case placementRow = "placement_row"
        case placementColumn = "placement_col"
        case founderID = "founder_id"
        case nextInspectionDate = "next_inspection_date"
    }
}

/// Edit payload for the columns currently present in `public.nest`.
///
/// `hatchery_id` and `founder_id` are deliberately absent: re-parenting a nest
/// is not an edit the app offers.
struct NestUpdateDTO: Encodable, Sendable {
    let numberOfEggs: Int
    let dateEggsLaid: Date?
    let datePredictedHatch: Date?
    let bucketID: String?
    let nestNumber: String?
    let latitude: Double?
    let longitude: Double?
    let locationAddress: String?
    let nextInspectionDate: Date?
    let placementRow: Int?
    let placementColumn: Int?

    enum CodingKeys: String, CodingKey {
        case numberOfEggs = "number_of_eggs"
        case dateEggsLaid = "date_eggs_laid"
        case datePredictedHatch = "date_predicted_hatch"
        case bucketID = "bucket_id"
        case nestNumber = "nest_number"
        case latitude
        case longitude
        case locationAddress = "location_address"
        case nextInspectionDate = "next_inspection_date"
        case placementRow = "placement_row"
        case placementColumn = "placement_col"
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
            datePredictedHatch: datePredictedHatch,
            bucketID: bucketID,
            nestNumber: nestNumber,
            latitude: latitude,
            longitude: longitude,
            locationAddress: locationAddress,
            successEggsHatch: successEggsHatch,
            failEggsHatch: failEggsHatch,
            eggsUnhatched: eggsUnhatched,
            placementRow: placementRow,
            placementColumn: placementColumn,
            nextInspectionDate: nextInspectionDate,
            createdAt: createdAt
        )
    }
}

extension CreateNestInput {
    func toDTO() -> NestInsertDTO {
        NestInsertDTO(
            numberOfEggs: numberOfEggs,
            dateEggsLaid: dateEggsLaid,
            datePredictedHatch: datePredictedHatch,
            bucketID: bucketID,
            nestNumber: nestNumber,
            latitude: latitude,
            longitude: longitude,
            locationAddress: locationAddress,
            hatcheryID: hatcheryID,
            placementRow: placementRow,
            placementColumn: placementColumn,
            founderID: founderID,
            nextInspectionDate: nextInspectionDate
        )
    }
}

extension UpdateNestInput {
    func toDTO() -> NestUpdateDTO {
        NestUpdateDTO(
            numberOfEggs: numberOfEggs,
            dateEggsLaid: dateEggsLaid,
            datePredictedHatch: datePredictedHatch,
            bucketID: bucketID,
            nestNumber: nestNumber,
            latitude: latitude,
            longitude: longitude,
            locationAddress: locationAddress,
            nextInspectionDate: nextInspectionDate,
            placementRow: placementRow,
            placementColumn: placementColumn
        )
    }
}
