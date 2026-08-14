import XCTest
@testable import community_challenge

final class InspectionAndDeviceTests: XCTestCase {

    // MARK: - Inspection rules

    /// Hatched means the counts are the whole point of the record.
    func testHatchedInspectionRequiresCounts() async throws {
        let (service, _, nest) = try await makeInspectionStack()

        await XCTAssertThrowsErrorAsync(
            try await service.recordInspection(
                RecordInspectionInput(
                    nestID: nest.id,
                    inspectedOn: Date(),
                    outcome: .complete,
                    eggsHatched: nil,
                    eggsRotten: nil,
                    nextInspectionDate: nil
                )
            )
        )
    }

    /// Not hatched means someone has to come back, so a next date is required.
    func testUnhatchedInspectionRequiresNextDate() async throws {
        let (service, _, nest) = try await makeInspectionStack()

        await XCTAssertThrowsErrorAsync(
            try await service.recordInspection(
                RecordInspectionInput(
                    nestID: nest.id,
                    inspectedOn: Date(),
                    outcome: .notHatched,
                    eggsHatched: nil,
                    eggsRotten: nil,
                    nextInspectionDate: nil
                )
            )
        )
    }

    /// Hatching ends the schedule; a next date alongside it is contradictory.
    func testHatchedInspectionRejectsANextDate() async throws {
        let (service, _, nest) = try await makeInspectionStack()

        await XCTAssertThrowsErrorAsync(
            try await service.recordInspection(
                RecordInspectionInput(
                    nestID: nest.id,
                    inspectedOn: Date(),
                    outcome: .complete,
                    eggsHatched: 80,
                    eggsRotten: 20,
                    nextInspectionDate: Date()
                )
            )
        )
    }

    /// Mirrors the apply_inspection_to_nest trigger: a hatch result moves the
    /// nest summary and clears the schedule.
    func testHatchedInspectionUpdatesNestSummaryAndClearsSchedule() async throws {
        let (service, nestRepository, nest) = try await makeInspectionStack()

        _ = try await service.recordInspection(
            RecordInspectionInput(
                nestID: nest.id,
                inspectedOn: Date(),
                outcome: .complete,
                eggsHatched: 80,
                eggsRotten: 20,
                nextInspectionDate: nil
            )
        )

        let updated = try await nestRepository.fetch(id: nest.id)
        XCTAssertEqual(updated.successEggsHatch, 80)
        XCTAssertEqual(updated.failEggsHatch, 20)
        XCTAssertNil(updated.nextInspectionDate)
        XCTAssertFalse(updated.isDueForInspection())
    }

    func testUnhatchedInspectionSchedulesTheNextVisit() async throws {
        let (service, nestRepository, nest) = try await makeInspectionStack()
        let nextDate = Date().addingTimeInterval(60 * 60 * 24 * 7)

        _ = try await service.recordInspection(
            RecordInspectionInput(
                nestID: nest.id,
                inspectedOn: Date(),
                outcome: .notHatched,
                eggsHatched: nil,
                eggsRotten: nil,
                nextInspectionDate: nextDate
            )
        )

        let updated = try await nestRepository.fetch(id: nest.id)
        XCTAssertEqual(updated.nextInspectionDate, nextDate)
        XCTAssertNil(updated.successEggsHatch)
        XCTAssertFalse(updated.isDueForInspection(), "A week out is not due yet")
    }

    func testInspectionsAreReturnedNewestFirst() async throws {
        let (service, _, nest) = try await makeInspectionStack()
        let older = Date().addingTimeInterval(-60 * 60 * 24 * 14)
        let newer = Date()

        for date in [older, newer] {
            _ = try await service.recordInspection(
                RecordInspectionInput(
                    nestID: nest.id,
                    inspectedOn: date,
                    outcome: .notHatched,
                    eggsHatched: nil,
                    eggsRotten: nil,
                    nextInspectionDate: date.addingTimeInterval(60 * 60 * 24 * 7)
                )
            )
        }

        let history = try await service.inspections(nestID: nest.id)
        XCTAssertEqual(history.map(\.inspectedOn), [newer, older])
    }

