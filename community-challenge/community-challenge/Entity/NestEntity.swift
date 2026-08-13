import Foundation

struct NestEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    var hatcheryID: UUID
    var founderID: UUID?
    var numberOfEggs: Int
    var dateEggsLaid: Date?
    var datePredictedHatch: Date?
    var placeEggsLaid: Date?
    var successEggsHatch: Int?
    var failEggsHatch: Int?
    var placementRow: Int?
    var placementColumn: Int?
    /// When the next inspection is expected. Nil once the nest has hatched,
    /// which is the terminal state: nothing further is scheduled.
    var nextInspectionDate: Date?

    /// Eggs neither hatched nor recorded rotten, so still incubating.
    ///
    /// Computed rather than stored: a third number kept in the database could
    /// disagree with the other two, and there is nothing here that can drift.
    var eggsRemaining: Int {
        max(numberOfEggs - (successEggsHatch ?? 0) - (failEggsHatch ?? 0), 0)
    }

    /// True once an inspection reported the nest finished. Deliberately not
    /// "some eggs hatched": a clutch emerges over several days, so a nest can
    /// have hatchlings and still be incubating the rest.
    var isComplete: Bool {
        nextInspectionDate == nil && (successEggsHatch != nil || failEggsHatch != nil)
    }

    /// Some hatchlings are out, but eggs remain and another visit is expected.
    var isPartiallyHatched: Bool {
        (successEggsHatch ?? 0) > 0 && !isComplete
    }

    /// Whether this nest is waiting to be inspected on or before `date`.
    func isDueForInspection(on date: Date = Date()) -> Bool {
        guard let nextInspectionDate else { return false }
        return nextInspectionDate <= date
    }

    var hatchRate: Double? {
        guard let successEggsHatch, numberOfEggs > 0 else { return nil }
        return Double(successEggsHatch) / Double(numberOfEggs)
    }

    var daysUntilHatch: Int? {
        guard let datePredictedHatch else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: datePredictedHatch).day
    }

    var sectionKey: String? {
        guard let placementRow, let placementColumn else { return nil }
        return "\(placementRow)-\(placementColumn)"
    }
}
