import UIKit
import XCTest
@testable import community_challenge

@MainActor
final class HatcheryLayoutPersistenceTests: XCTestCase {
    func testGridSnapshotRoundTripPreservesActiveMaskAndReprojectsBoundary() throws {
        let sourceBoundary = HatcheryBoundary.fullImage
        let sandRegion = try XCTUnwrap(
            HatcherySandRegion(
                points: [
                    NormalizedPoint(x: 0, y: 0),
                    NormalizedPoint(x: 0.66, y: 0),
                    NormalizedPoint(x: 0.66, y: 1),
                    NormalizedPoint(x: 0, y: 1)
                ]
            )
        )
        let grid = try XCTUnwrap(
            HatcheryGridGenerator.generate(
                dimension: HatcheryDimension(widthM: 6, heightM: 4),
                boundary: sourceBoundary,
                sandRegion: sandRegion
            )
        )

        let encoded = try JSONEncoder().encode(HatcheryGridSnapshot(grid: grid))
        let snapshot = try JSONDecoder().decode(HatcheryGridSnapshot.self, from: encoded)
        let restoredBoundary = HatcheryBoundary(
            topLeft: NormalizedPoint(x: 0.18, y: 0.21),
            topRight: NormalizedPoint(x: 0.82, y: 0.15),
            bottomRight: NormalizedPoint(x: 0.91, y: 0.83),
            bottomLeft: NormalizedPoint(x: 0.09, y: 0.78)
        )

        let restored = try snapshot.makeGrid(boundary: restoredBoundary)

        XCTAssertEqual(restored.rows, 2)
        XCTAssertEqual(restored.columns, 3)
        XCTAssertEqual(
            restored.sections.filter(\.isActive).map { "\($0.row),\($0.column)" },
            ["0,0", "0,1", "1,0", "1,1"]
        )
        XCTAssertFalse(restored.isSectionActive(row: 0, column: 2))
        XCTAssertEqual(
            restored.sections.first?.boundary,
            restoredBoundary.sectionBoundary(row: 0, column: 0, rowCount: 2, columnCount: 3)
        )
    }

