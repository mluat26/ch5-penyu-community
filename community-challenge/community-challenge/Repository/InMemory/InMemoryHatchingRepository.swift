import Foundation

actor InMemoryHatchingRepository: HatchingRepository {
    private var hatchings: [UUID: HatchingEntity]
    /// Mirrors `refresh_nest_summary`: a hatching record is the final tally, so
    /// it overwrites the nest summary and clears the inspection schedule.
    private let nestRepository: InMemoryNestRepository?

    init(
        seed: [HatchingEntity] = [],
        nestRepository: InMemoryNestRepository? = nil
    ) {
        hatchings = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
        self.nestRepository = nestRepository
    }

    func fetch(nestID: UUID) async throws -> HatchingEntity? {
        hatchings.values.first { $0.nestID == nestID }
    }

    func create(_ input: RecordHatchingInput) async throws -> HatchingEntity {
        // Mirrors the unique constraint on hatching.nest_id.
        guard hatchings.values.allSatisfy({ $0.nestID != input.nestID }) else {
            throw DomainValidationError.nestAlreadyHatched(nestID: input.nestID)
        }

        let hatching = HatchingEntity(
            id: UUID(),
            nestID: input.nestID,
            hatchedOn: input.hatchedOn,
            eggsHatched: input.eggsHatched,
            eggsRotten: input.eggsRotten,
            eggsUnhatched: input.eggsUnhatched
        )
        hatchings[hatching.id] = hatching
        await applyToNest(hatching)
        return hatching
    }

    func update(id: UUID, _ input: CorrectHatchingInput) async throws -> HatchingEntity {
        guard var hatching = hatchings[id] else {
            throw RepositoryError.notFound(resource: "Hatching", id: id)
        }

        hatching.hatchedOn = input.hatchedOn
        hatching.eggsHatched = input.eggsHatched
        hatching.eggsRotten = input.eggsRotten
        hatching.eggsUnhatched = input.eggsUnhatched
        hatchings[id] = hatching

        await applyToNest(hatching)
        return hatching
    }

    private func applyToNest(_ hatching: HatchingEntity) async {
        await nestRepository?.applyHatching(
            nestID: hatching.nestID,
            eggsHatched: hatching.eggsHatched,
            eggsRotten: hatching.eggsRotten,
            eggsUnhatched: hatching.eggsUnhatched
        )
    }
}
