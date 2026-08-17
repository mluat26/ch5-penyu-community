import Foundation
import Supabase

/// SQLSTATE codes the app has domain rules for.
///
/// A repository protocol promises a set of signatures, not a set of failures.
/// Without translation the two implementations of the same protocol fail
/// differently: the in-memory one throws a `DomainValidationError` a view can
/// display, while the Supabase one leaks a raw PostgREST error. Tests pass
/// against the fake and the app shows a database message to a field worker.
nonisolated enum PostgresErrorCode {
    static let uniqueViolation = "23505"
    static let foreignKeyViolation = "23503"
    static let checkViolation = "23514"
    /// `RAISE EXCEPTION` from a plpgsql trigger.
    static let raisedException = "P0001"

    /// Nil when the error did not come from Postgres.
    nonisolated static func of(_ error: any Error) -> String? {
        (error as? PostgrestError)?.code
    }

    nonisolated static func matches(_ error: any Error, _ code: String) -> Bool {
        of(error) == code
    }
}
