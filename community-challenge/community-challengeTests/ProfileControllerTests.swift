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

    /// Member management belongs to the organization's owner, which is
    /// `organization.owner_id` and not a role -- a manager who did not create
    /// the organization must not see the controls, and the owner must not see
    /// them on their own row.
    func testOnlyTheOrganizationOwnerManagesMembers() async {
        let owner = UUID()
        let colleague = ProfileEntity(
            id: UUID(),
            displayName: "Made Sari",
            appleEmail: nil,
            organizationID: nil,
            role: .officer
        )

        let asOwner = await makeController(currentUser: owner, ownerID: owner, members: [colleague])
        XCTAssertTrue(asOwner.canManageMembers)
        XCTAssertTrue(asOwner.canManage(colleague))
        XCTAssertFalse(
            asOwner.canManage(asOwner.profile!),
            "the owner cannot demote or remove themselves"
        )

        let asManager = await makeController(
            currentUser: UUID(),
            ownerID: owner,
            members: [colleague]
        )
        XCTAssertFalse(asManager.canManageMembers)
        XCTAssertFalse(asManager.canManage(colleague))
    }

    /// The write is followed by a re-read rather than a local patch: the
    /// database decides more than the field written, so the list has to come
    /// back from it.
    func testManagingAMemberRereadsTheList() async {
        let owner = UUID()
        let colleague = ProfileEntity(
            id: UUID(),
            displayName: "Made Sari",
            appleEmail: nil,
            organizationID: nil,
            role: .officer
        )
        let controller = await makeController(
            currentUser: owner,
            ownerID: owner,
            members: [colleague]
        )

        await controller.setRole(.coordinator, for: colleague)
        XCTAssertEqual(controller.members.first?.role, .coordinator)
        XCTAssertNil(controller.pendingMemberID)

        await controller.remove(colleague)
        XCTAssertTrue(controller.members.isEmpty)
        XCTAssertNil(controller.errorMessage)
    }

    private func makeController(
        currentUser: UUID,
        ownerID: UUID,
        members: [ProfileEntity]
    ) async -> ProfileController {
        let organizationID = UUID()
        let repository = StubProfileRepository(
            profile: ProfileEntity(
                id: currentUser,
                displayName: "Pak Wayan",
                appleEmail: "wayan@example.com",
                organizationID: organizationID,
                role: .manager
            ),
            sessionEmail: "wayan@example.com",
            updateFails: false,
            organization: OrganizationEntity(
                id: organizationID,
                name: "Penyu",
                createdAt: .now,
                code: "ORG-0000001",
                ownerID: ownerID
            ),
            members: members
        )
        let controller = ProfileController(repository: repository)
        await controller.load()
        return controller
    }
}

private struct StubProfileError: Error {}

private actor StubProfileRepository: ProfileRepository {
    private let profile: ProfileEntity?
    private let sessionEmail: String?
    private let updateFails: Bool
    private let fetchError: Error?
    private let organization: OrganizationEntity?
    /// Mutated by the member actions, so the controller's re-read after a write
    /// sees what the write did rather than the list it started with.
    private var members: [ProfileEntity]

    init(
        profile: ProfileEntity?,
        sessionEmail: String?,
        updateFails: Bool,
        fetchError: Error? = nil,
        organization: OrganizationEntity? = nil,
        members: [ProfileEntity] = []
    ) {
        self.profile = profile
        self.sessionEmail = sessionEmail
        self.updateFails = updateFails
        self.fetchError = fetchError
        self.organization = organization
        self.members = members
    }

    func fetchCurrentProfile() async throws -> ProfileEntity? {
        if let fetchError { throw fetchError }
        return profile
    }

    func fetchProfile(id: UUID) async throws -> ProfileEntity? { nil }

    /// Added to `ProfileRepository` for the members list without reaching this
    /// double, which left the whole test target unbuildable. Unrelated to the
    /// hatching work; fixed here because nothing else could run until it was.
    func fetchOrganizationMembers(organizationID: UUID) async throws -> [ProfileEntity] {
        members
    }

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
        guard let organization else { throw StubProfileError() }
        return organization
    }

    func generateInvite() async throws -> OrganizationInviteEntity {
        throw StubProfileError()
    }

    @discardableResult
    func redeemInvite(code: String) async throws -> UUID { throw StubProfileError() }

    func setMemberRole(memberID: UUID, role: OrganizationRole) async throws {
        guard let index = members.firstIndex(where: { $0.id == memberID }) else {
            throw StubProfileError()
        }
        members[index].role = role
    }

    func removeMember(memberID: UUID) async throws {
        members.removeAll { $0.id == memberID }
    }

    func deleteAccount() async throws { throw StubProfileError() }
}
