import XCTest
@testable import community_challenge

@MainActor
final class NestFlowTests: XCTestCase {
    /// `.sample` must re-evaluate `Date()` on every access, not bake in
    /// whatever moment the app first touched it as a cached `static let`.
    func testSampleCollectionDateIsToday() {
        let draft = NestFormDraft.sample
        let parsed = AppDateFormatting.parseNestDraftDate(draft.collectionDate)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(
            Calendar.current.startOfDay(for: parsed!),
            Calendar.current.startOfDay(for: Date())
        )
    }

    /// Reproduces the reported bug directly: a brand-new nest, mode already
    /// defaulted to "after X days", untouched by the user. `inspectionDate`
    /// used to sit at whatever the sample struct happened to hardcode --
    /// unrelated to `collectionDate` or `daysAfterCollection` -- until some UI
    /// trigger fired. A fresh draft that never fires one must still resolve
    /// correctly once asked to.
    func testFreshDraftResolvesInspectionDateFromItsOwnDefaults() {
        let controller = makeController()
        XCTAssertEqual(controller.draft.inspectionDateMode, .afterCollectionDays)

        controller.refreshDerivedDates()

        let collection = AppDateFormatting.parseNestDraftDate(controller.draft.collectionDate)!
        let days = Int(controller.draft.daysAfterCollection)!
        let expected = Calendar.current.date(byAdding: .day, value: days, to: collection)!

        XCTAssertEqual(
            controller.draft.inspectionDate,
            AppDateFormatting.nestDraftDateString(expected)
        )
    }

    /// The defensive recompute in `save()` is the actual fix: without it, a
    /// nest saved the instant the timeline screen appears -- before any
    /// onChange/onAppear trigger has run -- would persist whatever
    /// `next_inspection_date` the sample happened to carry, not one derived
    /// from the days the user is looking at on screen.
    func testSavePersistsInspectionDateDerivedFromDaysEvenWithoutAnyUITrigger() async {
        let controller = makeController()
        controller.draft.section = "B2"
        controller.draft.sectionRow = 1
        controller.draft.sectionColumn = 1
        // No updateInspectionDateFromDays(), no onAppear -- exactly the path
        // that shipped the bug.

        let nest = await controller.save()

        let collection = AppDateFormatting.parseNestDraftDate(controller.draft.collectionDate)!
        let days = Int(controller.draft.daysAfterCollection)!
        let expected = Calendar.current.date(byAdding: .day, value: days, to: collection)!

        XCTAssertEqual(
            nest?.nextInspectionDate.map(Calendar.current.startOfDay),
            Calendar.current.startOfDay(for: expected)
        )
    }

    /// Picking a date directly must resolve back into a day count, or
    /// switching to "After X days" afterward silently discards the picked
    /// date and replaces it with whatever stale count was last there.
    func testPickingAnInspectionDateUpdatesTheDayCount() {
        let controller = makeController()
        controller.draft.collectionDate = "01.01.2026"
        controller.draft.inspectionDateMode = .selectDate
        controller.draft.daysAfterCollection = "5" // stale, must not survive
        controller.draft.inspectionDate = "10.01.2026" // 9 days after collection

        controller.updateDaysAfterCollectionFromInspectionDate()

        XCTAssertEqual(controller.draft.daysAfterCollection, "9")
    }

    /// The full round trip the user actually does: pick a date, then flip to
    /// "After X days". The date just picked must survive the switch, not
    /// revert to a leftover count from before.
    func testSwitchingModesAfterPickingADateKeepsThatDate() {
        let controller = makeController()
        controller.draft.collectionDate = "01.01.2026"
        controller.draft.inspectionDateMode = .selectDate
        controller.draft.daysAfterCollection = "5"
        controller.draft.inspectionDate = "10.01.2026"

        // What the date picker's binding does on a pick.
        controller.updateDaysAfterCollectionFromInspectionDate()
        // What the mode buttons do on switching to afterCollectionDays.
        controller.draft.inspectionDateMode = .afterCollectionDays
        controller.updateInspectionDateFromDays()

        XCTAssertEqual(controller.draft.inspectionDate, "10.01.2026")
    }

