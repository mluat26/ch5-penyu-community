import Foundation

struct CreateNestInput: Hashable, Sendable {
    var hatcheryID: UUID
    var founderID: UUID?
    var numberOfEggs: Int
    var dateEggsLaid: Date?
    var datePredictedHatch: Date?
    var placeEggsLaid: Date?
    var placementRow: Int?
    var placementColumn: Int?
}

struct RecordHatchResultInput: Hashable, Sendable {
    var successEggsHatch: Int
    var failEggsHatch: Int
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

    func recordHatchResult(
        nestID: UUID,
        input: RecordHatchResultInput
    ) async throws -> NestEntity {
        try await repository.recordHatchResult(nestID: nestID, input: input)
    }
}
