import Foundation

protocol NestRepository: Sendable {
    func fetch(id: UUID) async throws -> NestEntity
    func fetchAll(hatcheryID: UUID) async throws -> [NestEntity]
    func create(_ input: CreateNestInput) async throws -> NestEntity
    func update(id: UUID, _ input: UpdateNestInput) async throws -> NestEntity
    func delete(id: UUID) async throws
    func recordHatchResult(
        nestID: UUID,
        input: RecordHatchResultInput
    ) async throws -> NestEntity
}
