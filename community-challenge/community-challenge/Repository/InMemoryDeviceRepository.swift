import Foundation

actor InMemoryDeviceRepository: DeviceRepository {
    private var devices: [UUID: DeviceEntity]

    init(seed: [DeviceEntity] = []) {
        devices = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func fetch(id: UUID) async throws -> DeviceEntity {
        guard let device = devices[id] else {
            throw RepositoryError.notFound(resource: "Device", id: id)
        }
        return device
    }

    func fetchAll() async throws -> [DeviceEntity] {
        devices.values.sorted { $0.name < $1.name }
    }

    func create(_ input: RegisterDeviceInput) async throws -> DeviceEntity {
        try assignmentIsFree(nestID: input.nestID, excluding: nil)

        let device = DeviceEntity(
            id: UUID(),
            name: input.name,
            nestID: input.nestID,
            installedAt: Date()
        )
        devices[device.id] = device
        return device
    }

    func update(id: UUID, _ input: UpdateDeviceInput) async throws -> DeviceEntity {
        guard var device = devices[id] else {
            throw RepositoryError.notFound(resource: "Device", id: id)
        }
        try assignmentIsFree(nestID: input.nestID, excluding: id)

        device.name = input.name
        device.nestID = input.nestID
        devices[id] = device
        return device
    }

    func delete(id: UUID) async throws {
        guard devices.removeValue(forKey: id) != nil else {
            throw RepositoryError.notFound(resource: "Device", id: id)
        }
    }

    /// Mirrors the unique constraint on `device.nest_id`: a nest holds at most
    /// one device, while any number may sit unassigned.
    private func assignmentIsFree(nestID: UUID?, excluding deviceID: UUID?) throws {
        guard let nestID else { return }
        let taken = devices.values.contains { $0.nestID == nestID && $0.id != deviceID }
        guard !taken else {
            throw DomainValidationError.nestAlreadyHasDevice(nestID: nestID)
        }
    }
}
