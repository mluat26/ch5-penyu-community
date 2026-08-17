import Foundation

/// Backs the profile sheet: the signed-in member, their organization, and the
/// invite code they can issue.
@MainActor
@Observable
final class ProfileController {
    private(set) var profile: ProfileEntity?
    private(set) var organization: OrganizationEntity?
    private(set) var invite: OrganizationInviteEntity?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isGeneratingInvite = false
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

    var appleAccount: String {
        profile?.appleEmail?.isEmpty == false ? profile!.appleEmail! : "Not set"
    }

    var role: OrganizationRole { profile?.role ?? .agent }

    var organizationCode: String { organization?.displayCode ?? "—" }

    /// Managers issue invites. The database refuses anyone else, so hiding the
    /// action keeps the UI from offering something that cannot succeed.
    var canGenerateInvite: Bool { role.canGenerateInviteCode }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let profile = try await repository.fetchCurrentProfile()
            self.profile = profile
            draftName = profile?.displayName ?? ""

            if let organizationID = profile?.organizationID {
                organization = try await repository.fetchOrganization(id: organizationID)
            } else {
                organization = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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
