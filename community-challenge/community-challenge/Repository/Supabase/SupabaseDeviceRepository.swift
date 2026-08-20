import Foundation
import Supabase

actor SupabaseDeviceRepository: DeviceRepository {
    private let client: SupabaseClient
    private let identity: any SupabaseIdentityProviding

    init(
        client: SupabaseClient,
        identity: any SupabaseIdentityProviding
    ) {
        self.client = client
        self.identity = identity
    }

    /// Kept for isolated tests and legacy composition points. The app's
    /// `AppContainer` injects one shared identity instance instead.
    init(client: SupabaseClient) {
        self.client = client
        self.identity = SupabaseAuthenticationService(client: client)
    }

    func fetch(id: UUID) async throws -> DeviceEntity {
        _ = try await identity.ensureAuthenticatedUserID()
        let rows: [DeviceDTO] = try await client
            .from("device_current_assignment")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        guard let dto = rows.first else {
            throw RepositoryError.notFound(resource: "Device", id: id)
        }
        return dto.toEntity()
    }

    func fetchAll() async throws -> [DeviceEntity] {
        _ = try await identity.ensureAuthenticatedUserID()
        let rows: [DeviceDTO] = try await client
            .from("device_current_assignment")
            .select()
            .order("name", ascending: true)
            .execute()
            .value

        return rows.map { $0.toEntity() }
    }

    func create(_ input: RegisterDeviceInput) async throws -> DeviceEntity {
        do {
            return try await save(input.toSaveDTO())
        } catch {
            throw Self.assignmentError(for: input.nestID, underlying: error)
        }
    }

    func update(id: UUID, _ input: UpdateDeviceInput) async throws -> DeviceEntity {
        do {
            return try await save(input.toSaveDTO(deviceID: id))
        } catch {
            throw Self.assignmentError(for: input.nestID, underlying: error)
        }
    }

    private func save(_ input: DeviceSaveDTO) async throws -> DeviceEntity {
        _ = try await identity.ensureAuthenticatedUserID()
        let rows: [DeviceSaveResultDTO] = try await client
            .rpc("save_device", params: input)
            .execute()
            .value

        guard let id = rows.first?.id else {
            throw DataMappingError.missingRequiredValue(field: "save_device response")
        }
        return try await fetch(id: id)
    }

    /// The active-assignment index enforces one device per nest. If the device
    /// was not being assigned to a nest, preserve the original server error.
    private static func assignmentError(for nestID: UUID?, underlying: any Error) -> any Error {
        guard
            PostgresErrorCode.matches(underlying, PostgresErrorCode.uniqueViolation),
            let nestID
        else {
            return underlying
        }
        return DomainValidationError.nestAlreadyHasDevice(nestID: nestID)
    }

    func delete(id: UUID) async throws {
        _ = try await identity.ensureAuthenticatedUserID()
        let rows: [DeviceSaveResultDTO] = try await client
            .from("device")
            .delete()
            .eq("id", value: id)
            .select()
            .execute()
            .value

        guard !rows.isEmpty else {
            throw RepositoryError.notFound(resource: "Device", id: id)
        }
    }
}
