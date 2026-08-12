import Foundation

struct HeatReading: Identifiable, Hashable, Sendable {
    let id: UUID
    var nestID: UUID
    var sensorID: UUID?
    var position: String?
    var depthCM: Double?
    var temperatureC: Double
    var timestamp: Date
    var alert: AlertLevel?
    var sensorStatus: SensorStatus?
    var batteryVoltage: Double?
    var signalRSSIDBM: Int?
}

protocol TelemetryRepository: Sendable {
    func fetchReadings(
        nestIDs: [UUID],
        in interval: DateInterval?
    ) async throws -> [HeatReading]
}
