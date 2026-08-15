import Foundation

enum SensorStatus: String, Sendable {
    case online
    case offline
    case faulty
}

enum AlertLevel: String, Sendable {
    case none
    case low
    case high
    case critical
}

struct IoTDataEntity: Identifiable, Hashable, Sendable {
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
