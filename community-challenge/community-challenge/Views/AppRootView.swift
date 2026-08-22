import SwiftUI

private enum InitialHatcheryOpeningState: Equatable {
    case idle
    case opening
    case failed
}

/// Owns app-level hatchery selection and creation state. The backend supplies
/// the management list; the selected hatchery remains a rich local session so
/// the current scan/layout can be rendered immediately after setup.
struct AppRootView: View {
    let container: AppContainer
    let session: AppSessionController

    @State private var hatcherySetupController: HatcherySetupController
    @State private var hatcheryListController: HatcheryListController
    /// Built once here rather than per presentation, so the sheet keeps what it
    /// loaded across openings of the name screen.
    @State private var profileController: ProfileController
    @State private var isCreatingHatchery = false
    @State private var hatcheryBeforeCreation: HatcherySessionState?
    @State private var rescanRequest: RescanRequest?
    @State private var initialHatcheryOpeningState = InitialHatcheryOpeningState.idle
    /// Set when someone backs out of first-hatch setup.
    ///
    /// Without it the root falls through its routing chain, which opens the
    /// first hatchery in the list rather than returning to the screen they
    /// came from. Back should land where the person was, not wherever the
    /// data happens to point.
    @State private var isShowingOnboarding = false
    /// Set only when the last hatchery was deleted. The person is still signed
    /// in, so the welcome frame would be a lie -- and its Sign in with Apple
    /// button replaces the identity rather than linking to it.
    @State private var onboardingStartsAtGetStarted = false
    /// The rich scan session can change even when a hatchery's UUID does not
    /// (for example, after re-scanning). This forces ContentView to rebuild
    /// its stateful dashboard controllers for that fresh session.
    @State private var activeSessionRevision = UUID()

    init(container: AppContainer, session: AppSessionController) {
        self.container = container
        self.session = session
        _hatcherySetupController = State(
            initialValue: container.makeHatcherySetupController()
        )
        _hatcheryListController = State(
            initialValue: container.makeHatcheryListController()
        )
        _profileController = State(
            initialValue: container.makeProfileController()
        )
    }

    /// Signing out from the name screen. Same shape as the dashboard's: the
    /// container clears the session, then the root drops back to the welcome
    /// route under whatever identity comes next.
    private func signOut() {
        Task {
            do {
                try await container.signOut()
                isCreatingHatchery = false
                endActiveAccount()
            } catch {
                profileController.setErrorMessage(error.localizedDescription)
            }
        }
    }

