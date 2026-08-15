import Foundation

/// A nest has at most one hatching record — the final tally — so `fetch` is by
/// nest rather than by id, and there is no `fetchAll(nestID:)`.
protocol HatchingRepository: Sendable {
    func fetch(nestID: UUID) async throws -> HatchingEntity?
    func create(_ input: RecordHatchingInput) async throws -> HatchingEntity
    func update(id: UUID, _ input: CorrectHatchingInput) async throws -> HatchingEntity
}
