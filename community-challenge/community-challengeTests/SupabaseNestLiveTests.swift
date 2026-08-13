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
final class SupabaseNestLiveTests: XCTestCase {
    private var hatcheryRepository: SupabaseHatcheryRepository!
    private var nestRepository: SupabaseNestRepository!

    override func setUpWithError() throws {
        hatcheryRepository = SupabaseHatcheryRepository(client: SupabaseConfig.client)
        nestRepository = SupabaseNestRepository(client: SupabaseConfig.client)
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

        // hatch result
        let hatched = try await nestRepository.recordHatchResult(
            nestID: created.id,
            input: RecordHatchResultInput(successEggsHatch: 70, failEggsHatch: 0)
        )
        XCTAssertEqual(hatched.successEggsHatch, 70)

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
            telemetryRepository: InMemoryTelemetryRepository()
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