    var body: some View {
        Group {
            if let activeHatchery = session.activeHatchery {
                ContentView(
                    hatchery: activeHatchery,
                    container: container,
                    hatcheryListController: hatcheryListController,
                    profileController: profileController,
                    onSwitchHatchery: activateHatchery,
                    onCreateHatchery: startNewHatchery,
                    onAccountEnded: endActiveAccount,
                    onActiveHatcheryDeleted: activeHatcheryDeleted
                )
                // ContentView builds its controllers in init, so switching
                // hatcheries or re-scanning must create a new instance bound
                // to the fresh rich session rather than only its stable ID.
                .id(activeSessionRevision)
            } else if isCreatingHatchery {
                HatcherySetupFlowView(
                    controller: hatcherySetupController,
                    onSave: finishHatcheryCreation,
                    entryPoint: isCreatingAdditionalHatchery
                        ? .additionalHatch
                        : .firstHatch,
                    onCancel: cancelHatcheryCreation,
                    // Only when an account already exists. First-hatch
                    // onboarding has no profile to show, which is why the icon
                    // stays decorative there.
                    profileController: isCreatingAdditionalHatchery
                        ? profileController
                        : nil,
                    onSignOut: signOut,
                    onDeleteAccount: {
                        try await container.deleteAccount()
                        endActiveAccount()
                    }
                )
            } else if !hatcheryListController.hasLoaded {
                // Neither screen is right until the query returns; rendering
                // one then swapping would read as a launch glitch.
                Color.appOffWhite
                    .ignoresSafeArea()
                    .task { await hatcheryListController.load() }
            } else if !hatcheryListController.hasSuccessfulLoad {
                HatcheryListLoadFailureView(
                    message: hatcheryListController.errorMessage,
                    onRetry: {
                        Task { await hatcheryListController.load() }
                    }
                )
            } else if isShowingOnboarding || hatcheryListController.hatcheries.isEmpty {
                // The introductory pair of Figma screens is only for a
                // genuinely empty account. Its Create action preserves the
                // established setup controller and routing below.
                PreFirstHatchOnboardingView(
                    onCreateHatchery: startNewHatchery,
                    onSignInWithApple: signInWithApple,
                    onJoinWithCode: joinWithCode,
                    startsAtGetStarted: onboardingStartsAtGetStarted
                )
            } else if let firstHatchery = hatcheryListController.hatcheries.first {
                if initialHatcheryOpeningState == .failed {
                    HatcheryManagementView(
                        controller: hatcheryListController,
                        onSelect: activateHatchery,
                        onCreateNew: startNewHatchery,
                        onRescan: beginRescan
                    )
                } else {
                    OpeningHatcheryView(name: firstHatchery.name)
                        .task(id: firstHatchery.id) {
                            await openFirstHatchery()
                        }
                }
            } else {
                EmptyView()
            }
        }
        // The controller travels inside the presentation item. Reading it from
        // a sibling `@State` here returned the stale value cached in this
        // closure's captured view copy, which rendered an empty cover.
        .fullScreenCover(item: $rescanRequest) { request in
            HatcherySetupFlowView(
                controller: request.controller,
                onSave: finishRescan,
                entryPoint: .rescan,
                onCancel: cancelRescan
            )
        }
    }

    private func startNewHatchery() {
        isShowingOnboarding = false
        hatcheryBeforeCreation = session.activeHatchery
        hatcherySetupController = container.makeHatcherySetupController()
        session.startNewHatchery()
        isCreatingHatchery = true
    }

    /// Apple may resolve to a returning account with hatcheries on another
    /// device. Reload after the token exchange so the root immediately opens
    /// that account's first hatchery instead of continuing the empty setup.
    private func signInWithApple(
        identityToken: String,
        nonce: String,
        fullName: String?
    ) async throws {
        try await container.signInWithApple(
            identityToken: identityToken,
            nonce: nonce,
            fullName: fullName
        )
        await hatcheryListController.load()

        guard hatcheryListController.hasSuccessfulLoad else {
            throw AppleSignInFlowError.hatcheriesCouldNotLoad
        }
    }

    /// Redeeming moves this device into the inviter's organization, which is
    /// what makes their hatcheries readable. Reload afterwards so the root
    /// leaves the empty-account route and opens what the person just joined.
    private func joinWithCode(_ code: String) async throws {
        try await container.redeemInvite(code: code)
        await hatcheryListController.load()
        isShowingOnboarding = false

        guard hatcheryListController.hasSuccessfulLoad else {
            throw AppleSignInFlowError.hatcheriesCouldNotLoad
        }
    }

    /// The session the dashboard was built on is gone — signed out or deleted.
    /// Clear the active hatchery and reload, which drops the app back to the
    /// welcome route under whatever identity comes next.
    private func endActiveAccount() {
        session.activeHatchery = nil
        initialHatcheryOpeningState = .idle
        activeSessionRevision = UUID()
        onboardingStartsAtGetStarted = false

        Task { await hatcheryListController.load() }
    }

    /// The hatchery this session was built on has been deleted. The account is
    /// untouched, so this only has to answer "what now": the next hatchery if
    /// there is one, otherwise "Let's get started".
    ///
    /// The list is already right. `ContentView` shares this controller, so the
    /// delete that just happened removed the row from it before this runs --
    /// which matters, because the reroute happens on the very next render, long
    /// before any reload could return.
    private func activeHatcheryDeleted(_ hatcheryID: UUID) {
        onboardingStartsAtGetStarted = hatcheryListController.hatcheries.isEmpty
        session.activeHatchery = nil
        initialHatcheryOpeningState = .idle
        activeSessionRevision = UUID()

        Task { await hatcheryListController.load() }
    }

