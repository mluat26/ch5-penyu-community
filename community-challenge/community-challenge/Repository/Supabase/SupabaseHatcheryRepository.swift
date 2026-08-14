import Foundation
import Supabase

/// Talks to the `public.hatchery` table. Conforms to the same `HatcheryRepository`
/// protocol as `InMemoryHatcheryRepository`, so `AppContainer` is the only place
/// that needs to know which one is in use.
actor SupabaseHatcheryRepository: HatcheryRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetch(id: UUID) async throws -> HatcheryEntity {
        let rows: [HatcheryDTO] = try await client
            .from("hatchery")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        guard let dto = rows.first else {
            throw RepositoryError.notFound(resource: "Hatchery", id: id)
        }
        return try dto.toEntity()
    }

    func fetchAll() async throws -> [HatcheryEntity] {
        let rows: [HatcheryDTO] = try await client
            .from("hatchery")
            .select()
            .order("name", ascending: true)
            .execute()
            .value

        return try rows.map { try $0.toEntity() }
    }

    func create(_ input: CreateHatcheryInput) async throws -> HatcheryEntity {
        let insertDTO = try input.toDTO()
        let rows: [HatcheryDTO] = try await client
            .from("hatchery")
            .insert(insertDTO)
            .select()
            .execute()
            .value

        guard let dto = rows.first else {
            throw DataMappingError.missingRequiredValue(field: "hatchery insert response")
        }
        return try dto.toEntity()
    }

    func update(id: UUID, _ input: UpdateHatcheryInput) async throws -> HatcheryEntity {
        let updateDTO = input.toDTO()
        let rows: [HatcheryDTO] = try await client
            .from("hatchery")
            .update(updateDTO)
            .eq("id", value: id)
            .select()
            .execute()
            .value

        guard let dto = rows.first else {
            throw RepositoryError.notFound(resource: "Hatchery", id: id)
        }
        return try dto.toEntity()
    }

    func delete(id: UUID) async throws {
        let rows: [HatcheryDTO] = try await client
            .from("hatchery")
            .delete()
            .eq("id", value: id)
            .select()
            .execute()
            .value

        guard !rows.isEmpty else {
            throw RepositoryError.notFound(resource: "Hatchery", id: id)
        }
    }
}
