#if LIVE_SUPABASE_TESTS
import XCTest
@testable import community_challenge

/// Hits the real Supabase project, creating and deleting rows in the shared dev
/// database. Compiled out by default so an ordinary run stays offline and does
/// not mutate shared state.
///
/// Run with:
///   xcodebuild test -scheme community-challenge \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///     -only-testing:community-challengeTests/SupabaseNestLiveTests \
///     SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LIVE_SUPABASE_TESTS' \
///     CODE_SIGNING_ALLOWED=NO
///
/// An environment-variable gate was tried first; xcodebuild does not forward
/// environment to hosted unit tests, so the flag has to be compile time.
///
/// The layout-persistence migration deliberately forbids direct client
/// hatchery creation/deletion, so this pre-lifecycle suite is skipped until a
/// service-role integration harness can perform immutable-photo cleanup. The
/// normal offline tests exercise the client lifecycle without shared-state
/// mutations.
final class SupabaseNestLiveTests: XCTestCase {
    private var identity: SupabaseAuthenticationService!
    private var hatcheryRepository: SupabaseHatcheryRepository!
    private var nestRepository: SupabaseNestRepository!

    override func setUpWithError() throws {
        throw XCTSkip(
            "Direct hatchery CRUD is unavailable after private layout persistence; use a trusted lifecycle integration harness."
        )

        let client = SupabaseConfig.client
        identity = SupabaseAuthenticationService(client: client)
        hatcheryRepository = SupabaseHatcheryRepository(
            client: client,
            identity: identity
        )
        nestRepository = SupabaseNestRepository(
            client: client,
            identity: identity
        )
    }

    /// Full CRUD against the live `nest` table, cleaning up after itself so
    /// repeated runs do not accumulate rows.
    func testNestCRUDAgainstLiveDatabase() async throws {
        // Rows and columns must agree with the dimensions the way
        // HatcheryGridGenerator derives them (floor(m / 2.0)), otherwise this
        // test writes a hatchery the app could never have produced.
        let hatchery = try await hatcheryRepository.create(
            CreateHatcheryInput(
                name: "Live test \(UUID().uuidString.prefix(8))",
                shape: .rectangle,
                numberOfRows: 5,
                numberOfColumns: 4,
                lengthM: 10,
                widthM: 8,
                organizationID: nil
            )
        )

        // create
        let laid = Date()
        let created = try await nestRepository.create(
            CreateNestInput(
                hatcheryID: hatchery.id,
                founderID: nil,
                numberOfEggs: 42,
                dateEggsLaid: laid,
                datePredictedHatch: laid.addingTimeInterval(60 * 60 * 24 * 59),
                placeEggsLaid: nil,
                placementRow: 1,
                placementColumn: 0
            )
        )
        XCTAssertEqual(created.numberOfEggs, 42)
        XCTAssertEqual(created.hatcheryID, hatchery.id)
        XCTAssertEqual(created.placementRow, 1)
        XCTAssertEqual(created.placementColumn, 0)
        // the date survived the round trip through a Postgres `date` column
        XCTAssertNotNil(created.dateEggsLaid)
        XCTAssertNotNil(created.datePredictedHatch)

        // read
        let fetched = try await nestRepository.fetch(id: created.id)
        XCTAssertEqual(fetched.id, created.id)

        let all = try await nestRepository.fetchAll(hatcheryID: hatchery.id)
        XCTAssertEqual(all.map(\.id), [created.id])

        // update
        let updated = try await nestRepository.update(
            id: created.id,
            UpdateNestInput(
                numberOfEggs: 80,
                dateEggsLaid: laid,
                datePredictedHatch: nil,
                placeEggsLaid: nil,
                placementRow: 3,
                placementColumn: 3
            )
        )
        XCTAssertEqual(updated.numberOfEggs, 80)
        XCTAssertEqual(updated.placementRow, 3)

        // hatch results now go through the inspection table, which the
        // apply_inspection_to_nest trigger applies to the nest; covered by
        // testInspectionUpdatesTheNestSummary below.

        // delete, and the row is really gone
        try await nestRepository.delete(id: created.id)
        var deletedNestWasFound = true
        do {
            _ = try await nestRepository.fetch(id: created.id)
        } catch {
            deletedNestWasFound = false
        }
        XCTAssertFalse(deletedNestWasFound, "Deleted nest should no longer be readable")

        // leave the database as we found it
        try await hatcheryRepository.delete(id: hatchery.id)
    }

