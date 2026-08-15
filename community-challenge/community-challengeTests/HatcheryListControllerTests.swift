import XCTest
@testable import community_challenge

@MainActor
final class HatcheryListControllerTests: XCTestCase {
    func testInitialBackendFailureIsNotTreatedAsAnEmptyHatcheryAccount() async {
        let controller = HatcheryListController(
            hatcheryService: HatcheryService(
                hatcheryRepository: FailingHatcheryRepository(),
                nestRepository: InMemoryNestRepository(),
                ioTDataRepository: InMemoryIoTDataRepository()
            )
        )

        await controller.load()

        XCTAssertTrue(controller.hasLoaded)
        XCTAssertFalse(controller.hasSuccessfulLoad)
        XCTAssertTrue(controller.hatcheries.isEmpty)
        XCTAssertEqual(controller.errorMessage, "Test backend unavailable")
    }

    func testManagementWaitsForAnInFlightListLoad() async {
        let hatchery = HatcheryEntity(
            id: UUID(),
            name: "Hatch_01",
            shape: .rectangle,
            numberOfRows: 3,
            numberOfColumns: 4,
            lengthM: 5,
            widthM: 4,
            organizationID: nil
        )
        let repository = DelayedHatcheryRepository(hatcheries: [hatchery])
        let controller = HatcheryListController(
            hatcheryService: HatcheryService(
                hatcheryRepository: repository,
                nestRepository: InMemoryNestRepository(),
                ioTDataRepository: InMemoryIoTDataRepository()
            )
        )

        let initialLoad = Task { await controller.load() }
        await Task.yield()
        await controller.loadManagement()
        await initialLoad.value

        XCTAssertEqual(controller.managementSummaries.map(\.hatchery), [hatchery])
        let fetchAllCallCount = await repository.fetchAllCallCount()
        XCTAssertEqual(fetchAllCallCount, 1)
    }

    func testFirstSessionOpensTheFirstLoadedHatchery() async {
        let firstHatchery = HatcheryEntity(
            id: UUID(),
            name: "Hatch_01",
            shape: .rectangle,
            numberOfRows: 3,
            numberOfColumns: 4,
            lengthM: 5,
            widthM: 4,
            organizationID: nil
        )
        let laterHatchery = HatcheryEntity(
            id: UUID(),
            name: "Hatch_02",
            shape: .rectangle,
            numberOfRows: 3,
            numberOfColumns: 4,
            lengthM: 5,
            widthM: 4,
            organizationID: nil
        )
        let controller = HatcheryListController(
            hatcheryService: HatcheryService(
                hatcheryRepository: InMemoryHatcheryRepository(
                    seed: [laterHatchery, firstHatchery]
                ),
                nestRepository: InMemoryNestRepository(),
                ioTDataRepository: InMemoryIoTDataRepository()
            )
        )

        await controller.load()
        let session = await controller.firstSession()

        XCTAssertEqual(session?.hatchery.id, firstHatchery.id)
        XCTAssertEqual(session?.hatchery.name, "Hatch_01")
    }

    func testRapidSelectionSingleFlightsAndUsesTheAuthoritativeHatchery() async {
        let hatcheryID = UUID()
        let staleHatchery = HatcheryEntity(
            id: hatcheryID,
            name: "Old Hatchery Name",
            shape: .rectangle,
            numberOfRows: 1,
            numberOfColumns: 1,
            lengthM: 2,
            widthM: 2,
            organizationID: nil
        )
        let authoritativeHatchery = HatcheryEntity(
            id: hatcheryID,
            name: "Current Hatchery Name",
            shape: .rectangle,
            numberOfRows: 3,
            numberOfColumns: 4,
            lengthM: 6,
            widthM: 8,
            organizationID: nil
        )
        let repository = BlockingFetchHatcheryRepository(
            repository: InMemoryHatcheryRepository(seed: [authoritativeHatchery])
        )
        let controller = HatcheryListController(
            hatcheryService: HatcheryService(
                hatcheryRepository: repository,
                nestRepository: InMemoryNestRepository(),
                ioTDataRepository: InMemoryIoTDataRepository()
            )
        )

        let firstSelection = Task { @MainActor in
            await controller.session(for: staleHatchery)
        }
        await repository.waitForFetchToStart()

        XCTAssertEqual(controller.openingHatcheryID, hatcheryID)
        let secondSelection = await controller.session(for: staleHatchery)
        XCTAssertNil(secondSelection)

        await repository.finishFetch()
        let restoredSession = await firstSelection.value
        let fetchCallCount = await repository.fetchCallCount()

        XCTAssertEqual(fetchCallCount, 1)
        XCTAssertNil(controller.openingHatcheryID)
        XCTAssertEqual(restoredSession?.hatchery, authoritativeHatchery)
        XCTAssertEqual(restoredSession?.grid.rows, authoritativeHatchery.numberOfRows)
        XCTAssertEqual(restoredSession?.grid.columns, authoritativeHatchery.numberOfColumns)
    }
}

