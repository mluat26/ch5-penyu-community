import XCTest
@testable import community_challenge

@MainActor
final class NestFlowTests: XCTestCase {
    func testEstimatedHatchDateTracksCollectionDateAndOffset() {
        let controller = makeController()
        controller.draft.collectionDate = "01.01.2026"
        controller.draft.daysAfterCollection = "59"

        controller.updateEstimatedHatchDate()

        XCTAssertEqual(controller.draft.hatchDate, "01.03.2026")
    }

    func testInvalidOffsetLeavesCurrentEstimatedHatchDateUntouched() {
        let controller = makeController()
        controller.draft.hatchDate = "01.03.2026"
        controller.draft.daysAfterCollection = "not a number"

        controller.updateEstimatedHatchDate()

        XCTAssertEqual(controller.draft.hatchDate, "01.03.2026")
    }

    func testReplaceRouteClearsPriorWizardHistory() {
        let router = NestRouter()
        router.push(.identity)
        router.push(.eggInformation)
        router.push(.preview)

        router.replace(with: .success)

        XCTAssertEqual(router.path, [.success])
    }

    func testSectionPickerPushAndPopStayInTheTypedNavigationPath() {
        let router = NestRouter()
        router.push(.identity)

        router.push(.sectionPicker)
        XCTAssertEqual(router.path, [.identity, .sectionPicker])

        router.pop()
        XCTAssertEqual(router.path, [.identity])
    }

    func testSuccessCanNavigateToSavedNestDetail() {
        let router = NestRouter()
        let item = makeNestDashboardItem()

        router.replace(with: .success)
        router.push(.nestDetail(item: item, ordinal: 1, sectionID: "B2"))

        XCTAssertEqual(
            router.path,
            [
                .success,
                .nestDetail(item: item, ordinal: 1, sectionID: "B2")
            ]
        )

        router.pop()
        XCTAssertEqual(router.path, [.success])
    }

    func testResetClearsNestedNavigationDestinations() {
        let router = NestRouter()
        let item = makeNestDashboardItem()
        router.replace(with: .success)
        router.push(.nestDetail(item: item, ordinal: 55, sectionID: "B2"))

        router.reset()

        XCTAssertTrue(router.path.isEmpty)
    }

    func testSavePersistsSelectedGridPlacement() async {
        let controller = makeController()
        controller.draft.section = "B2"
        controller.draft.sectionRow = 1
        controller.draft.sectionColumn = 1

        let nest = await controller.save()

        XCTAssertEqual(nest?.placementRow, 1)
        XCTAssertEqual(nest?.placementColumn, 1)
        XCTAssertEqual(controller.lastSavedNest?.sectionKey, "1-1")
    }

    func testNestServiceCRUDRoundTrip() async throws {
        let service = NestService(repository: InMemoryNestRepository())
        let hatcheryID = UUID()

        // create
        let created = try await service.createNest(
            CreateNestInput(
                hatcheryID: hatcheryID,
                founderID: nil,
                numberOfEggs: 100,
                dateEggsLaid: nil,
                datePredictedHatch: nil,
                placeEggsLaid: nil,
                placementRow: 1,
                placementColumn: 2
            )
        )
        XCTAssertEqual(created.numberOfEggs, 100)

        // read
        let fetched = try await service.nest(id: created.id)
        XCTAssertEqual(fetched.id, created.id)
        let all = try await service.nests(hatcheryID: hatcheryID)
        XCTAssertEqual(all.map(\.id), [created.id])

        // update
        let updated = try await service.updateNest(
            id: created.id,
            UpdateNestInput(
                numberOfEggs: 80,
                dateEggsLaid: nil,
                datePredictedHatch: nil,
                placeEggsLaid: nil,
                placementRow: 3,
                placementColumn: 4
            )
        )
        XCTAssertEqual(updated.numberOfEggs, 80)
        XCTAssertEqual(updated.placementRow, 3)

        // hatch result
        let hatched = try await service.recordHatchResult(
            nestID: created.id,
            input: RecordHatchResultInput(successEggsHatch: 70, failEggsHatch: 10)
        )
        XCTAssertEqual(hatched.successEggsHatch, 70)

        // validation rejects a nest with no eggs
        await XCTAssertThrowsErrorAsync(
            try await service.updateNest(
                id: created.id,
                UpdateNestInput(
                    numberOfEggs: 0,
                    dateEggsLaid: nil,
                    datePredictedHatch: nil,
                    placeEggsLaid: nil,
                    placementRow: nil,
                    placementColumn: nil
                )
            )
        )

        // delete, and deleting twice is an error
        try await service.deleteNest(id: created.id)
        await XCTAssertThrowsErrorAsync(try await service.nest(id: created.id))
        await XCTAssertThrowsErrorAsync(try await service.deleteNest(id: created.id))
    }

