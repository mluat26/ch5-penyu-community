import Foundation

protocol IoTDataRepository: Sendable {
    func fetch(id: UUID) async throws -> IoTDataEntity
    func fetchAll(nestID: UUID) async throws -> [IoTDataEntity]
    func fetchReadings(
        nestIDs: [UUID],
        in interval: DateInterval?
    ) async throws -> [IoTDataEntity]
}
