import Foundation

/// Wire representation of `public.inspection`.
struct InspectionDTO: Codable, Sendable {
    let id: UUID
    let nestID: UUID
    let inspectedOn: Date
    let outcome: String
    let eggsHatched: Int?
    let eggsRotten: Int?
    let nextInspectionDate: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case nestID = "nest_id"
        case inspectedOn = "inspected_on"
        case outcome
        case eggsHatched = "eggs_hatched"
        case eggsRotten = "eggs_rotten"
        case nextInspectionDate = "next_inspection_date"
    }
}

/// Insert payload. `id` and `created_at` are database-assigned.
struct InspectionInsertDTO: Encodable, Sendable {
    let nestID: UUID
    let inspectedOn: Date
    let outcome: String
    let eggsHatched: Int?
    let eggsRotten: Int?
    let nextInspectionDate: Date?

    enum CodingKeys: String, CodingKey {
        case nestID = "nest_id"
        case inspectedOn = "inspected_on"
        case outcome
        case eggsHatched = "eggs_hatched"
        case eggsRotten = "eggs_rotten"
        case nextInspectionDate = "next_inspection_date"
    }
}

/// Edit payload for correcting a recorded visit.
///
/// `nest_id` and `inspected_on` are deliberately absent: a correction fixes what
/// was found, it does not move the visit to another nest or another day.
struct InspectionUpdateDTO: Encodable, Sendable {
    let outcome: String
    let eggsHatched: Int?
    let eggsRotten: Int?
    let nextInspectionDate: Date?

    enum CodingKeys: String, CodingKey {
        case outcome
        case eggsHatched = "eggs_hatched"
        case eggsRotten = "eggs_rotten"
        case nextInspectionDate = "next_inspection_date"
    }
}

extension InspectionDTO {
    func toEntity() throws -> InspectionEntity {
        guard let mappedOutcome = InspectionOutcome(rawValue: outcome) else {
            throw DataMappingError.invalidEnum(field: "inspection.outcome", value: outcome)
        }

        return InspectionEntity(
            id: id,
            nestID: nestID,
            inspectedOn: inspectedOn,
            outcome: mappedOutcome,
            eggsHatched: eggsHatched,
            eggsRotten: eggsRotten,
            nextInspectionDate: nextInspectionDate
        )
    }
}

extension RecordInspectionInput {
    func toDTO() -> InspectionInsertDTO {
        InspectionInsertDTO(
            nestID: nestID,
            inspectedOn: inspectedOn,
            outcome: outcome.rawValue,
            eggsHatched: eggsHatched,
            eggsRotten: eggsRotten,
            nextInspectionDate: nextInspectionDate
        )
    }
}

extension CorrectInspectionInput {
    func toDTO() -> InspectionUpdateDTO {
        InspectionUpdateDTO(
            outcome: outcome.rawValue,
            eggsHatched: eggsHatched,
            eggsRotten: eggsRotten,
            nextInspectionDate: nextInspectionDate
        )
    }
}
