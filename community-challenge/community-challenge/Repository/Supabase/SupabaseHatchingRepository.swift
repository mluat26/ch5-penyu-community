import Foundation
import Supabase

actor SupabaseHatchingRepository: HatchingRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetch(nestID: UUID) async throws -> HatchingEntity? {
        let rows: [HatchingDTO] = try await client
            .from("hatching")
            .select()
            .eq("nest_id", value: nestID)
            .execute()
            .value

        return rows.first?.toEntity()
    }

    func create(_ input: RecordHatchingInput) async throws -> HatchingEntity {
        let rows: [HatchingDTO]
        do {
            rows = try await client
                .from("hatching")
                .insert(input.toDTO())
                .select()
                .execute()
                .value
        } catch {
            // hatching.nest_id is unique, matching InMemoryHatchingRepository.
            guard PostgresErrorCode.matches(error, PostgresErrorCode.uniqueViolation) else {
                throw error
            }
            throw DomainValidationError.nestAlreadyHatched(nestID: input.nestID)
        }

        guard let dto = rows.first else {
            throw DataMappingError.missingRequiredValue(field: "hatching insert response")
        }
        return dto.toEntity()
    }

    func update(id: UUID, _ input: CorrectHatchingInput) async throws -> HatchingEntity {
        let rows: [HatchingDTO] = try await client
            .from("hatching")
            .update(input.toDTO())
            .eq("id", value: id)
            .select()
            .execute()
            .value

        guard let dto = rows.first else {
            throw RepositoryError.notFound(resource: "Hatching", id: id)
        }
        return dto.toEntity()
    }
}
