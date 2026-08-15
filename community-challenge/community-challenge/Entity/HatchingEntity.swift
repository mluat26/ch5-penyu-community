import Foundation

/// The final accounting for a nest that has hatched.
///
/// Splits the clutch three ways. Rotten eggs spoiled; unhatched ones stayed
/// intact but never developed — different outcomes, tracked separately.
///
/// One per nest: this is a terminal tally, not a per-visit observation. Partial
/// emergence is recorded as inspections instead.
struct HatchingEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    var nestID: UUID
    /// When the eggs actually hatched, which may predate writing it down.
    var hatchedOn: Date
    var eggsHatched: Int
    var eggsRotten: Int
    var eggsUnhatched: Int

    var totalAccountedFor: Int {
        eggsHatched + eggsRotten + eggsUnhatched
    }

    /// Share of the clutch that hatched, given the nest's original egg count.
    func hatchRate(clutchSize: Int) -> Double? {
        guard clutchSize > 0 else { return nil }
        return Double(eggsHatched) / Double(clutchSize)
    }
}
