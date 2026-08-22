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

    // MARK: - Deletion

    private func makeDeletionFixture(
        withNest: Bool
    ) async throws -> (
        controller: HatcheryListController,
        hatchery: HatcheryEntity,
        hatcheryRepository: InMemoryHatcheryRepository,
        photoStore: DeletionPhotoStoreSpy
    ) {
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
        let hatcheryRepository = InMemoryHatcheryRepository(seed: [hatchery])
        let nestRepository = InMemoryNestRepository()

        if withNest {
            _ = try await nestRepository.create(
                CreateNestInput(
                    hatcheryID: hatchery.id,
                    founderID: nil,
                    numberOfEggs: 100,
                    dateEggsLaid: nil,
                    datePredictedHatch: nil,
                    placementRow: 1,
                    placementColumn: 2
                )
            )
        }

        let photoStore = DeletionPhotoStoreSpy()
        let controller = HatcheryListController(
            hatcheryService: HatcheryService(
                hatcheryRepository: hatcheryRepository,
                nestRepository: nestRepository,
                ioTDataRepository: InMemoryIoTDataRepository()
            ),
            layoutService: HatcheryLayoutService(
                repository: DeletionLayoutRepositoryStub(
                    photoPaths: ["\(hatchery.id)/one/source.jpg"]
                ),
                photoStore: photoStore
            )
        )

        return (controller, hatchery, hatcheryRepository, photoStore)
    }

    /// The routing decision the root makes after a delete -- open the next
    /// hatchery, or show "Let's get started" -- reads this list on the very
    /// next render, so it has to be right before any reload returns.
    func testForgettingAHatcheryUpdatesTheListSynchronously() async {
        let first = HatcheryEntity(
            id: UUID(),
            name: "Hatch_01",
            shape: .rectangle,
            numberOfRows: 3,
            numberOfColumns: 4,
            lengthM: 5,
            widthM: 4,
            organizationID: nil
        )
        let second = HatcheryEntity(
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
                hatcheryRepository: InMemoryHatcheryRepository(seed: [first, second]),
                nestRepository: InMemoryNestRepository(),
                ioTDataRepository: InMemoryIoTDataRepository()
            )
        )
        await controller.loadManagement()

        controller.forget(hatcheryID: first.id)

        XCTAssertEqual(controller.hatcheries.map(\.id), [second.id])
        XCTAssertEqual(controller.managementSummaries.map(\.id), [second.id])

        controller.forget(hatcheryID: second.id)

        XCTAssertTrue(controller.hatcheries.isEmpty)
        XCTAssertTrue(controller.managementSummaries.isEmpty)
    }

    func testDeletingAnEmptyHatcheryRemovesItsPhotosAndItsRow() async throws {
        let fixture = try await makeDeletionFixture(withNest: false)

        let deleted = await fixture.controller.delete(fixture.hatchery)

        XCTAssertTrue(deleted)
        XCTAssertNil(fixture.controller.errorMessage)
        let remaining = try await fixture.hatcheryRepository.fetchAll()
        XCTAssertTrue(remaining.isEmpty)
        let photoOperations = await fixture.photoStore.operations()
        XCTAssertEqual(photoOperations, ["delete:\(fixture.hatchery.id)/one/source.jpg"])
    }

    /// The ordering is the point. Photo removal is irreversible and the row is
    /// not going anywhere, so a refusal has to land before anything is deleted
    /// from Storage -- otherwise a hatchery that survives loses its scan.
    func testRefusingToDeleteAHatcheryWithNestsRemovesNoPhotos() async throws {
        let fixture = try await makeDeletionFixture(withNest: true)

        let deleted = await fixture.controller.delete(fixture.hatchery)

        XCTAssertFalse(deleted)
        XCTAssertEqual(
            fixture.controller.errorMessage,
            DomainValidationError.hatcheryNotEmpty(nestCount: 1).localizedDescription
        )
        let remaining = try await fixture.hatcheryRepository.fetchAll()
        XCTAssertEqual(remaining.map(\.id), [fixture.hatchery.id])
        let photoOperations = await fixture.photoStore.operations()
        XCTAssertTrue(photoOperations.isEmpty)
    }
}

/// Only the two members deletion reaches. Everything else on the protocol
/// belongs to the scan lifecycle, which this test never enters.
private actor DeletionLayoutRepositoryStub: HatcheryLayoutRepository {
    private let photoPaths: [String]

    init(photoPaths: [String]) {
        self.photoPaths = photoPaths
    }

    func photoPaths(hatcheryID: UUID) async throws -> [String] { photoPaths }
    func currentUserPhotoPaths() async throws -> [String] { photoPaths }

    func fetchCurrent(hatcheryID: UUID) async throws -> HatcheryLayoutRevision? { nil }
    func fetch(id: UUID) async throws -> HatcheryLayoutRevision? { nil }
    func begin(_ request: HatcheryLayoutSaveRequest) async throws -> HatcheryLayoutRevision {
        fatalError("Deletion never begins a layout")
    }
    func beginNewHatchery(
        _ request: HatcheryLayoutSaveRequest
    ) async throws -> HatcheryLayoutRevision {
        fatalError("Deletion never begins a layout")
    }
    func finalize(
        layoutID: UUID,
        sourcePhoto: HatcherySourcePhoto?
    ) async throws -> HatcheryLayoutRevision {
        fatalError("Deletion never finalizes a layout")
    }
    func abandon(layoutID: UUID) async throws -> HatcheryLayoutRevision {
        fatalError("Deletion never abandons a layout")
    }
    func purgeFailed(layoutID: UUID) async throws {}
}

private actor DeletionPhotoStoreSpy: HatcheryPhotoStore {
    private var callLog: [String] = []

    func upload(path: String, data: Data, contentType: String) async throws {
        callLog.append("upload:\(path)")
    }

    func download(path: String) async throws -> Data { Data() }

    func delete(path: String) async throws {
        callLog.append("delete:\(path)")
    }

    func operations() -> [String] { callLog }
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
