import Supabase

/// Converts the single, documented conflict emitted by the hatchery-name
/// database guard into a domain error that every SwiftUI surface can present.
nonisolated enum HatcheryPersistenceErrorMapper {
    private static let duplicateNameDetail = "hatchery_owner_normalized_name_unique"

    static func map(_ error: Error) -> Error {
        guard let databaseError = error as? PostgrestError,
              databaseError.code == "23505",
              databaseError.details == duplicateNameDetail
                || databaseError.message == "Name already exists"
        else {
            return error
        }

        return DomainValidationError.duplicateHatcheryName
    }
}
