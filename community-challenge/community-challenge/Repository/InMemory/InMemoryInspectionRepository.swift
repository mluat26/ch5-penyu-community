import Foundation

actor InMemoryInspectionRepository: InspectionRepository {
    private var inspections: [UUID: InspectionEntity]
    /// Mirrors the database trigger: recording or correcting an inspection
    /// re-totals the nest and moves its schedule. Optional so tests can
    /// exercise inspections on their own.
    private let nestRepository: InMemoryNestRepository?

    init(
        seed: [InspectionEntity] = [],
        nestRepository: InMemoryNestRepository? = nil
    ) {
        inspections = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
        self.nestRepository = nestRepository
    }

    func fetchAll(nestID: UUID) async throws -> [InspectionEntity] {
        inspections.values
            .filter { $0.nestID == nestID }
            .sorted { $0.inspectedOn > $1.inspectedOn }
    }

    func create(_ input: RecordInspectionInput) async throws -> InspectionEntity {
        let inspection = InspectionEntity(
            id: UUID(),
            nestID: input.nestID,
            inspectedOn: input.inspectedOn,
            outcome: input.outcome,
            eggsHatched: input.eggsHatched,
            eggsRotten: input.eggsRotten,
            nextInspectionDate: input.nextInspectionDate
        )
        inspections[inspection.id] = inspection
        await applyToNest(nestID: inspection.nestID)
        return inspection
    }

    func update(id: UUID, _ input: CorrectInspectionInput) async throws -> InspectionEntity {
        guard var inspection = inspections[id] else {
            throw RepositoryError.notFound(resource: "Inspection", id: id)
        }

        inspection.outcome = input.outcome
        inspection.eggsHatched = input.eggsHatched
        inspection.eggsRotten = input.eggsRotten
        inspection.nextInspectionDate = input.nextInspectionDate
        inspections[id] = inspection

        await applyToNest(nestID: inspection.nestID)
        return inspection
    }

    /// Recomputes from every visit rather than patching, matching the trigger,
    /// so a correction cannot leave a stale total behind.
    private func applyToNest(nestID: UUID) async {
        let forNest = inspections.values.filter { $0.nestID == nestID }
        let latest = forNest.max { $0.inspectedOn < $1.inspectedOn }

        await nestRepository?.applyInspectionTotals(
            nestID: nestID,
            eggsHatched: sum(forNest.map(\.eggsHatched)),
            eggsRotten: sum(forNest.map(\.eggsRotten)),
            nextInspectionDate: latest?.nextInspectionDate
        )
    }

    /// Postgres `sum()` returns NULL when every input is NULL, rather than 0.
    /// The in-memory mirror has to agree, or tests would see a total the real
    /// database never produces.
    private func sum(_ values: [Int?]) -> Int? {
        let present = values.compactMap { $0 }
        return present.isEmpty ? nil : present.reduce(0, +)
    }
}
