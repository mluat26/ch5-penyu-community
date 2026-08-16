import Foundation
import Supabase

/// Reads and writes the signed-in member's profile, and issues or redeems
/// organization invite codes.
///
/// Invites go through `security definer` database functions rather than table
/// writes: manager-only issuing, single use, and expiry are enforced there so
/// they hold no matter what the client sends.
protocol ProfileRepository: Sendable {
    func fetchCurrentProfile() async throws -> ProfileEntity?
    func updateCurrentProfile(displayName: String?, appleEmail: String?) async throws -> ProfileEntity
    func fetchOrganization(id: UUID) async throws -> OrganizationEntity
    func generateInvite() async throws -> OrganizationInviteEntity
    @discardableResult func redeemInvite(code: String) async throws -> UUID
    func deleteAccount() async throws
}

actor SupabaseProfileRepository: ProfileRepository {
    private let client: SupabaseClient
    private let identity: any SupabaseIdentityProviding

    init(client: SupabaseClient, identity: any SupabaseIdentityProviding) {
        self.client = client
        self.identity = identity
    }

    /// Returns `nil` rather than throwing when no row exists yet: a member has
    /// no profile until they create their first hatchery or redeem an invite,
    /// and that is an ordinary state, not a failure.
    func fetchCurrentProfile() async throws -> ProfileEntity? {
        let userID = try await identity.ensureAuthenticatedUserID()

        let rows: [ProfileDTO] = try await client
            .from("profile")
            .select()
            .eq("id", value: userID)
            .execute()
            .value

        return try rows.first?.toEntity()
    }

    func updateCurrentProfile(
        displayName: String?,
        appleEmail: String?
    ) async throws -> ProfileEntity {
        let userID = try await identity.ensureAuthenticatedUserID()

        let rows: [ProfileDTO] = try await client
            .from("profile")
            .update(ProfileUpdateDTO(displayName: displayName, appleEmail: appleEmail))
            .eq("id", value: userID)
            .select()
            .execute()
            .value

        guard let dto = rows.first else {
            throw RepositoryError.notFound(resource: "Profile", id: userID)
        }
        return try dto.toEntity()
    }

    func fetchOrganization(id: UUID) async throws -> OrganizationEntity {
        _ = try await identity.ensureAuthenticatedUserID()

        let rows: [OrganizationDTO] = try await client
            .from("organization")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        guard let dto = rows.first else {
            throw RepositoryError.notFound(resource: "Organization", id: id)
        }
        return try dto.toEntity()
    }

    func generateInvite() async throws -> OrganizationInviteEntity {
        _ = try await identity.ensureAuthenticatedUserID()

        let rows: [OrganizationInviteDTO] = try await client
            .rpc("generate_organization_invite")
            .execute()
            .value

        guard let dto = rows.first else {
            throw DataMappingError.missingRequiredValue(
                field: "generate_organization_invite response"
            )
        }
        return dto.toEntity()
    }

    /// Removes the caller's account and everything that belongs to it. The
    /// function is `security definer` and scoped to `auth.uid()`, so the app
    /// never needs a privileged key to do this.
    func deleteAccount() async throws {
        _ = try await identity.ensureAuthenticatedUserID()

        try await client
            .rpc("delete_my_account")
            .execute()
    }

    @discardableResult
    func redeemInvite(code: String) async throws -> UUID {
        _ = try await identity.ensureAuthenticatedUserID()

        return try await client
            .rpc("redeem_organization_invite", params: RedeemInviteDTO(inviteCode: code))
            .execute()
            .value
    }
}
