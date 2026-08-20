import XCTest
@testable import community_challenge

@MainActor
final class ProfileControllerTests: XCTestCase {
    /// The regression this guards: the Apple-address backfill used to run
    /// before the fetched profile was published, so the database refusing that
    /// write discarded a profile that had loaded perfectly well -- the sheet
    /// showed "Not set" for the name over a failure that had nothing to do
    /// with it.
    func testARefusedAppleEmailBackfillKeepsTheLoadedProfile() async {
        let repository = StubProfileRepository(
            profile: ProfileEntity(
                id: UUID(),
                displayName: "Jason",
                appleEmail: nil,
                organizationID: nil,
                role: .agent
            ),
            sessionEmail: "jason@example.com",
            updateFails: true
        )
        let controller = ProfileController(repository: repository)

        await controller.load()

        XCTAssertEqual(controller.displayName, "Jason")
        XCTAssertNil(controller.errorMessage)
    }

    /// The address is no longer shown on the profile sheet, but it is still
    /// recorded -- the sign-in capture and the `auth.users` trigger both write
    /// it, and it is what identifies the Apple account behind a row.
    func testASuccessfulBackfillPublishesTheAppleAddress() async {
        let repository = StubProfileRepository(
            profile: ProfileEntity(
                id: UUID(),
                displayName: "Jason",
                appleEmail: nil,
                organizationID: nil,
                role: .agent
            ),
            sessionEmail: "jason@example.com",
            updateFails: false
        )
        let controller = ProfileController(repository: repository)

        await controller.load()

        XCTAssertEqual(controller.profile?.appleEmail, "jason@example.com")
        XCTAssertEqual(controller.displayName, "Jason")
    }

    /// Dismissing the sheet cancels the load. That is the person closing a
    /// screen, not something to report back to them on it.
    func testACancelledLoadReportsNoError() async {
        let repository = StubProfileRepository(
            profile: nil,
            sessionEmail: nil,
            updateFails: false,
            fetchError: URLError(.cancelled)
        )
        let controller = ProfileController(repository: repository)

        await controller.load()

        XCTAssertNil(controller.errorMessage)
    }
}

private struct StubProfileError: Error {}

private actor StubProfileRepository: ProfileRepository {
    private let profile: ProfileEntity?
    private let sessionEmail: String?
    private let updateFails: Bool
    private let fetchError: Error?

    init(
        profile: ProfileEntity?,
        sessionEmail: String?,
        updateFails: Bool,
        fetchError: Error? = nil
    ) {
        self.profile = profile
        self.sessionEmail = sessionEmail
        self.updateFails = updateFails
        self.fetchError = fetchError
    }

    func fetchCurrentProfile() async throws -> ProfileEntity? {
        if let fetchError { throw fetchError }
        return profile
    }

    func fetchProfile(id: UUID) async throws -> ProfileEntity? { nil }

    /// Added to `ProfileRepository` for the members list without reaching this
    /// double, which left the whole test target unbuildable. Unrelated to the
    /// hatching work; fixed here because nothing else could run until it was.
    func fetchOrganizationMembers(organizationID: UUID) async throws -> [ProfileEntity] { [] }

    func updateCurrentProfile(
        displayName: String?,
        appleEmail: String?
    ) async throws -> ProfileEntity {
        if updateFails { throw StubProfileError() }
        guard var updated = profile else { throw StubProfileError() }
        updated.displayName = displayName
        updated.appleEmail = appleEmail
        return updated
    }

    func currentSessionEmail() async -> String? { sessionEmail }

    func fetchOrganization(id: UUID) async throws -> OrganizationEntity {
        throw StubProfileError()
    }

    func generateInvite() async throws -> OrganizationInviteEntity {
        throw StubProfileError()
    }

    @discardableResult
    func redeemInvite(code: String) async throws -> UUID { throw StubProfileError() }

    func deleteAccount() async throws { throw StubProfileError() }
}
