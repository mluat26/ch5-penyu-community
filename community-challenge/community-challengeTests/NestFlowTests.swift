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
