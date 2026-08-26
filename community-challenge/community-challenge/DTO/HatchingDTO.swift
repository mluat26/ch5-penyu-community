import Foundation

/// Wire representation of `public.hatching`.
struct HatchingDTO: Codable, Sendable {
    let id: UUID
    let nestID: UUID
    let hatchedOn: Date
    let eggsHatched: Int
    let eggsRotten: Int
    let eggsUnhatched: Int
    /// Both read-only, and deliberately absent from the insert and update
    /// payloads below. `recorded_by` is owned by the assign_hatching_recorder
    /// trigger and `created_at` by a column default; sending either would be
    /// ignored at best, and `created_at` is a `timestamptz` the shared encoder
    /// would truncate to a bare date on the way out.
    let recordedBy: UUID?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case nestID = "nest_id"
        case hatchedOn = "hatched_on"
        case eggsHatched = "eggs_hatched"
        case eggsRotten = "eggs_rotten"
        case eggsUnhatched = "eggs_unhatched"
        case recordedBy = "recorded_by"
        case createdAt = "created_at"
    }
}

/// Insert payload. `id` and `created_at` are database-assigned.
struct HatchingInsertDTO: Encodable, Sendable {
    let nestID: UUID
    let hatchedOn: Date
    let eggsHatched: Int
    let eggsRotten: Int
    let eggsUnhatched: Int

    enum CodingKeys: String, CodingKey {
        case nestID = "nest_id"
        case hatchedOn = "hatched_on"
        case eggsHatched = "eggs_hatched"
        case eggsRotten = "eggs_rotten"
        case eggsUnhatched = "eggs_unhatched"
    }
}

/// Edit payload for correcting a recorded tally. `nest_id` is absent: a
/// correction fixes the counts, it does not move the result to another nest.
struct HatchingUpdateDTO: Encodable, Sendable {
    let hatchedOn: Date
    let eggsHatched: Int
    let eggsRotten: Int
    let eggsUnhatched: Int

    enum CodingKeys: String, CodingKey {
        case hatchedOn = "hatched_on"
        case eggsHatched = "eggs_hatched"
        case eggsRotten = "eggs_rotten"
        case eggsUnhatched = "eggs_unhatched"
    }
}

extension HatchingDTO {
    func toEntity() -> HatchingEntity {
        HatchingEntity(
            id: id,
            nestID: nestID,
            hatchedOn: hatchedOn,
            eggsHatched: eggsHatched,
            eggsRotten: eggsRotten,
            eggsUnhatched: eggsUnhatched,
            recordedBy: recordedBy,
            createdAt: createdAt
        )
    }
}

extension RecordHatchingInput {
    func toDTO() -> HatchingInsertDTO {
        HatchingInsertDTO(
            nestID: nestID,
            hatchedOn: hatchedOn,
            eggsHatched: eggsHatched,
            eggsRotten: eggsRotten,
            eggsUnhatched: eggsUnhatched
        )
    }
}

extension CorrectHatchingInput {
    func toDTO() -> HatchingUpdateDTO {
        HatchingUpdateDTO(
            hatchedOn: hatchedOn,
            eggsHatched: eggsHatched,
            eggsRotten: eggsRotten,
            eggsUnhatched: eggsUnhatched
        )
    }
}
