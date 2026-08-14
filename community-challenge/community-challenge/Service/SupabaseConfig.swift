import Foundation
import Supabase

/// The Supabase project this app talks to.
///
/// Credentials live in `SupabaseSecrets`, which is git-ignored because this
/// repository is public. An anon key is normally safe to ship, since it names
/// the project rather than a user and Row Level Security decides what it may
/// touch — but the current dev policy grants anon full access to `hatchery` and
/// `nest`, so today this key *is* effectively a database credential. Keep it
/// out of version control until real ownership policies replace that one.
enum SupabaseConfig {
    static let client = SupabaseClient(
        supabaseURL: SupabaseSecrets.projectURL,
        supabaseKey: SupabaseSecrets.anonKey,
        options: SupabaseClientOptions(
            db: .init(decoder: .postgresDateAware)
        )
    )
}

private extension JSONDecoder {
    /// Postgres `date` columns (`date_eggs_laid`, `date_predicted_hatch`,
    /// `place_eggs_laid`) come back from PostgREST as plain `yyyy-MM-dd`
    /// strings. The SDK's default decoder only accepts full ISO8601
    /// timestamps, so a bare date fails to decode without this.
    static let postgresDateAware: JSONDecoder = {
        let dateOnlyFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

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