    /// A partial hatch still needs a follow-up: a clutch emerges over days, so
    /// finding hatchlings does not mean the nest is finished.
    func testPartiallyHatchedInspectionStillSchedulesTheNextVisit() async throws {
        let (service, nestRepository, nest) = try await makeInspectionStack()
        let nextDate = Date().addingTimeInterval(60 * 60 * 24 * 3)

        _ = try await service.recordInspection(
            RecordInspectionInput(
                nestID: nest.id,
                inspectedOn: Date(),
                outcome: .partiallyHatched,
                eggsHatched: 30,
                eggsRotten: 10,
                nextInspectionDate: nextDate
            )
        )

        let updated = try await nestRepository.fetch(id: nest.id)
        XCTAssertEqual(updated.successEggsHatch, 30)
        XCTAssertEqual(updated.failEggsHatch, 10)
        XCTAssertEqual(updated.eggsRemaining, 60, "100 - 30 hatched - 10 rotten")
        XCTAssertEqual(updated.nextInspectionDate, nextDate)
        XCTAssertFalse(updated.isComplete)
        XCTAssertTrue(updated.isPartiallyHatched)
    }

    /// Counts are per visit, so the nest total is their sum across visits.
    func testCountsAccumulateAcrossVisits() async throws {
        let (service, nestRepository, nest) = try await makeInspectionStack()

        // visit 1: 30 out, 10 rotten, 60 still incubating
        _ = try await service.recordInspection(
            RecordInspectionInput(
                nestID: nest.id,
                inspectedOn: Date().addingTimeInterval(-60 * 60 * 24 * 3),
                outcome: .partiallyHatched,
                eggsHatched: 30,
                eggsRotten: 10,
                nextInspectionDate: Date()
            )
        )
        let midway = try await nestRepository.fetch(id: nest.id)
        XCTAssertEqual(midway.eggsRemaining, 60)

        // visit 2: the rest emerge
        _ = try await service.recordInspection(
            RecordInspectionInput(
                nestID: nest.id,
                inspectedOn: Date(),
                outcome: .complete,
                eggsHatched: 55,
                eggsRotten: 5,
                nextInspectionDate: nil
            )
        )

        let finished = try await nestRepository.fetch(id: nest.id)
        XCTAssertEqual(finished.successEggsHatch, 85, "30 + 55")
        XCTAssertEqual(finished.failEggsHatch, 15, "10 + 5")
        XCTAssertEqual(finished.eggsRemaining, 0)
        XCTAssertNil(finished.nextInspectionDate)
        XCTAssertTrue(finished.isComplete)
        XCTAssertFalse(finished.isPartiallyHatched)
    }

    /// A partial hatch that found nothing is a contradiction.
    func testPartialHatchRequiresHatchlings() async throws {
        let (service, _, nest) = try await makeInspectionStack()

        await XCTAssertThrowsErrorAsync(
            try await service.recordInspection(
                RecordInspectionInput(
                    nestID: nest.id,
                    inspectedOn: Date(),
                    outcome: .partiallyHatched,
                    eggsHatched: 0,
                    eggsRotten: 5,
                    nextInspectionDate: Date()
                )
            )
        )
    }

    /// Correcting a miscount re-totals the nest rather than adding to it.
    func testCorrectingAnInspectionRetotalsTheNest() async throws {
        let (service, nestRepository, nest) = try await makeInspectionStack()

        let recorded = try await service.recordInspection(
            RecordInspectionInput(
                nestID: nest.id,
                inspectedOn: Date(),
                outcome: .partiallyHatched,
                eggsHatched: 30,
                eggsRotten: 10,
                nextInspectionDate: Date().addingTimeInterval(60 * 60 * 24 * 3)
            )
        )

        // recount: it was 32, not 30
        _ = try await service.correctInspection(
            id: recorded.id,
            CorrectInspectionInput(
                outcome: .partiallyHatched,
                eggsHatched: 32,
                eggsRotten: 10,
                nextInspectionDate: Date().addingTimeInterval(60 * 60 * 24 * 3)
            )
        )

        let updated = try await nestRepository.fetch(id: nest.id)
        XCTAssertEqual(updated.successEggsHatch, 32, "corrected, not 30 + 32")
        XCTAssertEqual(updated.eggsRemaining, 58)

        let history = try await service.inspections(nestID: nest.id)
        XCTAssertEqual(history.count, 1, "A correction edits the visit, it does not add one")
    }

    // MARK: - The inspection work queue

