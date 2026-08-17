import Foundation

actor InMemoryIoTDataRepository: IoTDataRepository {
    private var readings: [UUID: IoTDataEntity]

    init(seed: [IoTDataEntity] = []) {
        readings = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func fetch(id: UUID) async throws -> IoTDataEntity {
        guard let reading = readings[id] else {
            throw RepositoryError.notFound(resource: "IoTData", id: id)
        }
        return reading
    }

    func fetchAll(nestID: UUID) async throws -> [IoTDataEntity] {
        return readings.values
            .filter { $0.nestID == nestID }
            .sorted { $0.timestamp > $1.timestamp }
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
