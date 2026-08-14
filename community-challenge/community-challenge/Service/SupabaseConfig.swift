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
    static let client = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: anonKey,
        options: SupabaseClientOptions(
            db: .init(decoder: .postgresDateAware)
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
