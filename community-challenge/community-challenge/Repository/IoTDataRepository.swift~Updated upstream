import Foundation

protocol IoTDataRepository: Sendable {
    func fetchReadings(
        nestIDs: [UUID],
        in interval: DateInterval?
    ) async throws -> [IoTDataEntity]
}
