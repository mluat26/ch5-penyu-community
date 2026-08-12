import Foundation

actor InMemoryNestRepository: NestRepository {
    private var nests: [UUID: NestEntity]

    init(seed: [NestEntity] = []) {
        nests = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
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
            placementColumn: input.placementColumn
        )
        nests[nest.id] = nest
        return nest
    }

    func recordHatchResult(
        nestID: UUID,
        input: RecordHatchResultInput
    ) async throws -> NestEntity {
        guard var nest = nests[nestID] else {
            throw RepositoryError.notFound(resource: "Nest", id: nestID)
        }

        nest.successEggsHatch = input.successEggsHatch
        nest.failEggsHatch = input.failEggsHatch
        nests[nestID] = nest
        return nest
    }

    func seed(_ newNests: [NestEntity]) async {
        for nest in newNests {
            nests[nest.id] = nest
        }
    }
}
