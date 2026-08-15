import Foundation
import Supabase

/// Supplies the stable, per-install Supabase Auth identity used by private
/// hatchery rows and Storage objects. Supabase persists anonymous sessions in
/// the Keychain, so a user keeps access to their hatcheries across launches
/// without a shared anonymous data set.
protocol SupabaseIdentityProviding: Sendable {
    func ensureAuthenticatedUserID() async throws -> UUID
}

actor SupabaseAuthenticationService: SupabaseIdentityProviding {
    private let client: SupabaseClient
    private var anonymousSignInTask: Task<UUID, Error>?

    init(client: SupabaseClient) {
        self.client = client
    }

    func ensureAuthenticatedUserID() async throws -> UUID {
        // `session` refreshes a saved session when needed. Check synchronously
        // first so concurrent first requests share the one anonymous sign-in
        // task instead of creating multiple device identities.
        if client.auth.currentSession != nil {
            let session = try await client.auth.session
            return session.user.id
        }

        if let anonymousSignInTask {
            return try await anonymousSignInTask.value
        }

        let client = client
        let task = Task<UUID, Error> {
            let session = try await client.auth.signInAnonymously()
            return session.user.id
        }
        anonymousSignInTask = task
        defer { anonymousSignInTask = nil }
        return try await task.value
    }
}
