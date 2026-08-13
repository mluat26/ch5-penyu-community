import Foundation

/// Inspections are an append-only record of visits that happened, so there is
/// deliberately no delete: withdrawing a visit rewrites history. `update`
/// exists only to correct what a visit found — a miscount fixed on the day —
/// not to move it to another nest or another date.
protocol InspectionRepository: Sendable {
    func fetchAll(nestID: UUID) async throws -> [InspectionEntity]
    func create(_ input: RecordInspectionInput) async throws -> InspectionEntity
    func update(id: UUID, _ input: CorrectInspectionInput) async throws -> InspectionEntity
}
