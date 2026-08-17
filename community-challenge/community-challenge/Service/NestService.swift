import Foundation

struct CreateNestInput: Hashable, Sendable {
    var hatcheryID: UUID
    var founderID: UUID?
    var numberOfEggs: Int
    var dateEggsLaid: Date?
    var datePredictedHatch: Date?
    var bucketID: String? = nil
    var nestNumber: String? = nil
    /// Where the eggs were found. Optional: a ranger without a signal must
    /// still be able to register the nest.
    var latitude: Double? = nil
    var longitude: Double? = nil
    var locationAddress: String? = nil
    var placementRow: Int?
    var placementColumn: Int?
    /// When the first inspection is expected. Without it the nest is never
    /// queued, so nothing ever prompts anyone to go and look at it.
    var nextInspectionDate: Date?
}

struct UpdateNestInput: Hashable, Sendable {
    var numberOfEggs: Int
    var dateEggsLaid: Date?
    var datePredictedHatch: Date?
    var bucketID: String? = nil
    var nestNumber: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var locationAddress: String? = nil
    /// When the next visit is due. Editable from the nest detail screen; nil
    /// once a nest has hatched, since nothing further is scheduled.
    var nextInspectionDate: Date? = nil
    var placementRow: Int?
    var placementColumn: Int?
}

struct NestService: Sendable {
    private let repository: any NestRepository

    init(repository: any NestRepository) {
        self.repository = repository
    }

    func createNest(_ input: CreateNestInput) async throws -> NestEntity {
        guard input.numberOfEggs > 0 else {
            throw DomainValidationError.invalidEggCount
        }
        return try await repository.create(input)
    }

    func nest(id: UUID) async throws -> NestEntity {
        try await repository.fetch(id: id)
    }

    func nests(hatcheryID: UUID) async throws -> [NestEntity] {
        try await repository.fetchAll(hatcheryID: hatcheryID)
    }

    /// Nests whose inspection date has arrived, soonest first. Filters the
    /// hatchery's nests rather than issuing its own query: the dashboard
    /// already loads all of them, and a hatchery holds hundreds, not millions.
    // ponytail: client-side filter, add a repository query if a hatchery ever
    // grows past what the dashboard can load in one go.
    func nestsDueForInspection(
        hatcheryID: UUID,
        on date: Date = Date()
    ) async throws -> [NestEntity] {
        try await repository.fetchAll(hatcheryID: hatcheryID)
            .filter { $0.isDueForInspection(on: date) }
            .sorted {
                ($0.nextInspectionDate ?? .distantFuture)
                    < ($1.nextInspectionDate ?? .distantFuture)
            }
    }

    func updateNest(id: UUID, _ input: UpdateNestInput) async throws -> NestEntity {
        guard input.numberOfEggs > 0 else {
            throw DomainValidationError.invalidEggCount
        }
        return try await repository.update(id: id, input)
    }

    func deleteNest(id: UUID) async throws {
        try await repository.delete(id: id)
    }
}
