import Foundation

/// What a visit found. A clutch emerges over days rather than all at once, so
/// `partiallyHatched` is a real state: some hatchlings are out while eggs are
/// still incubating. Only `complete` ends the inspection schedule.
enum InspectionOutcome: String, CaseIterable, Sendable {
    case notHatched = "not_hatched"
    case partiallyHatched = "partially_hatched"
    case complete

    /// Whether this outcome finishes the nest, so no further visit is expected.
    var endsSchedule: Bool { self == .complete }
}

/// One completed inspection of a nest.
///
/// Rows are an append-only record of visits that happened. A visit that is still
/// expected lives on `NestEntity.nextInspectionDate` instead, so an inspection
/// never exists in a half-filled state.
///
/// Counts are what *this* visit found, not running totals — a field worker
/// counts what is in front of them. The nest's totals are the sum across visits.
struct InspectionEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    var nestID: UUID
    var inspectedOn: Date
    var outcome: InspectionOutcome
    var eggsHatched: Int?
    var eggsRotten: Int?
    /// Nil exactly when `outcome` is `.complete`.
    var nextInspectionDate: Date?
}
