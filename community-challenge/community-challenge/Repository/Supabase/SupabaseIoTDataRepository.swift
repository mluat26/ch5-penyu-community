import Foundation
import Supabase

actor SupabaseIoTDataRepository: IoTDataRepository {
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
                .gte("timestamp", value: interval.start)
                .lte("timestamp", value: interval.end)
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