    /// A picked date earlier than the collection date is not a valid interval;
    /// it must floor at 0 rather than save a negative day count.
    func testInspectionDateBeforeCollectionDateFloorsDaysAtZero() {
        let controller = makeController()
        controller.draft.collectionDate = "10.01.2026"
        controller.draft.inspectionDateMode = .selectDate
        controller.draft.inspectionDate = "01.01.2026"

        controller.updateDaysAfterCollectionFromInspectionDate()

        XCTAssertEqual(controller.draft.daysAfterCollection, "0")
    }

    /// The reverse guard: while "After X days" is what is actually driving the
    /// date, a stray call must not clobber it back down from an inspection
    /// date that is itself only a derived echo.
    func testDayCountIsUntouchedWhileAfterCollectionDaysModeIsActive() {
        let controller = makeController()
        controller.draft.collectionDate = "01.01.2026"
        controller.draft.inspectionDateMode = .afterCollectionDays
        controller.draft.daysAfterCollection = "5"
        controller.draft.inspectionDate = "06.01.2026"

        controller.updateDaysAfterCollectionFromInspectionDate()

        XCTAssertEqual(controller.draft.daysAfterCollection, "5")
    }

    /// The hatch estimate is the collection date plus the incubation period,
    /// and nothing else. It previously used `daysAfterCollection`, which meant
    /// choosing to inspect in 5 days also claimed the eggs would hatch in 5.
    /// The interval is deliberately set to a different value here so the two
    /// cannot be confused again.
    func testEstimatedHatchDateFollowsCollectionDateOnly() {
        let controller = makeController()
        controller.draft.collectionDate = "01.01.2026"
        controller.draft.daysAfterCollection = "5"

        controller.updateEstimatedHatchDate()

        // 01.01.2026 + 59 days of incubation
        XCTAssertEqual(controller.draft.hatchDate, "01.03.2026")
        XCTAssertEqual(NestController.estimatedIncubationDays, 59)
    }

    /// The day count is a free-text numeric field, so a non-number is
    /// reachable. It must leave the scheduled date alone rather than clear it.
    func testInvalidDayCountLeavesTheInspectionDateUntouched() {
        let controller = makeController()
        controller.draft.collectionDate = "01.01.2026"
        controller.draft.inspectionDateMode = .afterCollectionDays
        controller.draft.inspectionDate = "06.01.2026"
        controller.draft.daysAfterCollection = "not a number"

        controller.updateInspectionDateFromDays()

        XCTAssertEqual(controller.draft.inspectionDate, "06.01.2026")
    }

    func testReplaceRouteClearsPriorWizardHistory() {
        let router = NestRouter()
        router.push(.identity)
        router.push(.eggInformation)
        router.push(.preview)

        router.replace(with: .success)

        XCTAssertEqual(router.path, [.success])
    }

    /// Covers the location step rather than the section grid: the grid is now
    /// presented as a sheet and deliberately has no route, so the location
    /// picker is the pushed step this guarantee applies to.
    func testLocationPickerPushAndPopStayInTheTypedNavigationPath() {
        let router = NestRouter()
        router.push(.identity)

        router.push(.locationPicker)
        XCTAssertEqual(router.path, [.identity, .locationPicker])

        router.pop()
        XCTAssertEqual(router.path, [.identity])
    }

    func testResetClearsWizardHistory() {
        let router = NestRouter()
        router.replace(with: .success)

        router.reset()

        XCTAssertTrue(router.path.isEmpty)
    }

