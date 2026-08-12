import Foundation

protocol HatcheryRepository: Sendable {
    func fetch(id: UUID) async throws -> HatcheryEntity
    func create(_ input: CreateHatcheryInput) async throws -> HatcheryEntity
}
