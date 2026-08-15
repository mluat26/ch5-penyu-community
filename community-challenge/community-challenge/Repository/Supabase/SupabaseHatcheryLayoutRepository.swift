import Foundation
import Supabase

/// RPC-backed repository for private, revisioned scan layouts. Direct table
/// writes are intentionally unavailable to the client; the database owns the
/// begin/upload/finalize state transition.
actor SupabaseHatcheryLayoutRepository: HatcheryLayoutRepository {
    private let client: SupabaseClient
    private let identity: any SupabaseIdentityProviding

    init(
        client: SupabaseClient,
        identity: any SupabaseIdentityProviding
    ) {
        self.client = client
        self.identity = identity
    }

    func fetchCurrent(hatcheryID: UUID) async throws -> HatcheryLayoutRevision? {
        _ = try await identity.ensureAuthenticatedUserID()

        let rows: [HatcheryLayoutDTO] = try await client
            .from("hatchery_layout")
            .select()
            .eq("hatchery_id", value: hatcheryID)
            .eq("is_current", value: true)
            .limit(1)
            .execute()
            .value

        return try rows.first.map { try $0.toEntity() }
    }

    func fetch(id: UUID) async throws -> HatcheryLayoutRevision? {
        _ = try await identity.ensureAuthenticatedUserID()

        let rows: [HatcheryLayoutDTO] = try await client
            .from("hatchery_layout")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value

        return try rows.first.map { try $0.toEntity() }
    }

    func begin(_ request: HatcheryLayoutSaveRequest) async throws -> HatcheryLayoutRevision {
        try await begin(request, rpc: "begin_hatchery_layout")
    }

    func beginNewHatchery(
        _ request: HatcheryLayoutSaveRequest
    ) async throws -> HatcheryLayoutRevision {
        try await begin(request, rpc: "begin_new_hatchery_layout")
    }

    private func begin(
        _ request: HatcheryLayoutSaveRequest,
        rpc: String
    ) async throws -> HatcheryLayoutRevision {
        do {
            _ = try await identity.ensureAuthenticatedUserID()

            let rows: [HatcheryLayoutDTO] = try await client
                .rpc(rpc, params: HatcheryLayoutBeginDTO(request: request))
                .execute()
                .value

            guard let layout = try rows.first?.toEntity() else {
                throw DataMappingError.missingRequiredValue(field: "\(rpc) response")
            }
            return layout
        } catch {
            throw HatcheryPersistenceErrorMapper.map(error)
        }
    }

    func finalize(
        layoutID: UUID,
        sourcePhoto: HatcherySourcePhoto?
    ) async throws -> HatcheryLayoutRevision {
        _ = try await identity.ensureAuthenticatedUserID()

        let rows: [HatcheryLayoutDTO] = try await client
            .rpc(
                "finalize_hatchery_layout",
                params: HatcheryLayoutFinalizeDTO(
                    layoutID: layoutID,
                    sourcePhoto: sourcePhoto
                )
            )
            .execute()
            .value

        guard let layout = try rows.first?.toEntity() else {
            throw DataMappingError.missingRequiredValue(field: "finalize_hatchery_layout response")
        }
        return layout
    }

    func abandon(layoutID: UUID) async throws -> HatcheryLayoutRevision {
        _ = try await identity.ensureAuthenticatedUserID()

        let rows: [HatcheryLayoutDTO] = try await client
            .rpc("abandon_hatchery_layout", params: HatcheryLayoutIDDTO(layoutID: layoutID))
            .execute()
            .value

        guard let layout = try rows.first?.toEntity() else {
            throw DataMappingError.missingRequiredValue(field: "abandon_hatchery_layout response")
        }
        return layout
    }

    func purgeFailed(layoutID: UUID) async throws {
        _ = try await identity.ensureAuthenticatedUserID()

        try await client
            .rpc(
                "purge_failed_hatchery_layout",
                params: HatcheryLayoutIDDTO(layoutID: layoutID)
            )
            .execute()
    }
}

/// Private Storage access for layout source photos. Every operation first
/// ensures an anonymous/device auth session because the bucket is RLS-protected.
actor SupabaseHatcheryPhotoStore: HatcheryPhotoStore {
    private let client: SupabaseClient
    private let identity: any SupabaseIdentityProviding

    init(
        client: SupabaseClient,
        identity: any SupabaseIdentityProviding
    ) {
        self.client = client
        self.identity = identity
    }

    func upload(path: String, data: Data, contentType: String) async throws {
        _ = try await identity.ensureAuthenticatedUserID()
        try await client.storage
            .from(HatcheryLayoutStorage.bucketName)
            .upload(
                path,
                data: data,
                options: FileOptions(
                    cacheControl: "31536000",
                    contentType: contentType,
                    upsert: false
                )
            )
    }

    func download(path: String) async throws -> Data {
        _ = try await identity.ensureAuthenticatedUserID()
        return try await client.storage
            .from(HatcheryLayoutStorage.bucketName)
            .download(path: path)
    }

    func delete(path: String) async throws {
        _ = try await identity.ensureAuthenticatedUserID()
        _ = try await client.storage
            .from(HatcheryLayoutStorage.bucketName)
            .remove(paths: [path])
    }
}