    func testNextIdentifierStartsAtOneAndCountsUp() {
        XCTAssertEqual(NestController.nextIdentifier(after: []), "001")
        XCTAssertEqual(NestController.nextIdentifier(after: ["001"]), "002")
        XCTAssertEqual(NestController.nextIdentifier(after: ["055"]), "056")
        // One past the highest, not the count: gaps left by deleted nests must
        // not hand a number back out to a second nest.
        XCTAssertEqual(NestController.nextIdentifier(after: ["001", "010"]), "011")
        XCTAssertEqual(NestController.nextIdentifier(after: ["010", "002"]), "011")
        // Nests saved before numbering, or labelled by hand, are skipped
        // rather than dragging the sequence back to 001.
        XCTAssertEqual(NestController.nextIdentifier(after: [nil, "", "abc", "007"]), "008")
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
                placementRow: 3,
                placementColumn: 4
            )
        )
        XCTAssertEqual(updated.numberOfEggs, 80)
        XCTAssertEqual(updated.placementRow, 3)

        // hatch results are recorded through InspectionService now, so that a
        // hatch always leaves history and clears the inspection schedule;
        // see InspectionAndDeviceTests.

        // validation rejects a nest with no eggs
        await XCTAssertThrowsErrorAsync(
            try await service.updateNest(
                id: created.id,
                UpdateNestInput(
                    numberOfEggs: 0,
                    dateEggsLaid: nil,
                    datePredictedHatch: nil,
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
            ioTDataRepository: InMemoryIoTDataRepository()
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

    /// A hatchery holding nests must not be deletable: the nests would be
    /// orphaned, and nest_hatchery_id_fkey rejects it at the database anyway.
    func testDeletingAHatcheryHoldingNestsIsBlocked() async throws {
        let (hatcheryService, nestService, hatchery) = try await makeLiveishStack()

        _ = try await nestService.createNest(
            CreateNestInput(
                hatcheryID: hatchery.id,
                founderID: nil,
                numberOfEggs: 10,
                dateEggsLaid: nil,
                datePredictedHatch: nil,
                placementRow: 0,
                placementColumn: 0
            )
        )

        do {
            try await hatcheryService.deleteHatchery(id: hatchery.id)
            XCTFail("Expected the delete to be refused while a nest remains")
        } catch let error as DomainValidationError {
            guard case let .hatcheryNotEmpty(nestCount) = error else {
                return XCTFail("Expected .hatcheryNotEmpty, got \(error)")
            }
            XCTAssertEqual(nestCount, 1)
        }

        // still there
        let remaining = try await hatcheryService.hatcheries()
        XCTAssertEqual(remaining.map(\.id), [hatchery.id])
    }

    func testDeletingAnEmptyHatcherySucceeds() async throws {
        let (hatcheryService, _, hatchery) = try await makeLiveishStack()

        try await hatcheryService.deleteHatchery(id: hatchery.id)

        let remaining = try await hatcheryService.hatcheries()
        XCTAssertTrue(remaining.isEmpty)
    }

    /// Shrinking the grid past an existing nest would make it invisible in every
    /// section while still counting in the totals, so it is refused.
    func testResizeThatWouldStrandANestIsBlocked() async throws {
        let (hatcheryService, nestService, hatchery) = try await makeLiveishStack()

        _ = try await nestService.createNest(
            CreateNestInput(
                hatcheryID: hatchery.id,
                founderID: nil,
                numberOfEggs: 10,
                dateEggsLaid: nil,
                datePredictedHatch: nil,
                placementRow: 2,
                placementColumn: 2
            )
        )

        do {
            _ = try await hatcheryService.updateHatchery(
                id: hatchery.id,
                UpdateHatcheryInput(
                    name: hatchery.name,
                    numberOfRows: 2,
                    numberOfColumns: 2,
                    lengthM: 4,
                    widthM: 4
                )
            )
            XCTFail("Expected the resize to be refused")
        } catch let error as DomainValidationError {
            guard case let .resizeWouldStrandNests(count) = error else {
                return XCTFail("Expected .resizeWouldStrandNests, got \(error)")
            }
            XCTAssertEqual(count, 1)
        }
    }

    /// A rename touches no placement, so it is allowed even when the hatchery is
    /// full of nests.
    func testRenameIsAllowedWithNestsPresent() async throws {
        let (hatcheryService, nestService, hatchery) = try await makeLiveishStack()

        _ = try await nestService.createNest(
            CreateNestInput(
                hatcheryID: hatchery.id,
                founderID: nil,
                numberOfEggs: 10,
                dateEggsLaid: nil,
                datePredictedHatch: nil,
                placementRow: 2,
                placementColumn: 2
            )
        )

        let renamed = try await hatcheryService.updateHatchery(
            id: hatchery.id,
            UpdateHatcheryInput(
                name: "Renamed",
                numberOfRows: hatchery.numberOfRows,
                numberOfColumns: hatchery.numberOfColumns,
                lengthM: hatchery.lengthM,
                widthM: hatchery.widthM
            )
        )

        XCTAssertEqual(renamed.name, "Renamed")
        XCTAssertEqual(renamed.numberOfRows, hatchery.numberOfRows)
    }

    /// Shared in-memory stack wired the way AppContainer wires the real one:
    /// one nest repository behind both services.
    private func makeLiveishStack() async throws -> (HatcheryService, NestService, HatcheryEntity) {
        let nestRepository = InMemoryNestRepository()
        let hatcheryService = HatcheryService(
            hatcheryRepository: InMemoryHatcheryRepository(),
            nestRepository: nestRepository,
            ioTDataRepository: InMemoryIoTDataRepository()
        )
        let hatchery = try await hatcheryService.createHatchery(
            CreateHatcheryInput(
                name: "Test hatchery",
                shape: .rectangle,
                numberOfRows: 4,
                numberOfColumns: 4,
                lengthM: 8,
                widthM: 8,
                organizationID: nil
            )
        )
        return (hatcheryService, NestService(repository: nestRepository), hatchery)
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

    // MARK: - Derived timeline dates

    /// The inspection interval used to be discarded: nothing applied it, so
    /// every nest saved in this mode carried whatever date the form started
    /// with, and that column is what schedules the visit.
    @MainActor
    func testDaysAfterCollectionResolvesIntoTheInspectionDate() {
        let controller = makeController()
        controller.draft.collectionDate = "01.01.2026"
        controller.draft.inspectionDateMode = .afterCollectionDays
        controller.draft.daysAfterCollection = "5"

        controller.updateInspectionDateFromDays()

        XCTAssertEqual(controller.draft.inspectionDate, "06.01.2026")
    }

    @MainActor
    func testInspectionDateIsNotDerivedWhileAnExplicitDateIsChosen() {
        let controller = makeController()
        controller.draft.collectionDate = "01.01.2026"
        controller.draft.inspectionDateMode = .selectDate
        controller.draft.inspectionDate = "20.04.2026"
        controller.draft.daysAfterCollection = "5"

        controller.updateInspectionDateFromDays()

        XCTAssertEqual(controller.draft.inspectionDate, "20.04.2026")
    }

    @MainActor
    func testDaysUntilHatchIsCountedFromTodayNotHardcoded() {
        let controller = makeController()
        let inTenDays = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        controller.draft.hatchDate = AppDateFormatting.nestDraftDateString(inTenDays)

        XCTAssertEqual(controller.daysUntilHatchDisplay, "10")
    }

    /// Position in a list is not identity: the same nest used to be numbered
    /// differently depending on which screen opened it.
    func testNestNumberComesFromTheNestNotItsRowPosition() {
        var nest = makeNestDashboardItem().nest
        nest.nestNumber = "055"

        XCTAssertEqual(nest.displayNumber(fallbackOrdinal: 1), "055")

        nest.nestNumber = nil
        XCTAssertEqual(nest.displayNumber(fallbackOrdinal: 1), "001")
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
                successEggsHatch: nil,
                failEggsHatch: nil,
                placementRow: 1,
                placementColumn: 1
            ),
            latestTemperatureC: 30,
            latestBatteryVoltage: nil
        )
    }
}
