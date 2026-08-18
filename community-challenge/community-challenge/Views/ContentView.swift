//
//  ContentView.swift
//  community-challenge
//
//  Created by Nguyen Minh Luat on 10/8/26.
//

import SwiftUI

struct ContentView: View {
    let hatchery: HatcherySessionState
    let container: AppContainer
    let onSwitchHatchery: (HatcherySessionState) -> Void
    /// Called after signing out or deleting the account, so the root can leave
    /// this dashboard — the session it was built on no longer exists.
    var onAccountEnded: () -> Void = {}
    let onCreateHatchery: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var router = NestRouter()
    /// The section grid is a modal choice over the form, not a step in the
    /// flow, so it is presented rather than pushed.
    @State private var isPickingSection = false
    @State private var hatcheryController: HatcheryController
    @State private var nestController: NestController
    @State private var hatcheryListController: HatcheryListController
    @State private var isShowingHatcheryMenu = false
    @State private var isShowingHatcheryManagement = false
    @State private var rescanRequest: RescanRequest?
    /// Held while the management cover dismisses.
    ///
    /// Every exit from that cover has to wait for it to actually be gone.
    /// Switching or creating a hatchery changes `activeSessionRevision`, which
    /// rebuilds this whole view; doing that mid-dismissal leaves a presentation
    /// in flight on a view that no longer exists, and the next sheet — the
    /// profile button — then silently refuses to open.
    @State private var pendingManagementAction: PendingManagementAction?
    @State private var isShowingProfile = false
    @State private var profileController: ProfileController
    /// Held while the profile sheet dismisses, then promoted to
    /// `presentedInvite` — the same wait-for-dismissal rule every other
    /// presentation here follows.
    @State private var pendingInvite: OrganizationInviteEntity?
    @State private var presentedInvite: OrganizationInviteEntity?
    /// A nest to show after the Add Nest flow closes. Held rather than
    /// presented immediately: the flow has to finish popping first, or the
    /// sheet is presented on a stack that is still unwinding.
    @State private var pendingNestDetail: NestDetailPresentation?
    @State private var presentedNestDetail: NestDetailPresentation?

    init(
        hatchery: HatcherySessionState,
        container: AppContainer,
        onSwitchHatchery: @escaping (HatcherySessionState) -> Void = { _ in },
        onCreateHatchery: @escaping () -> Void = {},
        onAccountEnded: @escaping () -> Void = {}
    ) {
        self.hatchery = hatchery
        self.container = container
        self.onSwitchHatchery = onSwitchHatchery
        self.onCreateHatchery = onCreateHatchery
        self.onAccountEnded = onAccountEnded
        _hatcheryController = State(
            initialValue: container.makeHatcheryController(sessionState: hatchery)
        )
        _nestController = State(
            initialValue: container.makeNestController(hatcheryID: hatchery.hatchery.id)
        )
        _hatcheryListController = State(
            initialValue: container.makeHatcheryListController()
        )
        _profileController = State(
            initialValue: container.makeProfileController()
        )
    }

