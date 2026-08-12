import Foundation

protocol NestRepository: Sendable {
    func fetchAll(hatcheryID: UUID) async throws -> [NestEntity]
    func create(_ input: CreateNestInput) async throws -> NestEntity
    func recordHatchResult(
        nestID: UUID,
        input: RecordHatchResultInput
    ) async throws -> NestEntity
}