private enum TestHatcheryRepositoryError: LocalizedError {
    case unavailable

    var errorDescription: String? { "Test backend unavailable" }
}

private struct FailingHatcheryRepository: HatcheryRepository {
    func fetch(id: UUID) async throws -> HatcheryEntity {
        throw TestHatcheryRepositoryError.unavailable
    }

    func fetchAll() async throws -> [HatcheryEntity] {
        throw TestHatcheryRepositoryError.unavailable
    }

    func create(_ input: CreateHatcheryInput) async throws -> HatcheryEntity {
        throw TestHatcheryRepositoryError.unavailable
    }

    func update(
        id: UUID,
        _ input: UpdateHatcheryInput
    ) async throws -> HatcheryEntity {
        throw TestHatcheryRepositoryError.unavailable
    }

    func delete(id: UUID) async throws {
        throw TestHatcheryRepositoryError.unavailable
    }
}

private actor DelayedHatcheryRepository: HatcheryRepository {
    private let hatcheries: [HatcheryEntity]
    private var fetchAllCalls = 0

    init(hatcheries: [HatcheryEntity]) {
        self.hatcheries = hatcheries
    }

    func fetch(id: UUID) async throws -> HatcheryEntity {
        guard let hatchery = hatcheries.first else {
            throw TestHatcheryRepositoryError.unavailable
        }
        return hatchery
    }

    func fetchAll() async throws -> [HatcheryEntity] {
        fetchAllCalls += 1
        try? await Task.sleep(nanoseconds: 50_000_000)
        return hatcheries
    }

    func create(_ input: CreateHatcheryInput) async throws -> HatcheryEntity {
        throw TestHatcheryRepositoryError.unavailable
    }

    func update(
        id: UUID,
        _ input: UpdateHatcheryInput
    ) async throws -> HatcheryEntity {
        throw TestHatcheryRepositoryError.unavailable
    }

    func delete(id: UUID) async throws {
        throw TestHatcheryRepositoryError.unavailable
    }

    func fetchAllCallCount() -> Int { fetchAllCalls }
}

/// Makes the first `session(for:)` wait at the repository boundary, which
/// gives the test a deterministic overlapping tap without relying on timing.
private actor BlockingFetchHatcheryRepository: HatcheryRepository {
    private let repository: InMemoryHatcheryRepository
    private var fetchCalls = 0
    private var fetchStartedWaiter: CheckedContinuation<Void, Never>?
    private var finishFetchWaiter: CheckedContinuation<Void, Never>?

    init(repository: InMemoryHatcheryRepository) {
        self.repository = repository
    }

    func fetch(id: UUID) async throws -> HatcheryEntity {
        fetchCalls += 1
        fetchStartedWaiter?.resume()
        fetchStartedWaiter = nil
        await withCheckedContinuation { continuation in
            finishFetchWaiter = continuation
        }
        return try await repository.fetch(id: id)
    }

    func fetchAll() async throws -> [HatcheryEntity] {
        try await repository.fetchAll()
    }

    func create(_ input: CreateHatcheryInput) async throws -> HatcheryEntity {
        try await repository.create(input)
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

    func waitForFetchToStart() async {
        guard fetchCalls == 0 else { return }
        await withCheckedContinuation { continuation in
            fetchStartedWaiter = continuation
        }
    }

    func finishFetch() {
        finishFetchWaiter?.resume()
        finishFetchWaiter = nil
    }

    func fetchCallCount() -> Int { fetchCalls }
}
