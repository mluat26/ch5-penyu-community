import Foundation

struct RegisterDeviceInput: Hashable, Sendable {
    var name: String
    var nestID: UUID?
}

struct UpdateDeviceInput: Hashable, Sendable {
    var name: String
    var nestID: UUID?
}

struct DeviceService: Sendable {
    private let repository: any DeviceRepository

    init(repository: any DeviceRepository) {
        self.repository = repository
    }

    func devices() async throws -> [DeviceEntity] {
        try await repository.fetchAll()
    }

    func device(id: UUID) async throws -> DeviceEntity {
        try await repository.fetch(id: id)
    }

    func registerDevice(_ input: RegisterDeviceInput) async throws -> DeviceEntity {
        guard !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.emptyName
        }
        return try await repository.create(input)
    }

    func updateDevice(id: UUID, _ input: UpdateDeviceInput) async throws -> DeviceEntity {
        guard !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.emptyName
        }
        return try await repository.update(id: id, input)
    }

    /// Frees the device from its nest without deleting it: the hardware still
    /// exists and can be installed elsewhere.
    func unassignDevice(id: UUID) async throws -> DeviceEntity {
        let device = try await repository.fetch(id: id)
        return try await repository.update(
            id: id,
            UpdateDeviceInput(name: device.name, nestID: nil)
        )
    }

    func deleteDevice(id: UUID) async throws {
        try await repository.delete(id: id)
    }
}
