import Foundation

struct NestEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    var hatcheryID: UUID
    var founderID: UUID?
    var numberOfEggs: Int
    var dateEggsLaid: Date?
    var datePredictedHatch: Date?
    /// Written on the bucket in the field, so a nest can be matched to the
    /// physical container without opening it.
    var bucketID: String?
    var nestNumber: String?
    /// Where the eggs were found, which is not where they now sit: nests are
    /// relocated into the hatchery, so this is the origin beach, not the grid
    /// placement.
    var latitude: Double?
    var longitude: Double?
    /// Resolved once at capture time. Reverse geocoding needs the network and
    /// these screens are read on a beach, so the string is stored rather than
    /// looked up again.
    var locationAddress: String?
    var successEggsHatch: Int?
    /// Eggs that spoiled.
    var failEggsHatch: Int?
    /// Eggs that stayed intact but never developed. Distinct from rotten, and
    /// only known once a hatching record exists.
    var eggsUnhatched: Int?
    var placementRow: Int?
    var placementColumn: Int?
    /// When the next inspection is expected. Nil once the nest has hatched,
    /// which is the terminal state: nothing further is scheduled.
    var nextInspectionDate: Date?
    /// When the nest was written down, which is not when the eggs were laid --
    /// `dateEggsLaid` is what the ranger reports, this is what the database
    /// recorded. Nil for nests created before the column existed, so the report
    /// shows nothing rather than claiming they were logged today.
    var createdAt: Date? = nil

    /// Eggs neither hatched nor recorded rotten, so still incubating.
    ///
    /// Computed rather than stored: a third number kept in the database could
    /// disagree with the other two, and there is nothing here that can drift.
    var eggsRemaining: Int {
        max(
            numberOfEggs
                - (successEggsHatch ?? 0)
                - (failEggsHatch ?? 0)
                - (eggsUnhatched ?? 0),
            0
        )
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

    /// Whole days from today to the estimated hatch, counted between calendar
    /// days rather than instants.
    ///
    /// Measuring from `Date()` truncated the part-day since midnight, so this
    /// read one lower than the same count on the add-nest preview for most of
    /// the day. Both now start from `startOfDay`.
    var daysUntilHatch: Int? {
        guard let datePredictedHatch else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: datePredictedHatch)
        ).day
    }

    var sectionKey: String? {
        guard let placementRow, let placementColumn else { return nil }
        return "\(placementRow)-\(placementColumn)"
    }

    /// The number written on the nest in the field.
    ///
    /// Every screen must agree on this. Position in a list is not an identity:
    /// numbering by row index renamed the same nest depending on which screen
    /// opened it, and reordering the list silently renumbered all of them.
    /// `fallbackOrdinal` covers nests recorded before the number was stored.
    func displayNumber(fallbackOrdinal: Int) -> String {
        let trimmed = nestNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return String(format: "%03d", fallbackOrdinal)
    }
}
