import Foundation

/// Backs the profile sheet: the signed-in member, their organization, and the
/// invite code they can issue.
@MainActor
@Observable
final class ProfileController {
    private(set) var profile: ProfileEntity?
    private(set) var organization: OrganizationEntity?
    /// Everyone in the organization, for the Members list row and screen
    /// (Figma 200:4184 row 2, 200:4212).
    private(set) var members: [ProfileEntity] = []
    private(set) var invite: OrganizationInviteEntity?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isGeneratingInvite = false
    /// The member whose role or membership is being written, so the row that
    /// was tapped can show the wait instead of the whole list.
    private(set) var pendingMemberID: UUID?
    private(set) var errorMessage: String?

    /// Edited in place by the sheet's edit mode; committed by `save()`.
    var draftName: String = ""

    private let repository: any ProfileRepository

    init(repository: any ProfileRepository) {
        self.repository = repository
    }

    var displayName: String {
        profile?.displayName?.isEmpty == false ? profile!.displayName! : "Not set"
    }

    var role: OrganizationRole { profile?.role ?? .agent }

    /// True only while the first load is still in flight. Every value on this
    /// screen falls back to "Not set", "—", or Agent when `profile` is nil, so
    /// without this the sheet renders a confident wrong answer for as long as
    /// the network takes and an empty profile is indistinguishable from one
    /// that simply has not arrived.
    var isLoadingProfile: Bool { isLoading && profile == nil }

    var organizationCode: String { organization?.displayCode ?? "—" }

    /// Managers issue invites. The database refuses anyone else, so hiding the
    /// action keeps the UI from offering something that cannot succeed.
    var canGenerateInvite: Bool { role.canGenerateInviteCode }

    /// Deleting a hatchery is a manager's job. Someone with no organization is
    /// the only person who can see their own hatcheries at all, so they keep
    /// it -- otherwise a solo account, whose role is `agent` by definition,
    /// could never remove a hatchery it created by mistake.
    ///
    /// Deliberately stricter than the database rule, which also allows the
    /// hatchery's owner: an officer who happens to own one is refused here,
    /// because "only a manager may delete" is the point. The guard matters --
    /// `role` reads `.agent` before the profile has loaded.
    var canDeleteHatchery: Bool {
        guard let profile else { return false }
        return profile.role == .manager || profile.organizationID == nil
    }

    /// Only the organization's owner may change roles or remove people. This is
    /// `organization.owner_id`, not a role: a manager can be appointed, an
    /// owner is whoever created the organization's first hatchery. Same check
    /// the two database functions make, mirrored so the UI does not offer an
    /// action that would be refused.
    var canManageMembers: Bool {
        guard let ownerID = organization?.ownerID, let id = profile?.id else { return false }
        return ownerID == id
    }

    /// The owner's own row is not manageable — they cannot demote or remove
    /// themselves, and the database refuses both.
    func canManage(_ member: ProfileEntity) -> Bool {
        canManageMembers && member.id != profile?.id
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await repository.fetchCurrentProfile()

            // Published before anything optional runs, so a later step failing
            // cannot discard a profile that already arrived. Both the Apple
            // address backfill and the organization read used to sit ahead of
            // this assignment, which meant either one throwing blanked the
            // name as well -- over something that had nothing to do with it.
            profile = fetched
            draftName = fetched?.displayName ?? ""

            if let organizationID = fetched?.organizationID {
                organization = try await repository.fetchOrganization(id: organizationID)
                members = try await repository.fetchOrganizationMembers(
                    organizationID: organizationID
                )
            } else {
                organization = nil
                members = []
            }
        } catch {
            // Dismissing the sheet cancels this task mid-request. That is the
            // person closing a screen, not a failure to report back on it.
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
            return
        }

        await backfillAppleEmail()
    }

    /// Sign-in never recorded the Apple address, so fill it from the session
    /// the first time this screen is opened. Only ever written when the row has
    /// none: a person may have edited it since.
    ///
    /// Deliberately silent, and deliberately last. The profile is already on
    /// screen by now, and the database refusing this write -- an update policy
    /// that does not match the row the read policy allowed, which comes back as
    /// zero updated rows -- is not worth replacing a loaded profile with an
    /// error.
    private func backfillAppleEmail() async {
        guard
            let current = profile,
            current.appleEmail?.isEmpty ?? true,
            let sessionEmail = await repository.currentSessionEmail(),
            !sessionEmail.isEmpty,
            let updated = try? await repository.updateCurrentProfile(
                displayName: current.displayName,
                appleEmail: sessionEmail
            )
        else {
            return
        }

        profile = updated
    }

    /// URLSession reports a cancelled request as `URLError.cancelled` rather
    /// than `CancellationError`, so checking only the latter still surfaced
    /// "cancelled" to the person who did the cancelling.
    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            profile = try await repository.updateCurrentProfile(
                displayName: trimmed.isEmpty ? nil : trimmed,
                appleEmail: profile?.appleEmail
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generateInvite() async {
        guard !isGeneratingInvite else { return }
        isGeneratingInvite = true
        errorMessage = nil
        defer { isGeneratingInvite = false }

        do {
            invite = try await repository.generateInvite()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearInvite() {
        invite = nil
    }

    func setRole(_ role: OrganizationRole, for member: ProfileEntity) async {
        await manage(member) { try await $0.setMemberRole(memberID: member.id, role: role) }
    }

    func remove(_ member: ProfileEntity) async {
        await manage(member) { try await $0.removeMember(memberID: member.id) }
    }

    /// Both member actions are the same shape: write, then re-read the list.
    ///
    /// The list is re-read rather than patched in place because the database
    /// decides more than the one field written — removing somebody also revokes
    /// the invite codes they issued — and a locally edited row would show an
    /// answer the server never gave.
    private func manage(
        _ member: ProfileEntity,
        _ write: (any ProfileRepository) async throws -> Void
    ) async {
        guard pendingMemberID == nil else { return }
        pendingMemberID = member.id
        errorMessage = nil
        defer { pendingMemberID = nil }

        do {
            try await write(repository)
            if let organizationID = profile?.organizationID {
                members = try await repository.fetchOrganizationMembers(
                    organizationID: organizationID
                )
            }
        } catch {
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Lets the sheet surface a failure it handled itself, so every message on
    /// this screen comes from one place.
    func setErrorMessage(_ message: String?) {
        errorMessage = message
    }

    func discardEdits() {
        draftName = profile?.displayName ?? ""
        errorMessage = nil
    }
}
