import Foundation

actor InMemoryTelemetryRepository: TelemetryRepository {
    private var readings: [UUID: HeatReading]

    init(seed: [HeatReading] = []) {
        readings = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func fetchReadings(
        nestIDs: [UUID],
        in interval: DateInterval?
    ) async throws -> [HeatReading] {
        let requestedNestIDs = Set(nestIDs)
        return readings.values
            .filter { reading in
                requestedNestIDs.contains(reading.nestID)
                    && (interval?.contains(reading.timestamp) ?? true)
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func seed(_ newReadings: [HeatReading]) async {
        for reading in newReadings {
            readings[reading.id] = reading
        }
    }
}