    func testNestsDueForInspectionOnlyIncludesDatesThatHaveArrived() async throws {
        let nestRepository = InMemoryNestRepository()
        let inspectionService = InspectionService(
            repository: InMemoryInspectionRepository(nestRepository: nestRepository)
        )
        let nestService = NestService(repository: nestRepository)
        let hatcheryID = UUID()

        let due = try await nestService.createNest(makeNestInput(hatcheryID: hatcheryID, column: 0))
        let notDue = try await nestService.createNest(makeNestInput(hatcheryID: hatcheryID, column: 1))

        // one overdue, one a week out
        _ = try await inspectionService.recordInspection(
            RecordInspectionInput(
                nestID: due.id,
                inspectedOn: Date().addingTimeInterval(-60 * 60 * 24 * 14),
                outcome: .notHatched,
                eggsHatched: nil,
                eggsRotten: nil,
                nextInspectionDate: Date().addingTimeInterval(-60 * 60 * 24)
            )
        )
        _ = try await inspectionService.recordInspection(
            RecordInspectionInput(
                nestID: notDue.id,
                inspectedOn: Date(),
                outcome: .notHatched,
                eggsHatched: nil,
                eggsRotten: nil,
                nextInspectionDate: Date().addingTimeInterval(60 * 60 * 24 * 7)
            )
        )

        let queue = try await nestService.nestsDueForInspection(hatcheryID: hatcheryID)
        XCTAssertEqual(queue.map(\.id), [due.id])
    }

    // MARK: - Devices

    /// Mirrors the unique constraint on device.nest_id.
    func testANestCannotHoldTwoDevices() async throws {
        let service = DeviceService(repository: InMemoryDeviceRepository())
        let nestID = UUID()

        _ = try await service.registerDevice(
            RegisterDeviceInput(name: "Probe A", nestID: nestID)
        )

        await XCTAssertThrowsErrorAsync(
            try await service.registerDevice(
                RegisterDeviceInput(name: "Probe B", nestID: nestID)
            )
        )
    }

    /// Unassigning frees the nest without destroying the hardware record.
    func testUnassigningFreesTheNestButKeepsTheDevice() async throws {
        let service = DeviceService(repository: InMemoryDeviceRepository())
        let nestID = UUID()
        let device = try await service.registerDevice(
            RegisterDeviceInput(name: "Probe A", nestID: nestID)
        )

        let unassigned = try await service.unassignDevice(id: device.id)
        XCTAssertNil(unassigned.nestID)
        XCTAssertFalse(unassigned.isAssigned)
        XCTAssertEqual(unassigned.name, "Probe A")

        // the nest is free again
        let replacement = try await service.registerDevice(
            RegisterDeviceInput(name: "Probe B", nestID: nestID)
        )
        XCTAssertEqual(replacement.nestID, nestID)

        let all = try await service.devices()
        XCTAssertEqual(all.count, 2)
    }

    func testRegisteringADeviceRequiresAName() async {
        let service = DeviceService(repository: InMemoryDeviceRepository())

        await XCTAssertThrowsErrorAsync(
            try await service.registerDevice(
                RegisterDeviceInput(name: "   ", nestID: nil)
            )
        )
    }

    // MARK: - Helpers

    private func makeInspectionStack() async throws
        -> (InspectionService, InMemoryNestRepository, NestEntity) {
        let nestRepository = InMemoryNestRepository()
        let nest = try await NestService(repository: nestRepository)
            .createNest(makeNestInput(hatcheryID: UUID(), column: 0))
        let service = InspectionService(
            repository: InMemoryInspectionRepository(nestRepository: nestRepository)
        )
        return (service, nestRepository, nest)
    }

    private func makeNestInput(hatcheryID: UUID, column: Int) -> CreateNestInput {
        CreateNestInput(
            hatcheryID: hatcheryID,
            founderID: nil,
            numberOfEggs: 100,
            dateEggsLaid: nil,
            datePredictedHatch: nil,
            placeEggsLaid: nil,
            placementRow: 0,
            placementColumn: column
        )
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
}

// MARK: - Hatching result

final class HatchingTests: XCTestCase {

    /// The screen's own example: 225 eggs, 90 rotten, 12 unhatched, 123 hatched.
    func testHatchingRecordsThreeCategoriesOnTheNest() async throws {
        let (service, nestRepository, nest) = try await makeStack(clutchSize: 225)

        _ = try await service.recordHatching(
            RecordHatchingInput(
                nestID: nest.id,
                hatchedOn: Date(),
                eggsHatched: 123,
                eggsRotten: 90,
                eggsUnhatched: 12
            )
        )

        let updated = try await nestRepository.fetch(id: nest.id)
        XCTAssertEqual(updated.successEggsHatch, 123)
        XCTAssertEqual(updated.failEggsHatch, 90)
        XCTAssertEqual(updated.eggsUnhatched, 12)
        XCTAssertEqual(updated.eggsRemaining, 0, "225 = 123 + 90 + 12")
        XCTAssertNil(updated.nextInspectionDate, "Hatching ends the schedule")
        XCTAssertTrue(updated.isComplete)
    }

