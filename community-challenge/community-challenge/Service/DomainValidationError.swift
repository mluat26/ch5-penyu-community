import Foundation

enum DomainValidationError: Error, LocalizedError, Sendable {
    case emptyName
    case invalidDimensions
    case invalidEggCount
    case hatcheryNotEmpty(nestCount: Int)
    case resizeWouldStrandNests(count: Int)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "A name is required."
        case .invalidDimensions:
            "Hatchery dimensions and grid counts must be positive."
        case .invalidEggCount:
            "A nest must contain at least one egg."
        case let .hatcheryNotEmpty(nestCount):
            "This hatchery still holds \(nestCount) nest\(nestCount == 1 ? "" : "s"). "
                + "Delete or move them before deleting the hatchery."
        case let .resizeWouldStrandNests(count):
            "\(count) nest\(count == 1 ? "" : "s") would fall outside the smaller grid. "
                + "Move them to a section that still exists first."
        }
    }
}
