import Foundation

actor InMemoryNestRepository: NestRepository {
    private var nests: [UUID: NestEntity]

    init(seed: [NestEntity] = []) {
        nests = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func fetch(id: UUID) async throws -> NestEntity {
        guard let nest = nests[id] else {
            throw RepositoryError.notFound(resource: "Nest", id: id)
        }
        return nest
    }

    func fetchAll(hatcheryID: UUID) async throws -> [NestEntity] {
        nests.values
            .filter { $0.hatcheryID == hatcheryID }
            .sorted { $0.dateEggsLaid ?? .distantPast > $1.dateEggsLaid ?? .distantPast }
    }

    func create(_ input: CreateNestInput) async throws -> NestEntity {
        let nest = NestEntity(
            id: UUID(),
            hatcheryID: input.hatcheryID,
            founderID: input.founderID,
            numberOfEggs: input.numberOfEggs,
            dateEggsLaid: input.dateEggsLaid,
            datePredictedHatch: input.datePredictedHatch,
            placeEggsLaid: input.placeEggsLaid,
            successEggsHatch: nil,
            failEggsHatch: nil,
            placementRow: input.placementRow,
            placementColumn: input.placementColumn,
            nextInspectionDate: input.nextInspectionDate
        )
        nests[nest.id] = nest
        return nest
    }

    func update(id: UUID, _ input: UpdateNestInput) async throws -> NestEntity {
        guard var nest = nests[id] else {
            throw RepositoryError.notFound(resource: "Nest", id: id)
        }

        nest.numberOfEggs = input.numberOfEggs
        nest.dateEggsLaid = input.dateEggsLaid
        nest.datePredictedHatch = input.datePredictedHatch
        nest.placeEggsLaid = input.placeEggsLaid
        nest.placementRow = input.placementRow
        nest.placementColumn = input.placementColumn
        nests[id] = nest
        return nest
    }

    func delete(id: UUID) async throws {
        guard nests.removeValue(forKey: id) != nil else {
            throw RepositoryError.notFound(resource: "Nest", id: id)
        }
    }

    func seed(_ newNests: [NestEntity]) async {
        for nest in newNests {
            nests[nest.id] = nest
        }
    }

    /// Local stand-in for the `apply_inspection_to_nest` trigger, so in-memory
    /// tests observe the same summary the database produces. Totals are the sum
    /// across visits, since each inspection records only what it found.
    func applyInspectionTotals(
        nestID: UUID,
        eggsHatched: Int?,
        eggsRotten: Int?,
        nextInspectionDate: Date?
    ) {
        guard var nest = nests[nestID] else { return }

        nest.successEggsHatch = eggsHatched
        nest.failEggsHatch = eggsRotten
        nest.nextInspectionDate = nextInspectionDate
        nests[nestID] = nest
    }
}
