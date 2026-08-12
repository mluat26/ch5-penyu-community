import Foundation

/// Temporary local implementation. The future Supabase implementation will
/// conform to the same Domain protocol and be selected in `AppContainer`.
actor InMemoryHatcheryRepository: HatcheryRepository {
    private var hatcheries: [UUID: HatcheryEntity]

    init(seed: [HatcheryEntity] = []) {
        hatcheries = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func fetch(id: UUID) async throws -> HatcheryEntity {
        guard let hatchery = hatcheries[id] else {
            throw RepositoryError.notFound(resource: "Hatchery", id: id)
        }
        return hatchery
    }

    func create(_ input: CreateHatcheryInput) async throws -> HatcheryEntity {
        let hatchery = HatcheryEntity(
            id: UUID(),
            name: input.name,
            shape: input.shape,
            numberOfRows: input.numberOfRows,
            numberOfColumns: input.numberOfColumns,
            lengthM: input.lengthM,
            widthM: input.widthM,
            organizationID: input.organizationID
        )
        hatcheries[hatchery.id] = hatchery
        return hatchery
    }
}
