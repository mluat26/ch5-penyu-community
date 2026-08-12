import Foundation

/// Seeds the in-memory database so the existing prototype screens remain
/// populated before a real Supabase schema is connected. It is registered only
/// by the development composition root and can be replaced with a no-op later.
protocol HatcheryDemoDataSeeding: Sendable {
    func seedDashboard(for hatchery: HatcheryEntity) async
}

actor DemoHatcheryDataSeeder: HatcheryDemoDataSeeding {
    private let nestRepository: InMemoryNestRepository
    private let telemetryRepository: InMemoryTelemetryRepository
    private var seededHatcheryIDs = Set<UUID>()

    init(
        nestRepository: InMemoryNestRepository,
        telemetryRepository: InMemoryTelemetryRepository
    ) {
        self.nestRepository = nestRepository
        self.telemetryRepository = telemetryRepository
    }

    func seedDashboard(for hatchery: HatcheryEntity) async {
        guard seededHatcheryIDs.insert(hatchery.id).inserted else { return }

        let rowCount = max(hatchery.numberOfRows, 1)
        let columnCount = max(hatchery.numberOfColumns, 1)
        let now = Date()

        // Preserve the current dashboard's 312-nest / 4,812-egg prototype
        // numbers while keeping them in a repository rather than a View.
        let nests = (0..<312).map { index in
            NestEntity(
                id: UUID(),
                hatcheryID: hatchery.id,
                founderID: nil,
                numberOfEggs: index < 132 ? 16 : 15,
                dateEggsLaid: Calendar.current.date(byAdding: .day, value: -30 - index, to: now),
                datePredictedHatch: Calendar.current.date(byAdding: .day, value: 3 + index, to: now),
                placeEggsLaid: nil,
                successEggsHatch: nil,
                failEggsHatch: nil,
                placementRow: (index / columnCount) % rowCount,
                placementColumn: index % columnCount
            )
        }

        let readings = nests.enumerated().map { index, nest in
            HeatReadingEntity(
                id: UUID(),
                nestID: nest.id,
                sensorID: nil,
                position: nil,
                depthCM: nil,
                temperatureC: 29.0,
                timestamp: now.addingTimeInterval(TimeInterval(-index * 60)),
                alert: nil,
                sensorStatus: .online,
                batteryVoltage: nil,
                signalRSSIDBM: nil
            )
        }

        await nestRepository.seed(nests)
        await telemetryRepository.seed(readings)
    }
}
