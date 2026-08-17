import Foundation
import Supabase

actor SupabaseIoTDataRepository: IoTDataRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
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
