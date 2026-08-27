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

        // 01.01.2026 + 56 days of incubation
        XCTAssertEqual(controller.draft.hatchDate, "26.02.2026")
        XCTAssertEqual(NestController.estimatedIncubationDays, 56)
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

    func testIdentityNeedsBothASectionAndAPin() {
        let controller = makeController()

        // A fresh draft has neither, and both must say so at once -- a screen
        // that only complained about the first would send the ranger round
        // twice.
        XCTAssertTrue(controller.isSectionMissing)
        XCTAssertTrue(controller.isLocationMissing)
        XCTAssertFalse(controller.validateIdentity())

        controller.draft.section = "B2"
        controller.draft.sectionRow = 1
        controller.draft.sectionColumn = 1

        // The section's own message must stop showing the moment it is filled,
        // while the location's keeps showing.
        XCTAssertFalse(controller.isSectionMissing)
        XCTAssertTrue(controller.isLocationMissing)
        XCTAssertFalse(controller.validateIdentity(), "a pin is required, not optional")

        controller.draft.latitude = -8.7
        controller.draft.longitude = 115.17

        XCTAssertFalse(controller.isLocationMissing)
        XCTAssertTrue(controller.validateIdentity())
    }

    func testValidatingIdentityLeavesNoMessageBehind() {
        let controller = makeController()

        _ = controller.validateIdentity()

        // The old version wrote into `errorMessage`, which nothing cleared once
        // the field was filled, so the complaint outlived the problem.
        XCTAssertNil(controller.errorMessage)
    }

    func testStepperReturnsToAnEarlierPageAndDropsWhatWasAbove() {
        let router = NestRouter()
        router.push(.connectBucket)
        router.push(.identity)
        router.push(.eggInformation)

        router.popTo(.identity)

        XCTAssertEqual(router.path, [.connectBucket, .identity])

        // A step that is not on the path must not unwind the flow.
        router.popTo(.preview)
        XCTAssertEqual(router.path, [.connectBucket, .identity])

        // Returning to the page already showing is a no-op, not a pop.
        router.popTo(.identity)
        XCTAssertEqual(router.path, [.connectBucket, .identity])
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

    /// The registration screen reads its temperature from the nest it just
    /// saved, never from the hatchery average.
    ///
    /// It used to show `overview.averageTemperatureC ?? 30`, so a brand-new
    /// nest -- which has no reading of its own, because its logger has not
    /// reported yet -- displayed the neighbouring nests' average, or a flat 30
    /// when the hatchery had no readings at all. Both land in the optimal band,
    /// so a nest nothing had ever measured announced itself as healthy.
    func testNewNestReadsItsOwnTemperatureNotTheHatcheryAverage() async throws {
        let nestRepository = InMemoryNestRepository()
        let hatcheryRepository = InMemoryHatcheryRepository()
        let ioTDataRepository = InMemoryIoTDataRepository()
        let hatcheryService = HatcheryService(
            hatcheryRepository: hatcheryRepository,
            nestRepository: nestRepository,
            ioTDataRepository: ioTDataRepository
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

        func addNest(row: Int, column: Int) async throws -> NestEntity {
            try await nestService.createNest(
                CreateNestInput(
                    hatcheryID: hatchery.id,
                    founderID: nil,
                    numberOfEggs: 42,
                    dateEggsLaid: Date(),
                    datePredictedHatch: nil,
                    placementRow: row,
                    placementColumn: column
                )
            )
        }

        // An established nest that has been reporting, and the one just
        // registered alongside it.
        let reporting = try await addNest(row: 0, column: 0)
        let justRegistered = try await addNest(row: 1, column: 0)

        await ioTDataRepository.seed([
            IoTDataEntity(
                id: UUID(),
                nestID: reporting.id,
                sensorID: nil,
                position: nil,
                depthCM: nil,
                temperatureC: 30,
                timestamp: Date(),
                alert: nil,
                sensorStatus: nil,
                batteryVoltage: 3.9,
                signalRSSIDBM: nil
            )
        ])

        let dashboard = try await hatcheryService.loadDashboard(hatcheryID: hatchery.id)

        // The average exists and is optimal -- exactly the value the old code
        // would have handed the success screen.
        XCTAssertEqual(dashboard.overview.averageTemperatureC, 30)

        // The nest that reported resolves its own reading...
        XCTAssertEqual(dashboard.nest(id: reporting.id)?.latestTemperatureC, 30)
        XCTAssertEqual(dashboard.nest(id: reporting.id)?.latestBatteryVoltage, 3.9)

        // ...and the one just registered has nothing, which is what the
        // success screen must render as "--" rather than 30.
        let new = try XCTUnwrap(dashboard.nest(id: justRegistered.id))
        XCTAssertNil(new.latestTemperatureC)
        XCTAssertNil(new.latestBatteryVoltage)
        XCTAssertEqual(NestTemperature.text(new.latestTemperatureC), "--")
        XCTAssertEqual(NestTemperature.Band(temperatureC: new.latestTemperatureC), .noData)

        // A nest that is not in this hatchery is not found by the lookup.
        XCTAssertNil(dashboard.nest(id: UUID()))
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

    /// The bug: the ranger's inspection date disappeared from the Timeline the
    /// moment the nest hatched, because `refresh_nest_summary` nulled the
    /// column to keep the nest out of the work queue. The date stays now, and
    /// the queue asks whether the nest hatched instead of reading a destroyed
    /// record -- so both halves have to hold at once.
    func testAHatchedNestKeepsItsInspectionDateAndLeavesTheQueue() {
        let due = Date().addingTimeInterval(-60 * 60 * 24)
        var nest = NestEntity(
            id: UUID(),
            hatcheryID: UUID(),
            founderID: nil,
            numberOfEggs: 100,
            dateEggsLaid: nil,
            datePredictedHatch: nil,
            successEggsHatch: nil,
            failEggsHatch: nil,
            placementRow: 1,
            placementColumn: 1,
            nextInspectionDate: due
        )

        XCTAssertTrue(nest.isDueForInspection(), "an unhatched nest past its date is due")

        // The tally arrives. eggsUnhatched is what a hatching row sets, and
        // the inspection date is deliberately left alone.
        nest.successEggsHatch = 80
        nest.failEggsHatch = 10
        nest.eggsUnhatched = 10

        XCTAssertEqual(nest.nextInspectionDate, due, "the date the ranger entered survives")
        XCTAssertFalse(nest.isDueForInspection(), "a hatched nest is never due, date or no date")
        XCTAssertTrue(nest.isComplete)
        XCTAssertFalse(nest.isPartiallyHatched)
    }

    /// Temperature is an incubation alert. A logger's last reading survives
    /// the hatching report, so the alert calculation must explicitly close
    /// with the nest instead of continuing to warn from stale sensor data.
    func testTemperatureAlertsOnlyApplyUntilTheNestHasHatched() {
        var nest = makeNestDashboardItem().nest

        let incubating = NestDashboardItem(
            nest: nest,
            latestTemperatureC: 34,
            latestBatteryVoltage: nil
        )
        XCTAssertEqual(incubating.temperatureAlert, .outOfRange)

        // Some hatchlings can emerge while the remaining eggs still need
        // monitoring. Only a final tally sets `eggsUnhatched`.
        nest.successEggsHatch = 5
        let partiallyHatched = NestDashboardItem(
            nest: nest,
            latestTemperatureC: 34,
            latestBatteryVoltage: nil
        )
        XCTAssertEqual(partiallyHatched.temperatureAlert, .outOfRange)

        nest.eggsUnhatched = 10
        let hatchedWithBadReading = NestDashboardItem(
            nest: nest,
            latestTemperatureC: 34,
            latestBatteryVoltage: nil
        )
        let hatchedWithNoReading = NestDashboardItem(
            nest: nest,
            latestTemperatureC: nil,
            latestBatteryVoltage: nil
        )

        XCTAssertNil(hatchedWithBadReading.temperatureAlert)
        XCTAssertNil(hatchedWithNoReading.temperatureAlert)
    }

    /// The red warning opens a purpose-built list. It must not fall back to
    /// the ordinary `.all` filter, which is how healthy nests appeared beside
    /// the one the warning was pointing at.
    func testTemperatureWarningFiltersExcludeHealthyAndMissingDataNests() {
        let nest = makeNestDashboardItem().nest
        let healthy = NestDashboardItem(
            nest: nest,
            latestTemperatureC: 30,
            latestBatteryVoltage: nil
        )
        let tooHot = NestDashboardItem(
            nest: nest,
            latestTemperatureC: 34,
            latestBatteryVoltage: nil
        )
        let noData = NestDashboardItem(
            nest: nest,
            latestTemperatureC: nil,
            latestBatteryVoltage: nil
        )

        XCTAssertFalse(NestListFilter.temperatureOutOfRange.matches(healthy))
        XCTAssertTrue(NestListFilter.temperatureOutOfRange.matches(tooHot))
        XCTAssertFalse(NestListFilter.temperatureOutOfRange.matches(noData))
        XCTAssertFalse(NestListFilter.temperatureNoData.matches(healthy))
        XCTAssertFalse(NestListFilter.temperatureNoData.matches(tooHot))
        XCTAssertTrue(NestListFilter.temperatureNoData.matches(noData))
    }

    /// Alert classification and the temperature UI must share one boundary.
    /// The dashboard previously accepted up to 33°C while the rest of the app
    /// marks anything above 32°C as critical.
    func testTemperatureAlertsUseTheSharedCriticalThresholds() {
        let nest = makeNestDashboardItem().nest

        func alert(at temperature: Double) -> NestDashboardItem.TemperatureAlert? {
            NestDashboardItem(
                nest: nest,
                latestTemperatureC: temperature,
                latestBatteryVoltage: nil
            ).temperatureAlert
        }

        XCTAssertEqual(alert(at: 25.9), .outOfRange)
        XCTAssertNil(alert(at: 26))
        XCTAssertNil(alert(at: 32))
        XCTAssertEqual(alert(at: 32.1), .outOfRange)
    }

    /// The hatching-soon queue counts a nest that is already late. Bounding it
    /// at zero would drop exactly the nests that most need a ranger, which is
    /// the failure this asserts against rather than the happy path.
    func testHatchingSoonSpansThreeDaysAndKeepsOverdueNests() {
        func nest(daysOut: Int?, hatched: Bool = false) -> NestEntity {
            var nest = NestEntity(
                id: UUID(),
                hatcheryID: UUID(),
                founderID: nil,
                numberOfEggs: 100,
                dateEggsLaid: nil,
                datePredictedHatch: daysOut.map {
                    Calendar.current.date(byAdding: .day, value: $0, to: Date())!
                },
                successEggsHatch: nil,
                failEggsHatch: nil,
                placementRow: 1,
                placementColumn: 1
            )
            if hatched { nest.eggsUnhatched = 0 }
            return nest
        }

        XCTAssertTrue(nest(daysOut: 0).isHatchingSoon, "hatching today")
        XCTAssertTrue(nest(daysOut: 3).isHatchingSoon, "the far edge of the window")
        XCTAssertTrue(nest(daysOut: -2).isHatchingSoon, "overdue stays in the queue")
        XCTAssertFalse(nest(daysOut: 4).isHatchingSoon, "outside the window")
        XCTAssertFalse(nest(daysOut: nil).isHatchingSoon, "no predicted date, nothing to count")
        XCTAssertFalse(nest(daysOut: 1, hatched: true).isHatchingSoon, "already hatched")
    }

    /// Tapping the selected section again clears it. Without this the overview
    /// is stuck on one section and the hatchery-wide numbers are unreachable.
    func testSelectingTheSameSectionTwiceDeselectsIt() {
        let controller = AppContainer().makeHatcheryController(sessionState: .previewSample)
        let sectionID = controller.sessionState.grid.sections.first { $0.isActive }!.id

        controller.selectSection(id: sectionID)
        XCTAssertEqual(controller.selectedSectionID, sectionID)

        controller.selectSection(id: sectionID)
        XCTAssertNil(controller.selectedSectionID, "a second tap on the same cell clears it")

        controller.selectSection(id: sectionID)
        XCTAssertEqual(controller.selectedSectionID, sectionID, "and a third re-selects")
    }

    private func makeController() -> NestController {
        NestController(
            hatcheryID: UUID(),
            nestService: NestService(repository: InMemoryNestRepository())
        )
    }

    /// The grid overlay is read to decide where a nest can go, so its badge
    /// counts what still occupies the sand. `nestCount` keeps reporting
    /// everything the section has held.
    func testOverlayCountsOnlyTheNestsStillInTheSand() {
        var hatched = makeNestDashboardItem().nest
        hatched.eggsUnhatched = 10

        // Hatchlings out but no final tally yet -- still incubating, so it
        // still occupies its section.
        var partial = makeNestDashboardItem().nest
        partial.successEggsHatch = 5

        let section = HatcherySectionDashboard(
            id: "A1",
            row: 0,
            column: 0,
            averageTemperatureC: nil,
            nestCount: 3,
            totalEggs: 300,
            nextHatchDate: nil,
            nests: [
                makeNestDashboardItem(),
                NestDashboardItem(nest: partial, latestTemperatureC: nil, latestBatteryVoltage: nil),
                NestDashboardItem(nest: hatched, latestTemperatureC: nil, latestBatteryVoltage: nil),
            ]
        )

        XCTAssertEqual(section.activeNestCount, 2)
        XCTAssertEqual(section.nestCount, 3)
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
