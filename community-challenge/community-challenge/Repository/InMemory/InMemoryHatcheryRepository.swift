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

    func fetchAll() async throws -> [HatcheryEntity] {
        hatcheries.values.sorted { $0.name < $1.name }
    }

    func create(_ input: CreateHatcheryInput) async throws -> HatcheryEntity {
        let name = HatcheryName.trimmed(input.name)
        guard !name.isEmpty else {
            throw DomainValidationError.emptyName
        }
        guard !hasDuplicateName(name, excluding: nil) else {
            throw DomainValidationError.duplicateHatcheryName
        }

        let hatchery = HatcheryEntity(
            id: UUID(),
            name: name,
            shape: input.shape,
            numberOfRows: input.numberOfRows,
            numberOfColumns: input.numberOfColumns,
            lengthM: input.lengthM,
            widthM: input.widthM,
            organizationID: input.organizationID,
            createdAt: Date()
        )
        hatcheries[hatchery.id] = hatchery
        return hatchery
    }

    func update(id: UUID, _ input: UpdateHatcheryInput) async throws -> HatcheryEntity {
        guard var hatchery = hatcheries[id] else {
            throw RepositoryError.notFound(resource: "Hatchery", id: id)
        }

        let name = HatcheryName.trimmed(input.name)
        guard !name.isEmpty else {
            throw DomainValidationError.emptyName
        }
        guard !hasDuplicateName(name, excluding: id) else {
            throw DomainValidationError.duplicateHatcheryName
        }

        hatchery.name = name
        hatchery.numberOfRows = input.numberOfRows
        hatchery.numberOfColumns = input.numberOfColumns
        hatchery.lengthM = input.lengthM
        hatchery.widthM = input.widthM
        hatcheries[id] = hatchery
        return hatchery
    }

    func delete(id: UUID) async throws {
        guard hatcheries.removeValue(forKey: id) != nil else {
            throw RepositoryError.notFound(resource: "Hatchery", id: id)
        }
    }

    private func hasDuplicateName(_ name: String, excluding id: UUID?) -> Bool {
        let normalizedName = HatcheryName.normalized(name)
        return hatcheries.values.contains {
            $0.id != id && HatcheryName.normalized($0.name) == normalizedName
        }
    }
}
