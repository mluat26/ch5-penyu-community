import SwiftUI

/// The route at which a hatchery setup run begins. First and additional
/// hatcheries begin with their Figma name-entry screens; re-scanning begins at
/// the same scan screen but saves through the backend's update path.
enum HatcherySetupEntryPoint {
    case firstHatch
    case additionalHatch
    case rescan
}

/// Everything this flow presents full-screen, as one value.
private enum SetupCover: Identifiable {
    case ready(HatcherySessionState)
    case invite(OrganizationInviteEntity)

    var id: String {
        switch self {
        case .ready(let hatchery): hatchery.id.uuidString
        case .invite(let invite): invite.id
        }
    }
}

/// Presentation flow only: it maps typed SwiftUI routes to views. The actual
/// setup draft and creation workflow belong to `HatcherySetupController`.
struct HatcherySetupFlowView: View {
    @Bindable var controller: HatcherySetupController
    let onSave: (HatcherySessionState) -> Void
    let entryPoint: HatcherySetupEntryPoint
    let onCancel: () -> Void
    /// Drives the profile sheet the name screen opens. Nil while there is no
    /// account to show — first-hatch onboarding — which is what keeps the icon
    /// decorative there, as it was everywhere before this.
    var profileController: ProfileController?
    /// Both tear down the session this flow is running inside, so they are
    /// handed upward rather than run here. Same split as
    /// `HatcheryManagementView`.
    var onSignOut: (() -> Void)?
    var onDeleteAccount: (() async throws -> Void)?

    @State private var router = HatcherySetupRouter()
    /// Every full-screen presentation this flow makes, as one value: SwiftUI
    /// keeps only the last `.fullScreenCover` attached to a view, so a second
    /// modifier would silently never present.
    @State private var presentedCover: SetupCover?
    @State private var isShowingProfile = false

    init(
        controller: HatcherySetupController,
        onSave: @escaping (HatcherySessionState) -> Void,
        entryPoint: HatcherySetupEntryPoint = .firstHatch,
        onCancel: @escaping () -> Void = {},
        profileController: ProfileController? = nil,
        onSignOut: (() -> Void)? = nil,
        onDeleteAccount: (() async throws -> Void)? = nil
    ) {
        self.controller = controller
        self.onSave = onSave
        self.entryPoint = entryPoint
        self.onCancel = onCancel
        self.profileController = profileController
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
    }

