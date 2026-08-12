import Foundation

struct NestService: Sendable {
    private let repository: any NestRepository

    init(repository: any NestRepository) {
        self.repository = repository
    }

    func createNest(_ input: CreateNestInput) async throws -> Nest {
        guard input.numberOfEggs > 0 else {
            throw DomainValidationError.invalidEggCount
        }
        return try await repository.create(input)
    }

    func recordHatchResult(
        nestID: UUID,
        input: RecordHatchResultInput
    ) async throws -> Nest {
        try await repository.recordHatchResult(nestID: nestID, input: input)
    }
}
