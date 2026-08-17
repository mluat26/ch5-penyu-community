import Foundation

protocol DeviceRepository: Sendable {
    func fetch(id: UUID) async throws -> DeviceEntity
    func fetchAll() async throws -> [DeviceEntity]
    func create(_ input: RegisterDeviceInput) async throws -> DeviceEntity
    func update(id: UUID, _ input: UpdateDeviceInput) async throws -> DeviceEntity
    func delete(id: UUID) async throws
}
