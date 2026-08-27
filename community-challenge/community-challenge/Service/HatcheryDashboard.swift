import Foundation

struct HatcheryOverview: Hashable, Sendable {
    var averageTemperatureC: Double?
    var nestCount: Int
    var totalEggs: Int
}

struct NestDashboardItem: Identifiable, Hashable, Sendable {
    let nest: NestEntity
    let latestTemperatureC: Double?
    /// Reported by the nest's logger, not the phone. Absent until a reading
    /// carrying a battery voltage arrives, which is what the design's "--"
    /// state represents.
    let latestBatteryVoltage: Double?

    var id: UUID { nest.id }

    /// Voltage mapped onto the 0–1 range the battery pill draws.
    ///
    /// ponytail: a straight 3.0–4.2V line, which is the usable span of a
    /// single Li-ion cell. Real packs sag under load and flatten at the top of
    /// the curve, so this reads optimistically mid-discharge — swap in a
    /// per-logger curve once there is field data to fit one against.
    var batteryLevel: Double? {
        guard let latestBatteryVoltage else { return nil }
        return min(max((latestBatteryVoltage - 3.0) / 1.2, 0), 1)
    }

    /// What the dashboard warns about for this nest, or nil when it is fine.
    enum TemperatureAlert: Hashable, Sendable {
        /// The logger has never reported, or is not installed.
        case noData
        /// It reported, and the reading is outside the incubation range.
        case outOfRange
    }

    /// Nil when the nest is fine. `noData` outranks nothing -- a silent logger
    /// and a bad reading are different problems with different fixes, so they
    /// are reported separately rather than collapsed into one warning. The
    /// critical judgement comes from `NestTemperature`, the same source used
    /// by every temperature pill and chart; a second range here previously
    /// disagreed at 32–33 °C.
    var temperatureAlert: TemperatureAlert? {
        // A final hatching tally closes the incubation period. The logger may
        // keep reporting (or its last reading may remain attached), but neither
        // missing nor out-of-range data needs action once the nest has hatched.
        guard !nest.hasHatched else { return nil }
        guard let latestTemperatureC else { return .noData }
        return NestTemperature.isCritical(temperatureC: latestTemperatureC)
            ? .outOfRange
            : nil
    }
}

struct HatcherySectionDashboard: Identifiable, Hashable, Sendable {
    let id: String
    let row: Int
    let column: Int
    var averageTemperatureC: Double?
    var nestCount: Int
    var totalEggs: Int
    var nextHatchDate: Date?
    var nests: [NestDashboardItem]

    /// What is still in the sand. A hatched nest has been dug out and tallied,
    /// so counting it on the grid overlay reports occupancy that is not there
    /// -- the overlay is read to decide where a nest can go.
    ///
    /// Kept beside `nestCount` rather than replacing it: the section sheet and
    /// the picker still report everything the section has held.
    var activeNestCount: Int {
        nests.filter { !$0.nest.hasHatched }.count
    }
}

struct HatcheryDashboard: Identifiable, Hashable, Sendable {
    let hatchery: HatcheryEntity
    let overview: HatcheryOverview
    let sections: [HatcherySectionDashboard]

    var id: UUID { hatchery.id }

    func section(row: Int, column: Int) -> HatcherySectionDashboard? {
        sections.first { $0.row == row && $0.column == column }
    }

    /// Every nest in the hatchery, whatever section it sits in.
    var allNests: [NestDashboardItem] { sections.flatMap(\.nests) }

    /// One nest with its latest reading attached, wherever it sits on the grid.
    /// The registration screen knows the nest it just saved but not the
    /// section it landed in, so it looks the nest up rather than the cell.
    func nest(id: UUID) -> NestDashboardItem? {
        allNests.first { $0.id == id }
    }
}