    func testGridSnapshotRejectsDuplicateCoordinates() {
        let snapshot = HatcheryGridSnapshot(
            rows: 2,
            columns: 2,
            sectionWidthM: 2,
            sectionHeightM: 2,
            activeCells: [
                HatcheryGridCellCoordinate(row: 0, column: 0),
                HatcheryGridCellCoordinate(row: 0, column: 0)
            ]
        )

        XCTAssertThrowsError(try snapshot.makeGrid(boundary: .fullImage)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                HatcheryLayoutPersistenceError.invalidGridSnapshot.localizedDescription
            )
        }
    }

    func testNewCapturedLayoutUploadsThenFinalizes() async throws {
        let hatcheryID = UUID()
        let request = makeRequest(
            hatcheryID: hatcheryID,
            sourcePhoto: HatcherySourcePhoto(
                data: Data([1, 2, 3, 4]),
                width: 2,
                height: 2
            )
        )
        let pending = makeRevision(
            id: request.layoutID,
            hatcheryID: hatcheryID,
            state: .uploading,
            captureMode: .captured,
            isCurrent: false,
            sourcePhotoPath: "\(hatcheryID.uuidString.lowercased())/\(request.layoutID.uuidString.lowercased())/source.jpg",
            photoMetadataIsPresent: false
        )
        let ready = makeRevision(
            id: request.layoutID,
            hatcheryID: hatcheryID,
            state: .ready,
            captureMode: .captured,
            isCurrent: true,
            sourcePhotoPath: pending.sourcePhotoPath,
            photoMetadataIsPresent: true
        )
        let repository = LayoutRepositorySpy(pending: pending, finalized: ready)
        let photoStore = PhotoStoreSpy()
        let service = HatcheryLayoutService(repository: repository, photoStore: photoStore)

        let saved = try await service.createNewHatchery(request)

        XCTAssertEqual(saved, ready)
        let repositoryOperations = await repository.operations()
        XCTAssertEqual(repositoryOperations, ["beginNew", "finalize"])
        let photoStoreOperations = await photoStore.operations()
        XCTAssertEqual(
            photoStoreOperations,
            ["upload:\(pending.sourcePhotoPath ?? "")"]
        )
    }

    func testFailedFinalizationCleansUpUploadedPhotoAndPendingRevision() async {
        let hatcheryID = UUID()
        let request = makeRequest(
            hatcheryID: hatcheryID,
            sourcePhoto: HatcherySourcePhoto(
                data: Data([9, 8, 7]),
                width: 1,
                height: 3
            )
        )
        let pending = makeRevision(
            id: request.layoutID,
            hatcheryID: hatcheryID,
            state: .uploading,
            captureMode: .captured,
            isCurrent: false,
            sourcePhotoPath: "\(hatcheryID.uuidString.lowercased())/\(request.layoutID.uuidString.lowercased())/source.jpg",
            photoMetadataIsPresent: false
        )
        let failed = makeRevision(
            id: request.layoutID,
            hatcheryID: hatcheryID,
            state: .failed,
            captureMode: .captured,
            isCurrent: false,
            sourcePhotoPath: pending.sourcePhotoPath,
            photoMetadataIsPresent: false
        )
        let repository = LayoutRepositorySpy(
            pending: pending,
            finalized: nil,
            finalizeError: LayoutTestError.finalizationFailed,
            abandoned: failed
        )
        let photoStore = PhotoStoreSpy()
        let service = HatcheryLayoutService(repository: repository, photoStore: photoStore)

        do {
            _ = try await service.save(request)
            XCTFail("Expected finalization to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, LayoutTestError.finalizationFailed.localizedDescription)
        }

        let repositoryOperations = await repository.operations()
        XCTAssertEqual(
            repositoryOperations,
            ["begin", "finalize", "fetch", "abandon", "purgeFailed"]
        )
        let photoStoreOperations = await photoStore.operations()
        XCTAssertEqual(
            photoStoreOperations,
            [
                "upload:\(pending.sourcePhotoPath ?? "")",
                "delete:\(pending.sourcePhotoPath ?? "")"
            ]
        )
    }

    func testAmbiguousFinalizationKeepsThePhotoWhenTheServerFinishedFirst() async throws {
        let hatcheryID = UUID()
        let request = makeRequest(
            hatcheryID: hatcheryID,
            sourcePhoto: HatcherySourcePhoto(
                data: Data([4, 2]),
                width: 1,
                height: 2
            )
        )
        let pending = makeRevision(
            id: request.layoutID,
            hatcheryID: hatcheryID,
            state: .uploading,
            captureMode: .captured,
            isCurrent: false,
            sourcePhotoPath: "\(hatcheryID.uuidString.lowercased())/\(request.layoutID.uuidString.lowercased())/source.jpg",
            photoMetadataIsPresent: false
        )
        let ready = makeRevision(
            id: request.layoutID,
            hatcheryID: hatcheryID,
            state: .ready,
            captureMode: .captured,
            isCurrent: true,
            sourcePhotoPath: pending.sourcePhotoPath,
            photoMetadataIsPresent: true
        )
        let repository = LayoutRepositorySpy(
            pending: pending,
            finalized: nil,
            finalizeError: LayoutTestError.finalizationFailed,
            abandoned: ready
        )
        let photoStore = PhotoStoreSpy()
        let service = HatcheryLayoutService(repository: repository, photoStore: photoStore)

        let saved = try await service.save(request)

        XCTAssertEqual(saved, ready)
        let repositoryOperations = await repository.operations()
        XCTAssertEqual(repositoryOperations, ["begin", "finalize", "fetch", "abandon"])
        let photoStoreOperations = await photoStore.operations()
        XCTAssertEqual(photoStoreOperations, ["upload:\(pending.sourcePhotoPath ?? "")"])
    }

    func testSkippedLayoutFinalizesWithoutUploadingAFakePhoto() async throws {
        let hatcheryID = UUID()
        let request = makeRequest(hatcheryID: hatcheryID, sourcePhoto: nil)
        let pending = makeRevision(
            id: request.layoutID,
            hatcheryID: hatcheryID,
            state: .uploading,
            captureMode: .skipped,
            isCurrent: false,
            sourcePhotoPath: nil,
            photoMetadataIsPresent: false
        )
        let ready = makeRevision(
            id: request.layoutID,
            hatcheryID: hatcheryID,
            state: .ready,
            captureMode: .skipped,
            isCurrent: true,
            sourcePhotoPath: nil,
            photoMetadataIsPresent: false
        )
        let repository = LayoutRepositorySpy(pending: pending, finalized: ready)
        let photoStore = PhotoStoreSpy()
        let service = HatcheryLayoutService(repository: repository, photoStore: photoStore)

        let saved = try await service.save(request)

        XCTAssertEqual(saved.captureMode, .skipped)
        XCTAssertNil(saved.sourcePhotoPath)
        let photoStoreOperations = await photoStore.operations()
        XCTAssertTrue(photoStoreOperations.isEmpty)
    }

    func testPersistedCapturedLayoutRestoresPhotoAndExactGrid() async throws {
        let hatcheryID = UUID()
        let request = makeRequest(hatcheryID: hatcheryID, sourcePhoto: nil)
        let layout = makeRevision(
            id: request.layoutID,
            hatcheryID: hatcheryID,
            state: .ready,
            captureMode: .captured,
            isCurrent: true,
            sourcePhotoPath: "\(hatcheryID.uuidString.lowercased())/\(request.layoutID.uuidString.lowercased())/source.jpg",
            photoMetadataIsPresent: true
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 12, height: 8),
            format: format
        ).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        }
        let imageData = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        let hatchery = HatcheryEntity(
            id: hatcheryID,
            name: layout.name,
            shape: .rectangle,
            numberOfRows: layout.grid.rows,
            numberOfColumns: layout.grid.columns,
            lengthM: layout.dimension.heightM,
            widthM: layout.dimension.widthM,
            organizationID: nil
        )

        let session = try await HatcherySessionState.reconstructed(
            from: hatchery,
            layout: layout,
            sourcePhotoData: imageData
        )

        XCTAssertEqual(session.photo.size, CGSize(width: 12, height: 8))
        XCTAssertFalse(session.usesMockImage)
        XCTAssertEqual(session.grid.sections.filter(\.isActive).count, layout.grid.activeCells.count)
        XCTAssertEqual(session.sandRegion, layout.sandRegion)
    }

    func testSourcePhotoPreparationDownsamplesBeforeUpload() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 2_500, height: 1_250),
            format: format
        ).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_500, height: 1_250))
        }

        let payload = try HatcheryImageProcessor.payload(from: image)
        let sourcePhoto = try await HatcheryImageProcessor.sourcePhoto(from: payload)

        XCTAssertEqual(sourcePhoto.width, 2_048)
        XCTAssertEqual(sourcePhoto.height, 1_024)
        XCTAssertFalse(sourcePhoto.data.isEmpty)
    }

    func testLayoutCreationBuildsSessionFromFinalizedRevisionWithoutParentFetch() async throws {
        let hatcheryID = UUID()
        let layoutID = UUID()
        let pending = makeRevision(
            id: layoutID,
            hatcheryID: hatcheryID,
            state: .uploading,
            captureMode: .skipped,
            isCurrent: false,
            sourcePhotoPath: nil,
            photoMetadataIsPresent: false
        )
        let ready = makeRevision(
            id: layoutID,
            hatcheryID: hatcheryID,
            state: .ready,
            captureMode: .skipped,
            isCurrent: true,
            sourcePhotoPath: nil,
            photoMetadataIsPresent: false
        )
        let layoutRepository = LayoutRepositorySpy(pending: pending, finalized: ready)
        let layoutService = HatcheryLayoutService(
            repository: layoutRepository,
            photoStore: PhotoStoreSpy()
        )
        let hatcheryRepository = UnexpectedFetchHatcheryRepository()
        let controller = HatcherySetupController(
            hatcheryService: HatcheryService(
                hatcheryRepository: hatcheryRepository,
                nestRepository: InMemoryNestRepository(),
                telemetryRepository: InMemoryTelemetryRepository()
            ),
            layoutService: layoutService
        )

        controller.setName("Hatch_01")
        controller.skipScanning()
        XCTAssertTrue(
            controller.generateGrid(
                for: HatcheryDimension(widthM: 6, heightM: 4)
            )
        )

        let session = await controller.completeSetup()
        let fetchCallCount = await hatcheryRepository.fetchCallCount()
        let operations = await layoutRepository.operations()

        XCTAssertNotNil(session)
        XCTAssertEqual(session?.hatchery.name, ready.name)
        XCTAssertEqual(session?.hatchery.numberOfRows, ready.grid.rows)
        XCTAssertEqual(session?.hatchery.numberOfColumns, ready.grid.columns)
        XCTAssertEqual(session?.hatchery.lengthM, ready.dimension.heightM)
        XCTAssertEqual(session?.hatchery.widthM, ready.dimension.widthM)
        XCTAssertEqual(fetchCallCount, 0)
        XCTAssertEqual(operations, ["beginNew", "finalize"])
    }

    private func makeRequest(
        hatcheryID: UUID,
        sourcePhoto: HatcherySourcePhoto?
    ) -> HatcheryLayoutSaveRequest {
        let boundary = HatcheryBoundary.fullImage
        let grid = HatcheryGridSnapshot(
            rows: 2,
            columns: 3,
            sectionWidthM: 2,
            sectionHeightM: 2,
            activeCells: [
                HatcheryGridCellCoordinate(row: 0, column: 0),
                HatcheryGridCellCoordinate(row: 0, column: 1),
                HatcheryGridCellCoordinate(row: 1, column: 0),
                HatcheryGridCellCoordinate(row: 1, column: 1)
            ]
        )
        return HatcheryLayoutSaveRequest(
            hatcheryID: hatcheryID,
            name: "Hatch_01",
            dimension: HatcheryDimension(widthM: 6, heightM: 4),
            boundary: boundary,
            sandRegion: HatcherySandRegion.default(from: boundary),
            grid: grid,
            processingVersion: "test-v1",
            sourcePhoto: sourcePhoto
        )
    }

    private func makeRevision(
        id: UUID,
        hatcheryID: UUID,
        state: HatcheryLayoutRevisionState,
        captureMode: HatcheryCaptureMode,
        isCurrent: Bool,
        sourcePhotoPath: String?,
        photoMetadataIsPresent: Bool
    ) -> HatcheryLayoutRevision {
        let request = makeRequest(hatcheryID: hatcheryID, sourcePhoto: nil)
        return HatcheryLayoutRevision(
            id: id,
            hatcheryID: hatcheryID,
            revision: 1,
            createdBy: UUID(),
            state: state,
            isCurrent: isCurrent,
            captureMode: captureMode,
            sourcePhotoPath: sourcePhotoPath,
            sourcePhotoMIMEType: photoMetadataIsPresent ? HatcherySourcePhoto.jpegMIMEType : nil,
            sourcePhotoBytes: photoMetadataIsPresent ? 4 : nil,
            sourcePhotoWidth: photoMetadataIsPresent ? 2 : nil,
            sourcePhotoHeight: photoMetadataIsPresent ? 2 : nil,
            name: request.name,
            dimension: request.dimension,
            grid: request.grid,
            boundary: request.boundary,
            sandRegion: request.sandRegion,
            layoutSchemaVersion: HatcheryGridSnapshot.currentSchemaVersion,
            processingVersion: request.processingVersion,
            createdAt: Date(timeIntervalSince1970: 0),
            finalizedAt: state == .ready ? Date(timeIntervalSince1970: 1) : nil,
            supersededAt: nil
        )
    }
}

