import Foundation
import Supabase

/// The Supabase project this app talks to.
///
/// Credentials come from Info.plist values declared by `Config/Info.plist` and
/// populated by `Config/BuildSettings.xcconfig`. That tracked file optionally
/// includes the local, git-ignored `Config/SupabaseSecrets.xcconfig` file.
///
/// An anon/publishable key necessarily ships in a client app; its safety comes
/// from Row Level Security. The app exchanges it for a per-device anonymous
/// Auth session before it accesses owner-scoped hatcheries or private Storage.
enum SupabaseConfig {
    /// Ensures there is a session before anything tries to write.
    ///
    /// The database requires an authenticated user to create a hatchery, so an
    /// anonymous request is refused with "An authenticated user is required to
    /// create a hatchery". Anonymous sign-in is not "no auth": Supabase creates
    /// a real `auth.users` row and issues a genuine session, so `auth.uid()`
    /// returns a value and `hatchery.owner_id` gets populated.
    ///
    /// Idempotent — a session persists across launches, so this is a no-op on
    /// every launch after the first.
    ///
    /// ponytail: anonymous sign-in unblocks development; replace with the real
    /// provider once one is enabled on the project. Note that each install
    /// becomes its own user, so hatcheries created on one device are owned by
    /// an account no other device can sign into.
    @discardableResult
    static func ensureSignedIn() async throws -> UUID {
        if let existing = client.auth.currentSession {
            return existing.user.id
        }
        let session = try await client.auth.signInAnonymously()
        return session.user.id
    }

    static let client = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: anonKey,
        options: SupabaseClientOptions(
            db: .init(
                encoder: .postgresDateAware,
                decoder: .postgresDateAware
            )
        )
    )

    /// A harmless valid URL lets local builds and offline tests start before a
    /// developer has created their ignored configuration file. Any attempted
    /// backend request then fails without exposing a real project endpoint.
    private static let placeholderURL = URL(string: "https://missing-supabase-configuration.invalid")!
    private static let placeholderAnonKey = "missing-supabase-configuration"

    private static var projectURL: URL {
        let value = configurationValue(
            for: "SUPABASE_URL",
            fallback: placeholderURL.absoluteString
        )

        guard let url = URL(string: value), url.scheme == "https", url.host != nil else {
            return placeholderURL
        }
        return url
    }

    private static var anonKey: String {
        configurationValue(for: "SUPABASE_ANON_KEY", fallback: placeholderAnonKey)
    }

    private static func configurationValue(for key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return fallback
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty || trimmedValue.hasPrefix("$(") ? fallback : trimmedValue
    }
}

/// The `yyyy-MM-dd` wire format of a Postgres `date` column, read and written
/// in the device's own time zone.
///
/// A `date` column carries no time and no zone: it is a calendar day. Both
/// halves of the round trip therefore have to agree on which calendar, or the
/// day shifts. They previously did not -- the decoder read at UTC while the
/// encoder was the SDK's default, which serialises an instant in GMT with the
/// zone marker stripped. East of GMT, local midnight went out as the previous
/// afternoon and Postgres kept the literal date part, losing a day on write;
/// west of GMT the same mismatch lost one on read instead. Nest detail then
/// re-encoded what it had decoded, so every save moved the date again.
private let postgresDateOnlyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

private extension JSONEncoder {
    /// Writes every `Date` as a bare calendar day, which is what all five date
    /// columns this app writes actually are: `date_eggs_laid`,
    /// `date_predicted_hatch`, `next_inspection_date`, `inspected_on` and
    /// `hatched_on`. Nothing encodes a true timestamp -- `installed_at` and
    /// `iotdata.timestamp` are read-only here -- so this needs no exceptions.
    static let postgresDateAware: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(postgresDateOnlyFormatter.string(from: date))
        }
        return encoder
    }()
}

private extension JSONDecoder {
    /// Postgres `date` columns come back from PostgREST as plain `yyyy-MM-dd`
    /// strings. The SDK's default decoder only accepts full ISO8601
    /// timestamps, so a bare date fails to decode without this.
    static let postgresDateAware: JSONDecoder = {
        let dateOnlyFormatter = postgresDateOnlyFormatter

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = dateOnlyFormatter.date(from: string) {
                return date
            }
            if let date = try? Date(string, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(string)"
            )
        }
        return decoder
    }()
}
