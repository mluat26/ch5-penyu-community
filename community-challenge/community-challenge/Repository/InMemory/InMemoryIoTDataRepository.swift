import Foundation

actor InMemoryIoTDataRepository: IoTDataRepository {
    private var readings: [UUID: IoTDataEntity]

    init(seed: [IoTDataEntity] = []) {
        readings = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func fetchReadings(
        nestIDs: [UUID],
        in interval: DateInterval?
    ) async throws -> [IoTDataEntity] {
        let requestedNestIDs = Set(nestIDs)
        return readings.values
            .filter { reading in
                requestedNestIDs.contains(reading.nestID)
                    && (interval?.contains(reading.timestamp) ?? true)
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func seed(_ newReadings: [IoTDataEntity]) async {
        for reading in newReadings {
            readings[reading.id] = reading
        }
    }
}
