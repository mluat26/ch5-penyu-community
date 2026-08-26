import Foundation
import Supabase

actor SupabaseHatchingRepository: HatchingRepository {
    private let client: SupabaseClient
    /// Every other Supabase repository resolves the session before touching the
    /// database; this one did not, which stopped mattering the day
    /// `hatching.recorded_by` started being stamped from `auth.uid()`. On a
    /// cold launch the insert would land with a NULL recorder and no error --
    /// an anonymous entry in the one table that exists to say who did the work.
    private let identity: any SupabaseIdentityProviding

    init(client: SupabaseClient, identity: any SupabaseIdentityProviding) {
        self.client = client
        self.identity = identity
    }

    init(client: SupabaseClient) {
        self.client = client
        self.identity = SupabaseAuthenticationService(client: client)
    }

    func fetch(nestID: UUID) async throws -> HatchingEntity? {
        _ = try await identity.ensureAuthenticatedUserID()

        let rows: [HatchingDTO] = try await client
            .from("hatching")
            .select()
            .eq("nest_id", value: nestID)
            .execute()
            .value

        return rows.first?.toEntity()
    }

    func create(_ input: RecordHatchingInput) async throws -> HatchingEntity {
        _ = try await identity.ensureAuthenticatedUserID()

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
        _ = try await identity.ensureAuthenticatedUserID()

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