private enum LayoutTestError: LocalizedError {
    case finalizationFailed

    var errorDescription: String? { "Could not finalize test layout" }
}

private actor LayoutRepositorySpy: HatcheryLayoutRepository {
    private let pending: HatcheryLayoutRevision
    private let finalized: HatcheryLayoutRevision?
    private let finalizeError: Error?
    private let abandoned: HatcheryLayoutRevision?
    private var callLog: [String] = []
    private var newHatcheryID: UUID?

    init(
        pending: HatcheryLayoutRevision,
        finalized: HatcheryLayoutRevision?,
        finalizeError: Error? = nil,
        abandoned: HatcheryLayoutRevision? = nil
    ) {
        self.pending = pending
        self.finalized = finalized
        self.finalizeError = finalizeError
        self.abandoned = abandoned
    }

    func fetchCurrent(hatcheryID: UUID) async throws -> HatcheryLayoutRevision? { nil }

    func fetch(id: UUID) async throws -> HatcheryLayoutRevision? {
        callLog.append("fetch")
        return nil
    }

    func begin(_ request: HatcheryLayoutSaveRequest) async throws -> HatcheryLayoutRevision {
        callLog.append("begin")
        return pending
    }

    func beginNewHatchery(
        _ request: HatcheryLayoutSaveRequest
    ) async throws -> HatcheryLayoutRevision {
        callLog.append("beginNew")
        newHatcheryID = request.hatcheryID
        return pending.withHatcheryID(request.hatcheryID)
    }

    func finalize(
        layoutID: UUID,
        sourcePhoto: HatcherySourcePhoto?
    ) async throws -> HatcheryLayoutRevision {
        callLog.append("finalize")
        if let finalizeError { throw finalizeError }
        guard let finalized else { throw LayoutTestError.finalizationFailed }
        guard let newHatcheryID else { return finalized }
        return finalized.withHatcheryID(newHatcheryID)
    }

    func abandon(layoutID: UUID) async throws -> HatcheryLayoutRevision {
        callLog.append("abandon")
        return abandoned ?? pending
    }

    func purgeFailed(layoutID: UUID) async throws {
        callLog.append("purgeFailed")
    }

    func operations() -> [String] { callLog }
}

