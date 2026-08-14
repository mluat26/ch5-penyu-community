import Foundation
import Supabase

/// Talks to the `public.nest` table. Conforms to the same `NestRepository`
/// protocol as `InMemoryNestRepository`, so `AppContainer` is the only place
/// that needs to know which one is in use.
actor SupabaseNestRepository: NestRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetch(id: UUID) async throws -> NestEntity {
        let rows: [NestDTO] = try await client
            .from("nest")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        guard let dto = rows.first else {
            throw RepositoryError.notFound(resource: "Nest", id: id)
        }
        return try dto.toEntity()
    }

    func fetchAll(hatcheryID: UUID) async throws -> [NestEntity] {
        let rows: [NestDTO] = try await client
            .from("nest")
            .select()
            .eq("hatchery_id", value: hatcheryID)
            .order("date_eggs_laid", ascending: false)
            .execute()
            .value

        return try rows.map { try $0.toEntity() }
    }

    func create(_ input: CreateNestInput) async throws -> NestEntity {
        let insertDTO = input.toDTO()
        let rows: [NestDTO] = try await client
            .from("nest")
            .insert(insertDTO)
            .select()
            .execute()
            .value

        guard let dto = rows.first else {
            throw DataMappingError.missingRequiredValue(field: "nest insert response")
        }
        return try dto.toEntity()
    }

    func update(id: UUID, _ input: UpdateNestInput) async throws -> NestEntity {
        let updateDTO = input.toDTO()
        let rows: [NestDTO] = try await client
            .from("nest")
            .update(updateDTO)
            .eq("id", value: id)
            .select()
            .execute()
            .value

        guard let dto = rows.first else {
            throw RepositoryError.notFound(resource: "Nest", id: id)
        }
        return try dto.toEntity()
    }

    func delete(id: UUID) async throws {
        let rows: [NestDTO] = try await client
            .from("nest")
            .delete()
            .eq("id", value: id)
            .select()
            .execute()
            .value

        guard !rows.isEmpty else {
            throw RepositoryError.notFound(resource: "Nest", id: id)
        }
    }
}
