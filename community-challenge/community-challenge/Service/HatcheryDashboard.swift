import Foundation

struct HatcheryOverview: Hashable, Sendable {
    var averageTemperatureC: Double?
    var nestCount: Int
    var totalEggs: Int
}

struct NestDashboardItem: Identifiable, Hashable, Sendable {
    let nest: NestEntity
    let latestTemperatureC: Double?

    var id: UUID { nest.id }
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
