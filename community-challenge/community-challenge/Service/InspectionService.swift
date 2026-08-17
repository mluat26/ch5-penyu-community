import Foundation

struct RecordInspectionInput: Hashable, Sendable {
    var nestID: UUID
    var inspectedOn: Date
    var outcome: InspectionOutcome
    /// What this visit found, not a running total.
    var eggsHatched: Int?
    var eggsRotten: Int?
    var nextInspectionDate: Date?
}

/// Correction to a visit already recorded. The nest and the date it happened
/// are fixed: fixing a miscount is an edit, moving the visit is not.
struct CorrectInspectionInput: Hashable, Sendable {
    var outcome: InspectionOutcome
    var eggsHatched: Int?
    var eggsRotten: Int?
    var nextInspectionDate: Date?
}

struct InspectionService: Sendable {
    private let repository: any InspectionRepository

    init(repository: any InspectionRepository) {
        self.repository = repository
    }

    func inspections(nestID: UUID) async throws -> [InspectionEntity] {
        try await repository.fetchAll(nestID: nestID)
    }

    func recordInspection(_ input: RecordInspectionInput) async throws -> InspectionEntity {
        try validate(
            outcome: input.outcome,
            eggsHatched: input.eggsHatched,
            eggsRotten: input.eggsRotten,
            nextInspectionDate: input.nextInspectionDate
        )
        return try await repository.create(input)
    }

    func correctInspection(
        id: UUID,
        _ input: CorrectInspectionInput
    ) async throws -> InspectionEntity {
        try validate(
            outcome: input.outcome,
            eggsHatched: input.eggsHatched,
            eggsRotten: input.eggsRotten,
            nextInspectionDate: input.nextInspectionDate
        )
        return try await repository.update(id: id, input)
    }

    /// The same rules `inspection`'s check constraints enforce, applied here so
    /// callers get a `DomainValidationError` they can show rather than a raw
    /// Postgres constraint message.
    private func validate(
        outcome: InspectionOutcome,
        eggsHatched: Int?,
        eggsRotten: Int?,
        nextInspectionDate: Date?
    ) throws {
        if outcome.endsSchedule {
            guard nextInspectionDate == nil else {
                throw DomainValidationError.completeNestNeedsNoNextDate
            }
        } else {
            guard nextInspectionDate != nil else {
                throw DomainValidationError.unfinishedInspectionNeedsNextDate
            }
        }

        if outcome != .notHatched {
            guard eggsHatched != nil, eggsRotten != nil else {
                throw DomainValidationError.hatchResultMissingCounts
            }
        }

        if outcome == .partiallyHatched {
            guard (eggsHatched ?? 0) > 0 else {
                throw DomainValidationError.partialHatchNeedsHatchlings
            }
        }

        guard (eggsHatched ?? 0) >= 0, (eggsRotten ?? 0) >= 0 else {
            throw DomainValidationError.invalidEggCount
        }
    }
}
