import Foundation

enum DomainValidationError: Error, LocalizedError, Sendable {
    case emptyName
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
        case .hatchResultMissingCounts:
            "Record how many eggs hatched and how many were rotten."
        case .completeNestNeedsNoNextDate:
            "A finished nest needs no further inspection."
        case .unfinishedInspectionNeedsNextDate:
            "Set the next inspection date: this nest still has eggs incubating."
        case .partialHatchNeedsHatchlings:
            "A partial hatch means at least one egg hatched."
        case .nestAlreadyHasDevice:
            "That nest already has a device. Unassign it first."
        case .nestAlreadyHatched:
            "This nest already has a hatching result. Edit it instead."
        case let .hatchingExceedsClutch(counted, clutchSize):
            "That totals \(counted) eggs, but the nest holds \(clutchSize)."
        }
    }
}
