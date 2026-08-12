import Foundation

protocol TelemetryRepository: Sendable {
    func fetchReadings(
        nestIDs: [UUID],
        in interval: DateInterval?
    ) async throws -> [HeatReadingEntity]
}
