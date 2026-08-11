//
//  Model.swift
//  community-challenge
//
//  Created by Jason Marsellino on 10/08/26.
//

import Foundation

// MARK: - Enums

enum HatcheryShape: String, Codable, CaseIterable, Identifiable {
    case square, rectangle, circle
    var id: String { rawValue }
}

enum UserRole: String, Codable, CaseIterable, Identifiable {
    case admin, ranger, viewer
    var id: String { rawValue }
}

enum SensorStatus: String, Codable {
    case online, offline, faulty
}

enum AlertLevel: String, Codable {
    case none, low, high, critical
}

enum HatchOutcome: String, Codable, CaseIterable, Identifiable {
    case success            // egg laid / hatched successfully
    case rotten
    case notHatched = "not_hatched"
    var id: String { rawValue }
}

// MARK: - Organization

struct Organization: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var dateCreated: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case dateCreated = "date_created"
    }
}

// MARK: - User

struct AppUser: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var organizationId: UUID?
    var role: UserRole?

    enum CodingKeys: String, CodingKey {
        case id, name, role
        case organizationId = "organization_id"
    }
}

// MARK: - Hatchery

struct Hatchery: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var shape: HatcheryShape
    var numberOfRow: Int
    var numberOfColumn: Int
    var lengthM: Double
    var widthM: Double
    var organizationId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, name, shape
        case numberOfRow = "number_of_row"
        case numberOfColumn = "number_of_column"
        case lengthM = "length_m"
        case widthM = "width_m"
        case organizationId = "organization_id"
    }
}

extension Hatchery {
    var sectionCount: Int { numberOfRow * numberOfColumn }
    var areaM2: Double { lengthM * widthM }
    var cellSize: (width: Double, height: Double) {
        (widthM / Double(max(numberOfColumn, 1)), lengthM / Double(max(numberOfRow, 1)))
    }
}

// MARK: - Nest

struct Nest: Codable, Identifiable, Hashable {
    let id: UUID
    var hatcheryId: UUID
    var founderId: UUID?              // user who found/registered the nest
    var numberOfEggs: Int
    var dateEggsLaid: Date?
    var datePredictedHatch: Date?
    var placeEggsLaid: String?        // origin beach / location text
    var successEggsHatch: Int?
    var failEggsHatch: Int?
    var placementRow: Int?
    var placementCol: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case hatcheryId = "hatchery_id"
        case founderId = "founder_id"
        case numberOfEggs = "number_of_eggs"
        case dateEggsLaid = "date_eggs_laid"
        case datePredictedHatch = "date_predicted_hatch"
        case placeEggsLaid = "place_eggs_laid"
        case successEggsHatch = "success_eggs_hatch"
        case failEggsHatch = "fail_eggs_hatch"
        case placementRow = "placement_row"
        case placementCol = "placement_col"
    }
}

extension Nest {
    var isHatched: Bool { successEggsHatch != nil || failEggsHatch != nil }
    var hatchRate: Double? {
        guard let s = successEggsHatch, numberOfEggs > 0 else { return nil }
        return Double(s) / Double(numberOfEggs)
    }
    var daysUntilHatch: Int? {
        guard let d = datePredictedHatch else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: d).day
    }
    var sectionKey: String? {
        guard let r = placementRow, let c = placementCol else { return nil }
        return "\(r)-\(c)"
    }
}

// MARK: - IoT Heat Data

struct IoTHeatData: Codable, Identifiable, Hashable {
    let id: UUID
    var nestId: UUID
    var sensorId: UUID?
    var position: String?            // e.g. top / middle / bottom of clutch
    var depthCm: Double?
    var temperatureC: Double
    var timestamp: Date
    var alert: AlertLevel?
    var sensorStatus: SensorStatus?
    var batteryVoltage: Double?
    var signalRssiDbm: Int?

    enum CodingKeys: String, CodingKey {
        case id, position, alert, timestamp
        case nestId = "nest_id"
        case sensorId = "sensor_id"
        case depthCm = "depth_cm"
        case temperatureC = "temperature_c"
        case sensorStatus = "sensor_status"
        case batteryVoltage = "battery_voltage"
        case signalRssiDbm = "signal_rssi_dbm"
    }
}

// MARK: - Aggregates / View Models payloads

struct HatcherySummary: Identifiable, Hashable {
    var id: UUID { hatchery.id }
    let hatchery: Hatchery
    var averageTemperatureC: Double?
    var totalEggs: Int
    var nestCount: Int
}

struct SectionSummary: Identifiable, Hashable {
    let id: String                   // "row-col"
    let row: Int
    let col: Int
    var nestCount: Int
    var totalEggs: Int
    var averageTemperatureC: Double?
    var nextHatchDate: Date?
}

struct TemperaturePoint: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let temperatureC: Double
}

// MARK: - Insert payloads (server generates id)

struct NewHatchery: Encodable {
    var name: String
    var shape: HatcheryShape
    var numberOfRow: Int
    var numberOfColumn: Int
    var lengthM: Double
    var widthM: Double
    var organizationId: UUID?

    enum CodingKeys: String, CodingKey {
        case name, shape
        case numberOfRow = "number_of_row"
        case numberOfColumn = "number_of_column"
        case lengthM = "length_m"
        case widthM = "width_m"
        case organizationId = "organization_id"
    }
}

struct NewNest: Encodable {
    var hatcheryId: UUID
    var founderId: UUID?
    var numberOfEggs: Int
    var dateEggsLaid: Date?
    var datePredictedHatch: Date?
    var placeEggsLaid: String?
    var placementRow: Int?
    var placementCol: Int?

    enum CodingKeys: String, CodingKey {
        case hatcheryId = "hatchery_id"
        case founderId = "founder_id"
        case numberOfEggs = "number_of_eggs"
        case dateEggsLaid = "date_eggs_laid"
        case datePredictedHatch = "date_predicted_hatch"
        case placeEggsLaid = "place_eggs_laid"
        case placementRow = "placement_row"
        case placementCol = "placement_col"
    }
}

struct HatchResultUpdate: Encodable {
    var successEggsHatch: Int
    var failEggsHatch: Int

    enum CodingKeys: String, CodingKey {
        case successEggsHatch = "success_eggs_hatch"
        case failEggsHatch = "fail_eggs_hatch"
    }
}
