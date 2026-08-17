import Foundation

protocol HatcheryRepository: Sendable {
    func fetch(id: UUID) async throws -> HatcheryEntity
    func fetchAll() async throws -> [HatcheryEntity]
    func create(_ input: CreateHatcheryInput) async throws -> HatcheryEntity
    func update(id: UUID, _ input: UpdateHatcheryInput) async throws -> HatcheryEntity
    func delete(id: UUID) async throws
}