private extension HatcheryLayoutRevision {
    nonisolated func withHatcheryID(_ hatcheryID: UUID) -> HatcheryLayoutRevision {
        HatcheryLayoutRevision(
            id: id,
            hatcheryID: hatcheryID,
            revision: revision,
            createdBy: createdBy,
            state: state,
            isCurrent: isCurrent,
            captureMode: captureMode,
            sourcePhotoPath: sourcePhotoPath,
            sourcePhotoMIMEType: sourcePhotoMIMEType,
            sourcePhotoBytes: sourcePhotoBytes,
            sourcePhotoWidth: sourcePhotoWidth,
            sourcePhotoHeight: sourcePhotoHeight,
            name: name,
            dimension: dimension,
            grid: grid,
            boundary: boundary,
            sandRegion: sandRegion,
            layoutSchemaVersion: layoutSchemaVersion,
            processingVersion: processingVersion,
            createdAt: createdAt,
            finalizedAt: finalizedAt,
            supersededAt: supersededAt
        )
    }
}

private actor PhotoStoreSpy: HatcheryPhotoStore {
    private var callLog: [String] = []

    func upload(path: String, data: Data, contentType: String) async throws {
        callLog.append("upload:\(path)")
    }

    func download(path: String) async throws -> Data {
        Data()
    }

    func delete(path: String) async throws {
        callLog.append("delete:\(path)")
    }

    func operations() -> [String] { callLog }
}

/// The layout finalize response should be enough to enter the session. This
/// fake turns a future success-path hatchery GET back into a test failure.
private actor UnexpectedFetchHatcheryRepository: HatcheryRepository {
    private var fetchCalls = 0

    func fetch(id: UUID) async throws -> HatcheryEntity {
        fetchCalls += 1
        throw RepositoryError.notFound(resource: "Hatchery", id: id)
    }

    func fetchAll() async throws -> [HatcheryEntity] { [] }

    func create(_ input: CreateHatcheryInput) async throws -> HatcheryEntity {
        throw RepositoryError.notFound(resource: "Hatchery", id: UUID())
    }

    func update(
        id: UUID,
        _ input: UpdateHatcheryInput
    ) async throws -> HatcheryEntity {
        throw RepositoryError.notFound(resource: "Hatchery", id: id)
    }

    func delete(id: UUID) async throws {}

    func fetchCallCount() -> Int { fetchCalls }
}
