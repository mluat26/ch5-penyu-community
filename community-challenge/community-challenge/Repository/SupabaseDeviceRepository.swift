import Foundation
import Supabase

actor SupabaseDeviceRepository: DeviceRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetch(id: UUID) async throws -> DeviceEntity {
        let rows: [DeviceDTO] = try await client
            .from("device")
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
        let rows: [DeviceDTO] = try await client
            .from("device")
            .select()
            .order("name", ascending: true)
            .execute()
            .value

        return rows.map { $0.toEntity() }
    }

    func create(_ input: RegisterDeviceInput) async throws -> DeviceEntity {
        let rows: [DeviceDTO] = try await client
            .from("device")
            .insert(input.toDTO())
            .select()
            .execute()
            .value

        guard let dto = rows.first else {
            throw DataMappingError.missingRequiredValue(field: "device insert response")
        }
        return dto.toEntity()
    }

    func update(id: UUID, _ input: UpdateDeviceInput) async throws -> DeviceEntity {
        let rows: [DeviceDTO] = try await client
            .from("device")
            .update(input.toDTO())
            .eq("id", value: id)
            .select()
            .execute()
            .value

        guard let dto = rows.first else {
            throw RepositoryError.notFound(resource: "Device", id: id)
        }
        return dto.toEntity()
    }

    func delete(id: UUID) async throws {
        let rows: [DeviceDTO] = try await client
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