    var body: some View {
        @Bindable var router = router

        ZStack {
            NavigationStack(path: $router.path) {
                HomeView(
                    controller: hatcheryController,
                    container: container,
                    onAddNest: {
                        nestController.reset()
                        router.push(.connectBucket)
                    },
                    onOpenHatcheryMenu: {
                        presentHatcheryMenu()
                    },
                    onOpenProfile: { isShowingProfile = true },
                    // Same route as rescanning from the management sheet: the
                    // hatchery exists, it just has no photographed area yet.
                    onScanHatchery: { beginRescan(hatchery.hatchery) }
                )
                .sheet(
                    isPresented: $isShowingProfile,
                    onDismiss: presentPendingInvite
                ) {
                    ProfileSheetView(
                        controller: profileController,
                        onClose: { isShowingProfile = false },
                        onSignOut: {
                            isShowingProfile = false
                            Task { await signOut() }
                        },
                        onShowInvite: { invite in
                            // The invite screen is a full page, so the sheet
                            // has to be gone before it can be presented.
                            pendingInvite = invite
                            isShowingProfile = false
                        },
                        onDeleteAccount: {
                            try await container.deleteAccount()
                            isShowingProfile = false
                            // The account is gone; the next request mints a
                            // fresh anonymous identity, so send the app back
                            // to the empty-account route.
                            onAccountEnded()
                        }
                    )
                    // Figma 158:2283 draws an 801pt sheet; iOS adds the 34pt
                    // bottom safe area to a fixed detent, so the content is 767.
                    .presentationDetents([.height(ProfileSheetView.Layout.detentHeight)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(34)
                    .presentationSizing(.page)
                }
                .sheet(item: $presentedNestDetail) { selection in
                    NestDetailSheet(
                        item: selection.item,
                        ordinal: selection.ordinal,
                        sectionLabel: selection.sectionID,
                        controller: container.makeNestDetailController(nestID: selection.item.id),
                        onClose: { presentedNestDetail = nil },
                        onDelete: {
                            Task {
                                try? await container.makeNestService().deleteNest(id: selection.item.id)
                                presentedNestDetail = nil
                                await hatcheryController.load()
                            }
                        }
                    )
                    .presentationDetents([.height(NestDetailSheet.Layout.detentHeight)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(34)
                    .presentationSizing(.page)
                }
                .fullScreenCover(item: $presentedInvite) { invite in
                    InvitationCodeView(
                        invite: invite,
                        onBack: { presentedInvite = nil },
                        onRegenerate: {
                            await profileController.generateInvite()
                            if let refreshed = profileController.invite {
                                presentedInvite = refreshed
                            }
                        }
                    )
                }
                .fullScreenCover(
                    isPresented: $isShowingHatcheryManagement,
                    onDismiss: performPendingManagementAction
                ) {
                    HatcheryManagementView(
                        controller: hatcheryListController,
                        onSelect: { session in
                            if session.hatchery.id != hatchery.hatchery.id {
                                pendingManagementAction = .switchHatchery(session)
                            }
                            isShowingHatcheryManagement = false
                        },
                        onCreateNew: {
                            pendingManagementAction = .createHatchery
                            isShowingHatcheryManagement = false
                        },
                        onRescan: beginRescan,
                        onRename: updateActiveHatchery
                    )
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: NestRoute.self) { route in
                    switch route {
                    case .connectBucket:
                        AddNestConnectBucketView(
                            onContinue: { router.push(.identity) },
                            onCancel: finishAddNestFlow
                        )
                    case .identity:
                        AddNestIdentityView(
                            controller: nestController,
                            onSelectSection: { isPickingSection = true },
                            onPinLocation: { router.push(.locationPicker) },
                            onNext: { router.push(.eggInformation) },
                            onCancel: finishAddNestFlow
                        )
                    case .locationPicker:
                        NestLocationPickerView(
                            initialLatitude: nestController.draft.latitude,
                            initialLongitude: nestController.draft.longitude,
                            initialAddress: nestController.draft.locationAddress,
                            onCancel: router.pop,
                            onSave: { latitude, longitude, address in
                                nestController.draft.latitude = latitude
                                nestController.draft.longitude = longitude
                                nestController.draft.locationAddress = address
                                router.pop()
                            }
                        )
                    case .eggInformation:
                        AddNestEggInformationView(
                            controller: nestController,
                            onPreview: { router.push(.preview) },
                            onCancel: finishAddNestFlow
                        )
                    case .preview:
                        AddNestPreviewView(
                            controller: nestController,
                            onEdit: router.pop,
                            onCancel: finishAddNestFlow
                        ) {
                            Task {
                                guard await nestController.save() != nil else { return }
                                await hatcheryController.load()
                                router.replace(with: .success)
                            }
                        }
                    case .success:
                        NestRegistrationSuccessView(
                            nestNumber: savedNestNumber,
                            eggCount: savedEggCount,
                            hatchDate: savedHatchDate,
                            temperatureC: hatcheryController.overview?.averageTemperatureC ?? 30,
                            onViewNest: {
                                guard let nest = nestController.lastSavedNest else { return }
                                // Figma shows nest detail as a sheet, so this
                                // leaves the flow first and presents rather
                                // than pushing another page onto it.
                                pendingNestDetail = NestDetailPresentation(
                                    item: NestDashboardItem(
                                        nest: nest,
                                        latestTemperatureC: nil,
                                        latestBatteryVoltage: nil
                                    ),
                                    ordinal: Int(nestController.draft.nestNumber) ?? 0,
                                    sectionID: nestController.draft.section
                                )
                                finishAddNestFlow()
                            },
                            onBackToHatchery: finishAddNestFlow
                        )
                    }
                }
                .sheet(isPresented: $isPickingSection) {
                    NestSectionPickerView(
                        controller: nestController,
                        grid: hatchery.grid,
                        mapImage: hatchery.rectifiedPhoto,
                        usesMockMapCrop: hatchery.usesMockImage,
                        dashboard: hatcheryController.dashboard,
                        onCancel: { isPickingSection = false },
                        onConfirm: { isPickingSection = false }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(34)
                }
            }

            if isShowingHatcheryMenu {
                HatcheryQuickMenu(
                    controller: hatcheryListController,
                    activeHatchery: hatchery.hatchery,
                    selectedDestination: .hatchery(hatchery.hatchery.id),
                    onSelect: { session in
                        guard session.hatchery.id != hatchery.hatchery.id else { return }
                        onSwitchHatchery(session)
                    },
                    onManagement: {
                        isShowingHatcheryManagement = true
                    },
                    onCreateNew: onCreateHatchery,
                    onDismiss: {
                        dismissHatcheryMenu()
                    }
                )
                .transition(
                    .scale(scale: 0.94, anchor: .topLeading)
                        .combined(with: .opacity)
                )
                .zIndex(1)
            }
        }
        // Prime the popup list while the dashboard is visible, so opening the
        // hatchery menu never waits on its first list request.
        .task { await hatcheryListController.load() }
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

    private func finishAddNestFlow() {
        nestController.reset()
        router.reset()

        guard let pending = pendingNestDetail else { return }
        pendingNestDetail = nil
        presentedNestDetail = pending
    }

    private func presentHatcheryMenu() {
        setHatcheryMenuPresented(true)
    }

    private func dismissHatcheryMenu() {
        setHatcheryMenuPresented(false)
    }

    private func setHatcheryMenuPresented(_ isPresented: Bool) {
        withAnimation(menuAnimation) {
            isShowingHatcheryMenu = isPresented
        }
    }

    private var menuAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.12)
    }

    /// The number the database settled on, not the one the form proposed. Two
    /// rangers can compute the same next number offline; the server moves the
    /// later insert on, and this screen has to report what was actually saved.
    private var savedNestNumber: String {
        nestController.lastSavedNest?.nestNumber ?? nestController.draft.nestNumber
    }

    private var savedEggCount: String {
        nestController.lastSavedNest.map { String($0.numberOfEggs) }
            ?? nestController.draft.numberOfEggs
    }

    private var savedHatchDate: String {
        guard let date = nestController.lastSavedNest?.datePredictedHatch else {
            return nestController.draft.hatchDate
        }
        return AppDateFormatting.nestDraftDateString(date)
    }

    /// Two presentations have to come down first — the edit sheet, then the
    /// management cover — and only the second one's `onDismiss` says when that
    /// is genuinely finished. Presenting the scanner on a fixed delay instead
    /// raced that teardown and left an empty cover on screen.
    private func beginRescan(_ hatchery: HatcheryEntity) {
        pendingManagementAction = .rescan(
            RescanRequest(
                hatchery: hatchery,
                controller: container.makeHatcherySetupController(
                    editingHatchery: hatchery
                )
            )
        )
        isShowingHatcheryManagement = false
    }

    /// Runs once the profile sheet is genuinely gone. Closing it without
    /// generating a code leaves nothing pending, so this is a no-op.
    private func signOut() async {
        do {
            try await container.signOut()
            onAccountEnded()
        } catch {
            profileController.setErrorMessage(error.localizedDescription)
        }
    }

    private func presentPendingInvite() {
        guard let invite = pendingInvite else { return }
        pendingInvite = nil
        presentedInvite = invite
    }

    /// Runs once the management cover is genuinely gone. Closing it without
    /// choosing anything leaves no pending action, so this is a no-op.
    private func performPendingManagementAction() {
        guard let action = pendingManagementAction else { return }
        pendingManagementAction = nil

        switch action {
        case .switchHatchery(let session):
            onSwitchHatchery(session)
        case .createHatchery:
            onCreateHatchery()
        case .rescan(let request):
            rescanRequest = request
        }
    }

    private func finishRescan(_ session: HatcherySessionState) {
        rescanRequest = nil
        onSwitchHatchery(session)
    }

    private func cancelRescan() {
        rescanRequest = nil
    }

    private func updateActiveHatchery(_ updated: HatcheryEntity) {
        guard updated.id == hatchery.hatchery.id else { return }

        onSwitchHatchery(
            HatcherySessionState(
                hatchery: updated,
                photo: hatchery.photo,
                rectifiedPhoto: hatchery.rectifiedPhoto,
                usesMockImage: hatchery.usesMockImage,
                boundary: hatchery.boundary,
                sandRegion: hatchery.sandRegion,
                rectifiedSandRegion: hatchery.rectifiedSandRegion,
                grid: hatchery.grid
            )
        )
    }
}

/// What to do once the hatchery management cover has finished dismissing.
/// Every one of these either rebuilds this view or presents something else,
/// and neither is safe while a presentation is still animating away.
/// One nest to show in the detail sheet, with the labels the sheet needs.
struct NestDetailPresentation: Identifiable {
    let item: NestDashboardItem
    let ordinal: Int
    let sectionID: String

    var id: UUID { item.id }
}

private enum PendingManagementAction {
    case switchHatchery(HatcherySessionState)
    case createHatchery
    case rescan(RescanRequest)
}

/// A rescan needs both the hatchery and a setup controller bound to it.
/// Carrying them together as the presentation item means the cover physically
/// cannot appear without a controller, so there is no empty-state to render.
struct RescanRequest: Identifiable {
    let hatchery: HatcheryEntity
    let controller: HatcherySetupController

    var id: UUID { hatchery.id }
}

#Preview {
    ContentView(hatchery: .previewSample, container: AppContainer())
}
