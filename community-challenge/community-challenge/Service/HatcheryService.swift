import Foundation

struct CreateHatcheryInput: Hashable, Sendable {
    var name: String
    var shape: HatcheryShape
    var numberOfRows: Int
    var numberOfColumns: Int
    var lengthM: Double
    var widthM: Double
    var organizationID: UUID?
}

struct HatcheryService: Sendable {
    private let hatcheryRepository: any HatcheryRepository
    private let nestRepository: any NestRepository
    private let telemetryRepository: any TelemetryRepository

    init(
        hatcheryRepository: any HatcheryRepository,
        nestRepository: any NestRepository,
        telemetryRepository: any TelemetryRepository
    ) {
        self.hatcheryRepository = hatcheryRepository
        self.nestRepository = nestRepository
        self.telemetryRepository = telemetryRepository
    }

    func createHatchery(_ input: CreateHatcheryInput) async throws -> HatcheryEntity {
        guard !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.emptyName
        }
        guard
            input.numberOfRows > 0,
            input.numberOfColumns > 0,
            input.lengthM > 0,
            input.widthM > 0
        else {
            throw DomainValidationError.invalidDimensions
        }

        return try await hatcheryRepository.create(input)
    }

    func loadDashboard(hatcheryID: UUID) async throws -> HatcheryDashboard {
        async let hatchery = hatcheryRepository.fetch(id: hatcheryID)
        async let nests = nestRepository.fetchAll(hatcheryID: hatcheryID)

        let (loadedHatchery, loadedNests) = try await (hatchery, nests)
        let readings = try await telemetryRepository.fetchReadings(
            nestIDs: loadedNests.map(\.id),
            in: nil
        )
        let latestReadingByNestID = Dictionary(
            uniqueKeysWithValues: Dictionary(
                grouping: readings,
                by: \.nestID
            ).compactMap { nestID, nestReadings in
                nestReadings.max { $0.timestamp < $1.timestamp }
                    .map { (nestID, $0) }
            }
        )

        let sections = makeSections(
            hatchery: loadedHatchery,
            nests: loadedNests,
            latestReadingByNestID: latestReadingByNestID
        )
        let latestReadings = Array(latestReadingByNestID.values)

        return HatcheryDashboard(
            hatchery: loadedHatchery,
            overview: HatcheryOverview(
                averageTemperatureC: averageTemperature(in: latestReadings),
                nestCount: loadedNests.count,
                totalEggs: loadedNests.reduce(0) { $0 + $1.numberOfEggs }
            ),
            sections: sections
        )
    }

    private func makeSections(
        hatchery: HatcheryEntity,
        nests: [NestEntity],
        latestReadingByNestID: [UUID: HeatReadingEntity]
    ) -> [HatcherySectionDashboard] {
        (0..<max(hatchery.numberOfRows, 0)).flatMap { row in
            (0..<max(hatchery.numberOfColumns, 0)).map { column in
                let sectionNests = nests.filter {
                    $0.placementRow == row && $0.placementColumn == column
                }
                let items = sectionNests.map { nest in
                    NestDashboardItem(
                        nest: nest,
                        latestTemperatureC: latestReadingByNestID[nest.id]?.temperatureC
                    )
                }

                return HatcherySectionDashboard(
                    id: HatcherySectionIdentifier.make(row: row, column: column),
                    row: row,
                    column: column,
                    averageTemperatureC: averageTemperature(
                        in: sectionNests.compactMap { latestReadingByNestID[$0.id] }
                    ),
                    nestCount: sectionNests.count,
                    totalEggs: sectionNests.reduce(0) { $0 + $1.numberOfEggs },
                    nextHatchDate: sectionNests.compactMap(\.datePredictedHatch).min(),
                    nests: items
                )
            }
        }
    }

    private func averageTemperature(in readings: [HeatReadingEntity]) -> Double? {
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0) { $0 + $1.temperatureC } / Double(readings.count)
    }
}

enum HatcherySectionIdentifier {
    static func make(row: Int, column: Int) -> String {
        "\(columnLabel(column))\(row + 1)"
    }

    private static func columnLabel(_ zeroBasedIndex: Int) -> String {
        var value = zeroBasedIndex + 1
        var label = ""
        while value > 0 {
            value -= 1
            label = String(UnicodeScalar(65 + value % 26)!) + label
            value /= 26
        }
        return label
    }
}
