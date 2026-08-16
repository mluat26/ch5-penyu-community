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
}

struct HatcheryDashboard: Identifiable, Hashable, Sendable {
    let hatchery: HatcheryEntity
    let overview: HatcheryOverview
    let sections: [HatcherySectionDashboard]

    var id: UUID { hatchery.id }

    func section(row: Int, column: Int) -> HatcherySectionDashboard? {
        sections.first { $0.row == row && $0.column == column }
    }
}
