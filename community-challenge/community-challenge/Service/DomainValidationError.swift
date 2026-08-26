import Foundation

enum DomainValidationError: Error, LocalizedError, Sendable {
    case emptyName
    case duplicateHatcheryName
    case invalidDimensions
    case invalidEggCount
    case hatcheryNotEmpty(nestCount: Int)
    case resizeWouldStrandNests(count: Int)
    case hatchResultMissingCounts
    case completeNestNeedsNoNextDate
    case unfinishedInspectionNeedsNextDate
    case partialHatchNeedsHatchlings
    case nestAlreadyHasDevice(nestID: UUID)
    case nestAlreadyHatched(nestID: UUID)
    case hatchingExceedsClutch(counted: Int, clutchSize: Int)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            String(localized: "A name is required.")
        case .duplicateHatcheryName:
            String(localized: "Name already exists")
        case .invalidDimensions:
            String(localized: "Hatchery dimensions and grid counts must be positive.")
        case .invalidEggCount:
            String(localized: "A nest must contain at least one egg.")
        case let .hatcheryNotEmpty(nestCount):
            String(localized: "This hatchery still holds ^[\(nestCount) nest](inflect: true). Delete or move them before deleting the hatchery.")
        case let .resizeWouldStrandNests(count):
            String(localized: "^[\(count) nest](inflect: true) would fall outside the smaller grid. Move them to a section that still exists first.")
        case .hatchResultMissingCounts:
            String(localized: "Record how many eggs hatched and how many were rotten.")
        case .completeNestNeedsNoNextDate:
            String(localized: "A finished nest needs no further inspection.")
        case .unfinishedInspectionNeedsNextDate:
            String(localized: "Set the next inspection date: this nest still has eggs incubating.")
        case .partialHatchNeedsHatchlings:
            String(localized: "A partial hatch means at least one egg hatched.")
        case .nestAlreadyHasDevice:
            String(localized: "That nest already has a device. Unassign it first.")
        case .nestAlreadyHatched:
            String(localized: "This nest already has a hatching result. Edit it instead.")
        case let .hatchingExceedsClutch(counted, clutchSize):
            String(localized: "That totals \(counted) eggs, but the nest holds \(clutchSize).")
        }
    }
}

/// Keeps the client-side preflight aligned with the database's
/// `lower(btrim(name))` comparison while preserving the person's spelling for
/// display and storage.
nonisolated enum HatcheryName {
    static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalized(_ name: String) -> String {
        trimmed(name).lowercased()
    }
}
