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
            bucketID: input.bucketID,
            nestNumber: input.nestNumber,
            latitude: input.latitude,
            longitude: input.longitude,
            locationAddress: input.locationAddress,
            successEggsHatch: nil,
            failEggsHatch: nil,
            eggsUnhatched: nil,
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
        nest.bucketID = input.bucketID
        nest.nestNumber = input.nestNumber
        nest.latitude = input.latitude
        nest.longitude = input.longitude
        nest.locationAddress = input.locationAddress
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

    /// Mirrors the hatching branch of `refresh_nest_summary`: a final tally
    /// overwrites the summary outright and ends the inspection schedule.
    func applyHatching(
        nestID: UUID,
        eggsHatched: Int,
        eggsRotten: Int,
        eggsUnhatched: Int
    ) {
        guard var nest = nests[nestID] else { return }

        nest.successEggsHatch = eggsHatched
        nest.failEggsHatch = eggsRotten
        nest.eggsUnhatched = eggsUnhatched
        nest.nextInspectionDate = nil
        nests[nestID] = nest
    }
}
