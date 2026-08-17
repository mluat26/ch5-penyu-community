import Foundation

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
