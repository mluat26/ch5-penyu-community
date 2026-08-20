import Foundation
import Supabase

actor SupabaseIoTDataRepository: IoTDataRepository {
    /// `timestamp` is a `timestamptz`, and this is the only filter in the app
    /// that compares against a real instant rather than a calendar day.
    ///
    /// The client's encoder writes every `Date` as `yyyy-MM-dd`, which is right
    /// for the five `date` columns it saves and wrong here -- it collapsed this
    /// window to whole days and the chart came back empty. Formatting the bound
    /// explicitly keeps the two concerns apart.
    private static func instant(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private let client: SupabaseClient
    private let identity: any SupabaseIdentityProviding

    init(
        client: SupabaseClient,
        identity: any SupabaseIdentityProviding
    ) {
        self.client = client
        self.identity = identity
    }

    init(client: SupabaseClient) {
        self.client = client
        self.identity = SupabaseAuthenticationService(client: client)
    }

    func fetch(id: UUID) async throws -> IoTDataEntity {
        let rows: [IoTDataDTO] = try await client
            .from("iotdata")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        guard let dto = rows.first else {
            throw RepositoryError.notFound(resource: "IoTData", id: id)
        }
        return try dto.toEntity()
    }

    func fetchAll(nestID: UUID) async throws -> [IoTDataEntity] {
        let rows: [IoTDataDTO] = try await client
            .from("iotdata")
            .select()
            .eq("nest_id", value: nestID)
            .order("timestamp", ascending: false)
            .execute()
            .value

        return rows.compactMap { try? $0.toEntity() }
    }

    func fetchReadings(
        nestIDs: [UUID],
        in interval: DateInterval?
    ) async throws -> [IoTDataEntity] {
        guard !nestIDs.isEmpty else { return [] }
        _ = try await identity.ensureAuthenticatedUserID()

        var query = client
            .from("iotdata")
            .select()
            .in("nest_id", values: nestIDs)

        if let interval {
            query = query
                .gte("timestamp", value: Self.instant(interval.start))
                .lte("timestamp", value: Self.instant(interval.end))
        }

        let rows: [IoTDataDTO] = try await query
            .order("timestamp", ascending: false)
            .execute()
            .value

        // A row missing its temperature is unusable, but it must not take the
        // rest of the dashboard down with it: drop it and keep going.
        return rows.compactMap { try? $0.toEntity() }
    }
}