    private func finishHatcheryCreation(_ hatchery: HatcherySessionState) {
        isCreatingHatchery = false
        isShowingOnboarding = false
        hatcheryBeforeCreation = nil
        activateHatchery(hatchery)
        refreshHatcheryList()
    }

    private func cancelHatcheryCreation() {
        isCreatingHatchery = false

        if let hatcheryBeforeCreation {
            // Creating an additional hatchery: back returns to the one that
            // was open before.
            activateHatchery(hatcheryBeforeCreation)
        } else {
            // First-hatch setup was entered from the create-or-join screen,
            // so that is where back belongs.
            isShowingOnboarding = true
        }

        self.hatcheryBeforeCreation = nil
    }

    private var isCreatingAdditionalHatchery: Bool {
        hatcheryBeforeCreation != nil || !hatcheryListController.hatcheries.isEmpty
    }

    private func beginRescan(_ hatchery: HatcheryEntity) {
        let request = RescanRequest(
            hatchery: hatchery,
            controller: container.makeHatcherySetupController(
                editingHatchery: hatchery
            )
        )

        // The request originates in the edit sheet. Give that presentation a
        // moment to dismiss before presenting the scanner above it.
        // ponytail: still a timing guess. Unlike ContentView there is no cover
        // to hang `onDismiss` on here — removing it needs the sheet's own
        // dismissal reported out of HatcheryManagementView.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            rescanRequest = request
        }
    }

    private func finishRescan(_ hatchery: HatcherySessionState) {
        rescanRequest = nil
        activateHatchery(hatchery)
        refreshHatcheryList()
    }

    private func cancelRescan() {
        rescanRequest = nil
    }

    private func activateHatchery(_ hatchery: HatcherySessionState) {
        session.activate(hatchery)
        activeSessionRevision = UUID()
    }

    /// The normal app entry point is the first available hatchery, not the
    /// management list. Its scan layout may need a private Storage download,
    /// so wait behind a small loading state rather than presenting a blank or
    /// a non-interactive dashboard.
    private func openFirstHatchery() async {
        guard
            initialHatcheryOpeningState == .idle,
            session.activeHatchery == nil,
            !isCreatingHatchery
        else {
            return
        }

        initialHatcheryOpeningState = .opening
        guard let firstSession = await hatcheryListController.firstSession() else {
            guard !Task.isCancelled else { return }
            initialHatcheryOpeningState = .failed
            return
        }
        guard !Task.isCancelled else { return }
        activateHatchery(firstSession)
    }

    /// Refresh list-card metadata after a new scan or hatchery is committed;
    /// the active rich session is already immediate, while the management list
    /// must reflect its latest title, dimensions, and grid counts next time it
    /// is opened.
    private func refreshHatcheryList() {
        Task { @MainActor in
            await hatcheryListController.loadManagement(refreshHatcheries: true)
        }
    }
}

private enum AppleSignInFlowError: LocalizedError {
    case hatcheriesCouldNotLoad

    var errorDescription: String? {
        "Your account was signed in, but your hatcheries could not be loaded. Please try again."
    }
}

private struct OpeningHatcheryView: View {
    let name: String

    var body: some View {
        ZStack {
            Color.appOffWhite

            VStack(spacing: 12) {
                ProgressView()
                    .tint(Color.appGreenPrimary)

                Text("Opening \(name)…")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appGreenPrimary)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening \(name)")
    }
}

/// A failed backend query must not look like a valid empty hatchery account,
/// since that would send the user into setup and then fail again on save.
private struct HatcheryListLoadFailureView: View {
    let message: String?
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.appOffWhite

            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(Color.appGreenPrimary)

                Text("Unable to load hatcheries")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.appNeutralBlack)

                Text(message ?? "Check your connection and try again.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appNeutralGray1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                Button("Try again", action: onRetry)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "#FAF8F4"))
                    .frame(width: 180, height: 55)
                    .background(Color.appGreenPrimary, in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
    }
}