    /// A nest written through NestService must come back out of the dashboard
    /// HatcheryService builds, in the section it was placed in. This is the
    /// wiring AppContainer relies on by sharing one nest repository instance.
    func testNestSavedThroughServiceAppearsInHatcheryDashboard() async throws {
        let nestRepository = InMemoryNestRepository()
        let hatcheryRepository = InMemoryHatcheryRepository()
        let hatcheryService = HatcheryService(
            hatcheryRepository: hatcheryRepository,
            nestRepository: nestRepository,
            telemetryRepository: InMemoryTelemetryRepository()
        )
        let nestService = NestService(repository: nestRepository)

        let hatchery = try await hatcheryService.createHatchery(
            CreateHatcheryInput(
                name: "Test hatchery",
                shape: .rectangle,
                numberOfRows: 2,
                numberOfColumns: 2,
                lengthM: 10,
                widthM: 8,
                organizationID: nil
            )
        )

        let emptyDashboard = try await hatcheryService.loadDashboard(hatcheryID: hatchery.id)
        XCTAssertEqual(emptyDashboard.overview.nestCount, 0)

        let created = try await nestService.createNest(
            CreateNestInput(
                hatcheryID: hatchery.id,
                founderID: nil,
                numberOfEggs: 42,
                dateEggsLaid: Date(),
                datePredictedHatch: nil,
                placeEggsLaid: nil,
                placementRow: 1,
                placementColumn: 0
            )
        )

        let dashboard = try await hatcheryService.loadDashboard(hatcheryID: hatchery.id)
        XCTAssertEqual(dashboard.overview.nestCount, 1)
        XCTAssertEqual(dashboard.overview.totalEggs, 42)

        // the nest lands in the section it was placed in, and nowhere else
        let section = dashboard.section(row: 1, column: 0)
        XCTAssertEqual(section?.nests.map(\.id), [created.id])
        XCTAssertEqual(section?.nestCount, 1)
        XCTAssertEqual(section?.totalEggs, 42)
        XCTAssertEqual(dashboard.section(row: 0, column: 0)?.nests.count, 0)

        // no sensor is paired to a new nest, so it has no temperature
        XCTAssertNil(section?.nests.first?.latestTemperatureC)

        // and a delete round-trips back out of the dashboard
        try await nestService.deleteNest(id: created.id)
        let afterDelete = try await hatcheryService.loadDashboard(hatcheryID: hatchery.id)
        XCTAssertEqual(afterDelete.overview.nestCount, 0)
    }

    private func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected an error but none was thrown", file: file, line: line)
        } catch {}
    }

    private func makeController() -> NestController {
        NestController(
            hatcheryID: UUID(),
            nestService: NestService(repository: InMemoryNestRepository())
        )
    }

    private func makeNestDashboardItem() -> NestDashboardItem {
        NestDashboardItem(
            nest: NestEntity(
                id: UUID(),
                hatcheryID: UUID(),
                founderID: nil,
                numberOfEggs: 100,
                dateEggsLaid: nil,
                datePredictedHatch: nil,
                placeEggsLaid: nil,
                successEggsHatch: nil,
                failEggsHatch: nil,
                placementRow: 1,
                placementColumn: 1
            ),
            latestTemperatureC: 30
        )
    }
}