    /// A hatchery still holding nests must not be deletable, and the message has
    /// to name the count rather than surfacing a raw foreign key violation.
    func testDeletingAHatcheryHoldingNestsIsBlocked() async throws {
        let hatcheryService = HatcheryService(
            hatcheryRepository: hatcheryRepository,
            nestRepository: nestRepository,
            ioTDataRepository: InMemoryIoTDataRepository()
        )

        let hatchery = try await hatcheryRepository.create(
            CreateHatcheryInput(
                name: "Live delete guard \(UUID().uuidString.prefix(8))",
                shape: .rectangle,
                numberOfRows: 5,
                numberOfColumns: 4,
                lengthM: 10,
                widthM: 8,
                organizationID: nil
            )
        )
        let nest = try await nestRepository.create(
            CreateNestInput(
                hatcheryID: hatchery.id,
                founderID: nil,
                numberOfEggs: 12,
                dateEggsLaid: nil,
                datePredictedHatch: nil,
                placeEggsLaid: nil,
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

        // once empty it succeeds, which also cleans up after this test
        try await nestRepository.delete(id: nest.id)
        try await hatcheryService.deleteHatchery(id: hatchery.id)
    }

    /// The apply_inspection_to_nest trigger must move the nest summary and
    /// clear the schedule, so the two can never disagree.
    func testInspectionUpdatesTheNestSummary() async throws {
        let inspectionRepository = SupabaseInspectionRepository(client: SupabaseConfig.client)
        let hatchery = try await hatcheryRepository.create(
            CreateHatcheryInput(
                name: "Live inspection \(UUID().uuidString.prefix(8))",
                shape: .rectangle,
                numberOfRows: 5,
                numberOfColumns: 4,
                lengthM: 10,
                widthM: 8,
                organizationID: nil
            )
        )
        let nest = try await nestRepository.create(
            CreateNestInput(
                hatcheryID: hatchery.id,
                founderID: nil,
                numberOfEggs: 100,
                dateEggsLaid: nil,
                datePredictedHatch: nil,
                placeEggsLaid: nil,
                placementRow: 0,
                placementColumn: 0,
                nextInspectionDate: Date()
            )
        )

        // not hatched yet: the next visit is scheduled
        let nextDue = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        _ = try await inspectionRepository.create(
            RecordInspectionInput(
                nestID: nest.id,
                inspectedOn: Date(),
                outcome: .notHatched,
                eggsHatched: nil,
                eggsRotten: nil,
                nextInspectionDate: nextDue
            )
        )
        let pending = try await nestRepository.fetch(id: nest.id)
        XCTAssertNotNil(pending.nextInspectionDate)
        XCTAssertNil(pending.successEggsHatch)

        // hatched: counts land on the nest and the schedule ends
        _ = try await inspectionRepository.create(
            RecordInspectionInput(
                nestID: nest.id,
                inspectedOn: Date(),
                outcome: .complete,
                eggsHatched: 80,
                eggsRotten: 20,
                nextInspectionDate: nil
            )
        )
        let hatched = try await nestRepository.fetch(id: nest.id)
        XCTAssertEqual(hatched.successEggsHatch, 80)
        XCTAssertEqual(hatched.failEggsHatch, 20)
        XCTAssertNil(hatched.nextInspectionDate)

        let history = try await inspectionRepository.fetchAll(nestID: nest.id)
        XCTAssertEqual(history.count, 2, "Both visits are kept as history")

        // inspections cascade with the nest
        try await nestRepository.delete(id: nest.id)
        try await hatcheryRepository.delete(id: hatchery.id)
    }

    /// The check constraints, exercised through the repository rather than
    /// InspectionService so the Swift validation is bypassed and it is really
    /// Postgres doing the rejecting. Without this, a mistake in the SQL and the
    /// same mistake in InspectionService would agree with each other and no
    /// test would notice.
    func testInspectionConstraintsRejectContradictoryRows() async throws {
        let inspectionRepository = SupabaseInspectionRepository(client: SupabaseConfig.client)
        let hatchery = try await hatcheryRepository.create(
            CreateHatcheryInput(
                name: "Live constraints \(UUID().uuidString.prefix(8))",
                shape: .rectangle,
                numberOfRows: 5,
                numberOfColumns: 4,
                lengthM: 10,
                widthM: 8,
                organizationID: nil
            )
        )
        let nest = try await nestRepository.create(
            CreateNestInput(
                hatcheryID: hatchery.id,
                founderID: nil,
                numberOfEggs: 100,
                dateEggsLaid: nil,
                datePredictedHatch: nil,
                placeEggsLaid: nil,
                placementRow: 0,
                placementColumn: 0,
                nextInspectionDate: nil
            )
        )

        let laterDate = Calendar.current.date(byAdding: .day, value: 5, to: Date())!

        // each of these must be refused by a check constraint
        let contradictions: [(String, RecordInspectionInput)] = [
            ("complete with a next visit still scheduled", .init(
                nestID: nest.id, inspectedOn: Date(), outcome: .complete,
                eggsHatched: 80, eggsRotten: 20, nextInspectionDate: laterDate
            )),
            ("unfinished with no next visit", .init(
                nestID: nest.id, inspectedOn: Date(), outcome: .notHatched,
                eggsHatched: nil, eggsRotten: nil, nextInspectionDate: nil
            )),
            ("complete without counts", .init(
                nestID: nest.id, inspectedOn: Date(), outcome: .complete,
                eggsHatched: nil, eggsRotten: nil, nextInspectionDate: nil
            )),
            ("partial hatch with zero hatchlings", .init(
                nestID: nest.id, inspectedOn: Date(), outcome: .partiallyHatched,
                eggsHatched: 0, eggsRotten: 5, nextInspectionDate: laterDate
            )),
            ("negative count", .init(
                nestID: nest.id, inspectedOn: Date(), outcome: .partiallyHatched,
                eggsHatched: 10, eggsRotten: -1, nextInspectionDate: laterDate
            ))
        ]

        var accepted: [String] = []
        for (label, input) in contradictions {
            do {
                _ = try await inspectionRepository.create(input)
                accepted.append(label)
            } catch {
                // expected
            }
        }

        try await nestRepository.delete(id: nest.id)
        try await hatcheryRepository.delete(id: hatchery.id)

        XCTAssertTrue(
            accepted.isEmpty,
            "Postgres accepted rows it should have refused: \(accepted.joined(separator: "; "))"
        )
    }

    /// Counts are per visit, so the trigger must sum them. A single-visit test
    /// cannot tell summing apart from copying the latest row.
    func testCountsAccumulateAcrossVisitsInTheDatabase() async throws {
        let inspectionRepository = SupabaseInspectionRepository(client: SupabaseConfig.client)
        let hatchery = try await hatcheryRepository.create(
            CreateHatcheryInput(
                name: "Live totals \(UUID().uuidString.prefix(8))",
                shape: .rectangle,
                numberOfRows: 5,
                numberOfColumns: 4,
                lengthM: 10,
                widthM: 8,
                organizationID: nil
            )
        )
        let nest = try await nestRepository.create(
            CreateNestInput(
                hatcheryID: hatchery.id,
                founderID: nil,
                numberOfEggs: 100,
                dateEggsLaid: nil,
                datePredictedHatch: nil,
                placeEggsLaid: nil,
                placementRow: 0,
                placementColumn: 0,
                nextInspectionDate: Date()
            )
        )

        // 30 out, 10 rotten, 60 still incubating
        let recorded = try await inspectionRepository.create(
            RecordInspectionInput(
                nestID: nest.id,
                inspectedOn: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
                outcome: .partiallyHatched,
                eggsHatched: 30,
                eggsRotten: 10,
                nextInspectionDate: Date()
            )
        )
        let midway = try await nestRepository.fetch(id: nest.id)

        // the rest emerge
        _ = try await inspectionRepository.create(
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

        // correcting the first visit must re-total, not add again
        _ = try await inspectionRepository.update(
            id: recorded.id,
            CorrectInspectionInput(
                outcome: .partiallyHatched,
                eggsHatched: 32,
                eggsRotten: 10,
                nextInspectionDate: Date()
            )
        )
        let corrected = try await nestRepository.fetch(id: nest.id)

        try await nestRepository.delete(id: nest.id)
        try await hatcheryRepository.delete(id: hatchery.id)

        XCTAssertEqual(midway.successEggsHatch, 30)
        XCTAssertEqual(midway.eggsRemaining, 60)
        XCTAssertEqual(finished.successEggsHatch, 85, "30 + 55, summed by the trigger")
        XCTAssertEqual(finished.failEggsHatch, 15, "10 + 5")
        XCTAssertEqual(finished.eggsRemaining, 0)
        XCTAssertNil(finished.nextInspectionDate)
        XCTAssertEqual(corrected.successEggsHatch, 87, "32 + 55, re-totalled not double counted")
    }

    /// The unique constraint on device.nest_id: one device per nest, while any
    /// number may sit unassigned.
    func testANestCannotHoldTwoDevices() async throws {
        let deviceRepository = SupabaseDeviceRepository(client: SupabaseConfig.client)
        let hatchery = try await hatcheryRepository.create(
            CreateHatcheryInput(
                name: "Live device \(UUID().uuidString.prefix(8))",
                shape: .rectangle,
                numberOfRows: 5,
                numberOfColumns: 4,
                lengthM: 10,
                widthM: 8,
                organizationID: nil
            )
        )
        let nest = try await nestRepository.create(
            CreateNestInput(
                hatcheryID: hatchery.id,
                founderID: nil,
                numberOfEggs: 50,
                dateEggsLaid: nil,
                datePredictedHatch: nil,
                placeEggsLaid: nil,
                placementRow: 0,
                placementColumn: 0,
                nextInspectionDate: nil
            )
        )

        let first = try await deviceRepository.create(
            RegisterDeviceInput(name: "Probe A", nestID: nest.id)
        )

        var secondSucceeded = true
        var secondError: (any Error)?
        do {
            _ = try await deviceRepository.create(
                RegisterDeviceInput(name: "Probe B", nestID: nest.id)
            )
        } catch {
            secondSucceeded = false
            secondError = error
        }

        // deleting the nest frees the device rather than destroying it
        try await nestRepository.delete(id: nest.id)
        let freed = try await deviceRepository.fetch(id: first.id)

        try await deviceRepository.delete(id: first.id)
        try await hatcheryRepository.delete(id: hatchery.id)

        XCTAssertFalse(secondSucceeded, "device.nest_id is unique")
        // ...and it must fail the SAME way the in-memory fake does, or a view
        // that shows the message will work in tests and break in the app.
        guard case .nestAlreadyHasDevice = (secondError as? DomainValidationError) else {
            return XCTFail(
                "Expected .nestAlreadyHasDevice from Supabase, got \(String(describing: secondError))"
            )
        }
        XCTAssertNil(freed.nestID, "ON DELETE SET NULL keeps the hardware record")
    }

    /// The database trigger is the backstop behind HatcheryService's own check:
    /// a placement outside the hatchery's grid must be rejected by Postgres.
    func testNestPlacedOutsideTheGridIsRejected() async throws {
        let hatchery = try await hatcheryRepository.create(
            CreateHatcheryInput(
                name: "Live grid guard \(UUID().uuidString.prefix(8))",
                shape: .rectangle,
                numberOfRows: 5,
                numberOfColumns: 4,
                lengthM: 10,
                widthM: 8,
                organizationID: nil
            )
        )

        var insertSucceeded = true
        do {
            _ = try await nestRepository.create(
                CreateNestInput(
                    hatcheryID: hatchery.id,
                    founderID: nil,
                    numberOfEggs: 10,
                    dateEggsLaid: nil,
                    datePredictedHatch: nil,
                    placeEggsLaid: nil,
                    placementRow: 99,
                    placementColumn: 0
                )
            )
        } catch {
            insertSucceeded = false
        }

        try await hatcheryRepository.delete(id: hatchery.id)
        XCTAssertFalse(
            insertSucceeded,
            "nest_placement_within_hatchery should reject a placement outside the grid"
        )
    }

    /// The hatchery a nest points at must exist: the schema declares
    /// nest_hatchery_id_fkey, so an orphan insert has to be rejected.
    func testNestInsertWithUnknownHatcheryIsRejected() async throws {
        var insertSucceeded = true
        do {
            _ = try await nestRepository.create(
                CreateNestInput(
                    hatcheryID: UUID(),
                    founderID: nil,
                    numberOfEggs: 10,
                    dateEggsLaid: nil,
                    datePredictedHatch: nil,
                    placeEggsLaid: nil,
                    placementRow: 0,
                    placementColumn: 0
                )
            )
        } catch {
            insertSucceeded = false
        }
        XCTAssertFalse(
            insertSucceeded,
            "Foreign key nest_hatchery_id_fkey should reject an unknown hatchery_id"
        )
    }
}
#endif