    /// Nil without a controller, which is what leaves the icon decorative on
    /// first-hatch onboarding rather than opening an empty sheet.
    private var profileHandler: (() -> Void)? {
        guard profileController != nil else { return nil }
        return { isShowingProfile = true }
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            rootView(router: router)
            .navigationDestination(for: HatcherySetupRoute.self) { route in
                destination(for: route, router: router)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // The session travels inside the presentation item rather than being
        // read back from state, and a cover rather than another route: setup
        // is finished and written by this point, so there is nothing left on
        // the stack worth going back to.
        .fullScreenCover(item: $presentedCover) { cover in
            switch cover {
            case .ready(let hatchery):
                HatcheryReadyView { onSave(hatchery) }

            case .invite(let invite):
                InvitationCodeView(
                    invite: invite,
                    onBack: { presentedCover = nil },
                    onRegenerate: {
                        guard let profileController else { return }
                        await profileController.generateInvite()
                        if let refreshed = profileController.invite {
                            presentedCover = .invite(refreshed)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingProfile) {
            if let profileController {
                ProfileSheetView(
                    controller: profileController,
                    onClose: { isShowingProfile = false },
                    onSignOut: {
                        isShowingProfile = false
                        onSignOut?()
                    },
                    onShowInvite: { invite in
                        // The invite screen is a full page, so the sheet has to
                        // be gone before it can be presented.
                        isShowingProfile = false
                        presentedCover = .invite(invite)
                    },
                    onDeleteAccount: {
                        try await onDeleteAccount?()
                        isShowingProfile = false
                    }
                )
                .presentationDetents([.height(ProfileSheetView.Layout.detentHeight)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
            }
        }
    }

    @ViewBuilder
    private func rootView(router: HatcherySetupRouter) -> some View {
        switch entryPoint {
        case .firstHatch:
            CreateFirstHatchView(
                onCreate: { name in
                    await continueWithNewHatchery(named: name, router: router)
                },
                onBack: onCancel,
                onProfile: profileHandler
            )

        case .additionalHatch:
            CreateFirstHatchView(
                style: .additionalHatch,
                onCreate: { name in
                    await continueWithNewHatchery(named: name, router: router)
                },
                onBack: onCancel,
                onProfile: profileHandler
            )

        case .rescan:
            scanView(router: router)
        }
    }

    @ViewBuilder
    private func destination(
        for route: HatcherySetupRoute,
        router: HatcherySetupRouter
    ) -> some View {
        switch route {
        case .scan:
            scanView(router: router)

        case .camera:
            CustomCameraView(
                onClose: router.pop,
                onCapture: { image, boundary in
                    controller.storeCapturedImage(image, boundary: boundary)
                    router.push(.adjustBoundary)
                }
            )

        case .adjustBoundary:
            if let image = controller.draft.image,
               let boundary = controller.draft.boundary {
                HatcheryBoundaryAdjustmentView(
                    image: image,
                    boundary: boundary,
                    sandRegion: controller.draft.sandRegion,
                    onRetake: {
                        controller.discardCaptureState()
                        router.pop()
                    },
                    onConfirm: { image, boundary, sandRegion in
                        guard await controller.confirmBoundary(
                            image: image,
                            boundary: boundary,
                            sandRegion: sandRegion
                        ) else { return }
                        advanceAfterBoundary(router: router)
                    }
                )
            }

        case .dimensions:
            if let image = controller.draft.rectifiedImage ?? controller.draft.image {
                HatcheryDimensionView(
                    hatchName: controller.draft.name,
                    image: image,
                    sandRegion: controller.draft.rectifiedSandRegion,
                    usesMockImage: controller.draft.usesMockImage,
                    showsCapturedImage: !controller.draft.isAwaitingScan,
                    initialDimension: controller.draft.dimension,
                    onNext: { dimension in
                        if controller.generateGrid(for: dimension) {
                            router.push(.preview)
                        }
                    },
                    onRescan: {
                        controller.discardCaptureState()
                        router.restartCamera()
                    }
                )
            }

        case .preview:
            if let image = controller.draft.rectifiedImage ?? controller.draft.image,
               let grid = controller.draft.grid {
                HatcheryGridPreviewView(
                    hatchName: controller.draft.name,
                    image: image,
                    sandRegion: controller.draft.rectifiedSandRegion,
                    usesMockImage: controller.draft.usesMockImage,
                    dimension: controller.draft.dimension,
                    grid: grid,
                    isSaving: controller.isSaving,
                    errorMessage: controller.errorMessage,
                    onDone: saveHatchery,
                    onBack: router.pop
                )
                .disabled(controller.isSaving)
            }
        }
    }

    private func scanView(router: HatcherySetupRouter) -> some View {
        ScanView(
            onScan: { router.push(.camera) },
            onSkip: {
                controller.skipScanning()
                router.push(.dimensions)
            },
            // `.scan` is this flow's root only for a rescan; the two creation
            // entry points always push it on top of their name screen.
            onBack: entryPoint == .rescan ? onCancel : router.pop
        )
    }

    /// A rescan is only re-photographing a hatchery that already exists, so it
    /// keeps the dimensions already saved and goes straight to the preview.
    /// Re-entering them would be busywork, and any change would move the grid
    /// out from under nests that are stored against it.
    @MainActor
    private func advanceAfterBoundary(router: HatcherySetupRouter) {
        guard entryPoint == .rescan else {
            router.push(.dimensions)
            return
        }

        guard controller.generateGrid(for: controller.draft.dimension) else {
            // `generateGrid` has already put the reason on the controller, and
            // the dimension screen is where it can be corrected.
            router.push(.dimensions)
            return
        }

        router.push(.preview)
    }

    @MainActor
    private func continueWithNewHatchery(
        named name: String,
        router: HatcherySetupRouter
    ) async -> String? {
        do {
            try await controller.validateNewHatcheryName(name)
            try Task.checkCancellation()
            controller.setName(name)
            router.push(.scan)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func saveHatchery() {
        Task {
            guard let hatchery = await controller.completeSetup() else { return }

            // A rescan only re-photographs a hatchery the user already has,
            // so it returns straight to it. "Your hatchery is ready" belongs
            // to setting one up, not to replacing its photo.
            guard entryPoint != .rescan else {
                onSave(hatchery)
                return
            }

            presentedCover = .ready(hatchery)
        }
    }
}

#Preview {
    HatcherySetupFlowView(
        controller: AppContainer().makeHatcherySetupController(),
        onSave: { _ in }
    )
}
