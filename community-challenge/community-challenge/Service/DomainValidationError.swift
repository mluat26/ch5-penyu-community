import Foundation

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
