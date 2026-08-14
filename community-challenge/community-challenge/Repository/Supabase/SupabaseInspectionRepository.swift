import Foundation
import Supabase

actor SupabaseInspectionRepository: InspectionRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchAll(nestID: UUID) async throws -> [InspectionEntity] {
        let rows: [InspectionDTO] = try await client
            .from("inspection")
            .select()
            .eq("nest_id", value: nestID)
            .order("inspected_on", ascending: false)
            .execute()
            .value

        return try rows.map { try $0.toEntity() }
    }

    func create(_ input: RecordInspectionInput) async throws -> InspectionEntity {
        let rows: [InspectionDTO] = try await client
            .from("inspection")
            .insert(input.toDTO())
            .select()
            .execute()
            .value

        guard let dto = rows.first else {
            throw DataMappingError.missingRequiredValue(field: "inspection insert response")
        }
        return try dto.toEntity()
    }

    func update(id: UUID, _ input: CorrectInspectionInput) async throws -> InspectionEntity {
        let rows: [InspectionDTO] = try await client
            .from("inspection")
            .update(input.toDTO())
            .eq("id", value: id)
            .select()
            .execute()
            .value

        guard let dto = rows.first else {
            throw RepositoryError.notFound(resource: "Inspection", id: id)
        }
        return try dto.toEntity()
    }
}