    /// What the Hatchling details screen pre-fills into the hatched field.
    func testSuggestedHatchedCountIsTheRemainder() async throws {
        let (service, _, _) = try await makeStack(clutchSize: 225)

        XCTAssertEqual(
            service.suggestedHatchedCount(clutchSize: 225, eggsRotten: 90, eggsUnhatched: 12),
            123
        )
        // never negative, however wrong the other two are
        XCTAssertEqual(
            service.suggestedHatchedCount(clutchSize: 10, eggsRotten: 9, eggsUnhatched: 9),
            0
        )
    }

    /// The inspector may override the suggestion, so the three need not sum to
    /// the clutch — eggs can simply be unaccounted for.
    func testCountsMayFallShortOfTheClutch() async throws {
        let (service, nestRepository, nest) = try await makeStack(clutchSize: 225)

        _ = try await service.recordHatching(
            RecordHatchingInput(
                nestID: nest.id,
                hatchedOn: Date(),
                eggsHatched: 120,
                eggsRotten: 90,
                eggsUnhatched: 12
            )
        )

        let updated = try await nestRepository.fetch(id: nest.id)
        XCTAssertEqual(updated.eggsRemaining, 3, "222 accounted for out of 225")
    }

    /// Mirrors the hatching_within_clutch trigger.
    func testCountsCannotExceedTheClutch() async throws {
        let (service, _, nest) = try await makeStack(clutchSize: 225)

        do {
            _ = try await service.recordHatching(
                RecordHatchingInput(
                    nestID: nest.id,
                    hatchedOn: Date(),
                    eggsHatched: 200,
                    eggsRotten: 90,
                    eggsUnhatched: 12
                )
            )
            XCTFail("Expected the tally to be refused")
        } catch let error as DomainValidationError {
            guard case let .hatchingExceedsClutch(counted, clutchSize) = error else {
                return XCTFail("Expected .hatchingExceedsClutch, got \(error)")
            }
            XCTAssertEqual(counted, 302)
            XCTAssertEqual(clutchSize, 225)
        }
    }

    /// Mirrors the unique constraint on hatching.nest_id: one tally per nest.
    func testANestCannotHatchTwice() async throws {
        let (service, _, nest) = try await makeStack(clutchSize: 225)
        let input = RecordHatchingInput(
            nestID: nest.id,
            hatchedOn: Date(),
            eggsHatched: 123,
            eggsRotten: 90,
            eggsUnhatched: 12
        )

        _ = try await service.recordHatching(input)

        do {
            _ = try await service.recordHatching(input)
            XCTFail("Expected the second tally to be refused")
        } catch let error as DomainValidationError {
            guard case .nestAlreadyHatched = error else {
                return XCTFail("Expected .nestAlreadyHatched, got \(error)")
            }
        }
    }

    /// A correction replaces the tally rather than adding to it.
    func testCorrectingAHatchingReplacesTheCounts() async throws {
        let (service, nestRepository, nest) = try await makeStack(clutchSize: 225)

        let recorded = try await service.recordHatching(
            RecordHatchingInput(
                nestID: nest.id,
                hatchedOn: Date(),
                eggsHatched: 123,
                eggsRotten: 90,
                eggsUnhatched: 12
            )
        )

        _ = try await service.correctHatching(
            id: recorded.id,
            nestID: nest.id,
            CorrectHatchingInput(
                hatchedOn: recorded.hatchedOn,
                eggsHatched: 125,
                eggsRotten: 88,
                eggsUnhatched: 12
            )
        )

        let updated = try await nestRepository.fetch(id: nest.id)
        XCTAssertEqual(updated.successEggsHatch, 125, "replaced, not 123 + 125")
        XCTAssertEqual(updated.failEggsHatch, 88)
    }

    private func makeStack(clutchSize: Int) async throws
        -> (HatchingService, InMemoryNestRepository, NestEntity) {
        let nestRepository = InMemoryNestRepository()
        let nest = try await NestService(repository: nestRepository).createNest(
            CreateNestInput(
                hatcheryID: UUID(),
                founderID: nil,
                numberOfEggs: clutchSize,
                dateEggsLaid: nil,
                datePredictedHatch: nil,
                placeEggsLaid: nil,
                placementRow: 0,
                placementColumn: 0,
                nextInspectionDate: Date()
            )
        )
        let service = HatchingService(
            repository: InMemoryHatchingRepository(nestRepository: nestRepository),
            nestRepository: nestRepository
        )
        return (service, nestRepository, nest)
    }
}
