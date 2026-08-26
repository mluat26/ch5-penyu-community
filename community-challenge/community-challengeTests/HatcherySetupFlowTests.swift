import CoreGraphics
import XCTest
@testable import community_challenge

@MainActor
final class HatcherySetupFlowTests: XCTestCase {
    func testSkipScanningKeepsAFunctionalBlankCanvasInsteadOfSamplePhoto() {
        let controller = HatcherySetupController(
            hatcheryService: HatcheryService(
                hatcheryRepository: InMemoryHatcheryRepository(),
                nestRepository: InMemoryNestRepository(),
                ioTDataRepository: InMemoryIoTDataRepository()
            )
        )

        controller.skipScanning()

        XCTAssertTrue(controller.draft.isAwaitingScan)
        XCTAssertFalse(controller.draft.usesMockImage)
        XCTAssertEqual(controller.draft.image?.size, CGSize(width: 1_960, height: 1_102))
        XCTAssertEqual(controller.draft.rectifiedImage?.size, CGSize(width: 1_960, height: 1_102))
        XCTAssertEqual(controller.draft.boundary, .fullImage)
        XCTAssertEqual(
            controller.draft.sandRegion,
            HatcherySandRegion.default(from: .fullImage)
        )

        // The skipped path has no photo, but it must still produce the same
        // section layout once the user confirms the displayed dimensions.
        //
        // The numbers are the default 8m x 6m solved against the 4 m² target:
        // twelve exactly square 2x2 sections. Deliberately spelled out rather
        // than read back from the solver, which is what generates them --
        // asserting a value against its own source proves nothing.
        XCTAssertTrue(controller.generateGrid(for: controller.draft.dimension))
        XCTAssertEqual(controller.draft.grid?.columns, 4)
        XCTAssertEqual(controller.draft.grid?.rows, 3)
        XCTAssertEqual(controller.draft.grid?.activeSectionCount, 12)
    }

    func testConcurrentCompletionCreatesOnlyOneHatchery() async throws {
        let hatcheryRepository = BlockingCreateHatcheryRepository(
            repository: InMemoryHatcheryRepository()
        )
        let controller = HatcherySetupController(
            hatcheryService: HatcheryService(
                hatcheryRepository: hatcheryRepository,
                nestRepository: InMemoryNestRepository(),
                ioTDataRepository: InMemoryIoTDataRepository()
            )
        )
        controller.setName("Hatch_01")
        controller.skipScanning()
        XCTAssertTrue(
            controller.generateGrid(
                for: HatcheryDimension(widthM: 6, heightM: 4)
            )
        )

        let firstCompletion = Task { @MainActor in
            await controller.completeSetup()
        }
        await hatcheryRepository.waitForCreateToStart()

        XCTAssertTrue(controller.isSaving)
        let secondCompletion = await controller.completeSetup()
        XCTAssertNil(secondCompletion)

        await hatcheryRepository.finishCreate()
        let firstSession = await firstCompletion.value
        let createdHatcheries = try await hatcheryRepository.fetchAll()
        let createCallCount = await hatcheryRepository.createCallCount()

        XCTAssertNotNil(firstSession)
        XCTAssertEqual(createCallCount, 1)
        XCTAssertEqual(createdHatcheries.count, 1)
        XCTAssertEqual(firstSession?.hatchery.id, createdHatcheries.first?.id)
    }
}

/// Holds the first persistence call open so the test can deterministically
/// issue a second completion before the first one returns to the main actor.
private actor BlockingCreateHatcheryRepository: HatcheryRepository {
    private let repository: InMemoryHatcheryRepository
    private var createCalls = 0
    private var createStartedWaiter: CheckedContinuation<Void, Never>?
    private var finishCreateWaiter: CheckedContinuation<Void, Never>?

    init(repository: InMemoryHatcheryRepository) {
        self.repository = repository
    }

    func fetch(id: UUID) async throws -> HatcheryEntity {
        try await repository.fetch(id: id)
    }

    func fetchAll() async throws -> [HatcheryEntity] {
        try await repository.fetchAll()
    }

    func create(_ input: CreateHatcheryInput) async throws -> HatcheryEntity {
        createCalls += 1
        createStartedWaiter?.resume()
        createStartedWaiter = nil

        await withCheckedContinuation { continuation in
            finishCreateWaiter = continuation
        }

        return try await repository.create(input)
    }

    func update(
        id: UUID,
        _ input: UpdateHatcheryInput
    ) async throws -> HatcheryEntity {
        try await repository.update(id: id, input)
    }

    func delete(id: UUID) async throws {
        try await repository.delete(id: id)
    }

    func waitForCreateToStart() async {
        guard createCalls == 0 else { return }
        await withCheckedContinuation { continuation in
            createStartedWaiter = continuation
        }
    }

    func finishCreate() {
        finishCreateWaiter?.resume()
        finishCreateWaiter = nil
    }

    func createCallCount() -> Int { createCalls }
}
