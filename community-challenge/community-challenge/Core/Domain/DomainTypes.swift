import Foundation

// Domain types deliberately model app language only. Database/API spelling
// belongs to DTOs in each feature's Data layer.

enum HatcheryShape: String, CaseIterable, Identifiable, Sendable {
    case square
    case rectangle
    case circle

    var id: String { rawValue }
}

enum UserRole: String, CaseIterable, Identifiable, Sendable {
    case admin
    case ranger
    case viewer

    var id: String { rawValue }
}

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

enum HatchOutcome: String, CaseIterable, Identifiable, Sendable {
    case success
    case rotten
    case notHatched = "not_hatched"

    var id: String { rawValue }
}

enum RepositoryError: Error, LocalizedError, Sendable {
    case notFound(resource: String, id: UUID)

    var errorDescription: String? {
        switch self {
        case let .notFound(resource, id):
            "\(resource) \(id.uuidString) was not found."
        }
    }
}

enum DataMappingError: Error, LocalizedError, Sendable {
    case invalidEnum(field: String, value: String)
    case missingRequiredValue(field: String)
    case schemaColumnUnavailable(table: String, column: String)

    var errorDescription: String? {
        switch self {
        case let .invalidEnum(field, value):
            "Unsupported value '\(value)' for \(field)."
        case let .missingRequiredValue(field):
            "A value is required for \(field)."
        case let .schemaColumnUnavailable(table, column):
            "The current \(table) schema does not contain \(column)."
        }
    }
}

enum DomainValidationError: Error, LocalizedError, Sendable {
    case emptyName
    case invalidDimensions
    case invalidEggCount

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "A name is required."
        case .invalidDimensions:
            "Hatchery dimensions and grid counts must be positive."
        case .invalidEggCount:
            "A nest must contain at least one egg."
        }
    }
}
