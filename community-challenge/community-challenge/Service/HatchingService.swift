import Foundation

struct RecordHatchingInput: Hashable, Sendable {
    var nestID: UUID
    var hatchedOn: Date
    var eggsHatched: Int
    var eggsRotten: Int
    var eggsUnhatched: Int
}

struct CorrectHatchingInput: Hashable, Sendable {
    var hatchedOn: Date
    var eggsHatched: Int
    var eggsRotten: Int
    var eggsUnhatched: Int
}

struct HatchingService: Sendable {
    private let repository: any HatchingRepository
    private let nestRepository: any NestRepository

    init(repository: any HatchingRepository, nestRepository: any NestRepository) {
        self.repository = repository
        self.nestRepository = nestRepository
    }

    func hatching(nestID: UUID) async throws -> HatchingEntity? {
        try await repository.fetch(nestID: nestID)
    }

    /// The count the Hatchling details screen pre-fills, so the inspector
    /// confirms a number rather than doing arithmetic in the field. It stays
    /// editable: eggs can go unaccounted for, and the total is what was
    /// actually seen, not what the subtraction implies.
    func suggestedHatchedCount(
        clutchSize: Int,
        eggsRotten: Int,
        eggsUnhatched: Int
    ) -> Int {
        max(clutchSize - eggsRotten - eggsUnhatched, 0)
    }

    func recordHatching(_ input: RecordHatchingInput) async throws -> HatchingEntity {
        try await validate(
            nestID: input.nestID,
            eggsHatched: input.eggsHatched,
            eggsRotten: input.eggsRotten,
            eggsUnhatched: input.eggsUnhatched
        )
        return try await repository.create(input)
    }

    func correctHatching(
        id: UUID,
        nestID: UUID,
        _ input: CorrectHatchingInput
    ) async throws -> HatchingEntity {
        try await validate(
            nestID: nestID,
            eggsHatched: input.eggsHatched,
            eggsRotten: input.eggsRotten,
            eggsUnhatched: input.eggsUnhatched
        )
        return try await repository.update(id: id, input)
    }

    /// Mirrors the `hatching_within_clutch` trigger, so a miscount surfaces as
    /// a readable message instead of a raw Postgres exception.
    private func validate(
        nestID: UUID,
        eggsHatched: Int,
        eggsRotten: Int,
        eggsUnhatched: Int
    ) async throws {
        guard eggsHatched >= 0, eggsRotten >= 0, eggsUnhatched >= 0 else {
            throw DomainValidationError.invalidEggCount
        }

        let nest = try await nestRepository.fetch(id: nestID)
        let counted = eggsHatched + eggsRotten + eggsUnhatched

        guard counted <= nest.numberOfEggs else {
            throw DomainValidationError.hatchingExceedsClutch(
                counted: counted,
                clutchSize: nest.numberOfEggs
            )
        }
    }
}
