import XCTest
@testable import community_challenge

@MainActor
final class HatcheryRescanPersistenceTests: XCTestCase {
    func testRescanUpdatesTheExistingHatcheryInsteadOfCreatingAnotherRow() async throws {
        let existing = HatcheryEntity(
            id: UUID(),
            name: "Hatch_01",
            shape: .rectangle,
            numberOfRows: 2,
            numberOfColumns: 3,
            lengthM: 4,
            widthM: 6,
            organizationID: nil
        )
        let hatcheryRepository = InMemoryHatcheryRepository(seed: [existing])
        let service = HatcheryService(
            hatcheryRepository: hatcheryRepository,
            nestRepository: InMemoryNestRepository(),
            telemetryRepository: InMemoryTelemetryRepository()
        )
        let controller = HatcherySetupController(
            hatcheryService: service,
            existingHatchery: existing
        )

        controller.skipScanning()
        let rescannedDimension = HatcheryDimension(widthM: 8, heightM: 6)
        XCTAssertTrue(controller.generateGrid(for: rescannedDimension))

        let session = await controller.completeSetup()
        let stored = try await hatcheryRepository.fetchAll()

        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(session?.hatchery.id, existing.id)
        XCTAssertEqual(session?.hatchery.name, existing.name)
        XCTAssertEqual(session?.hatchery.widthM, 8)
        XCTAssertEqual(session?.hatchery.lengthM, 6)
        XCTAssertEqual(session?.hatchery.numberOfColumns, 4)
        XCTAssertEqual(session?.hatchery.numberOfRows, 3)
    }
}
