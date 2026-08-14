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
    let onCreateHatchery: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var router = NestRouter()
    @State private var hatcheryController: HatcheryController
    @State private var nestController: NestController
    @State private var hatcheryListController: HatcheryListController
    @State private var isShowingHatcheryMenu = false
    @State private var isShowingHatcheryManagement = false
    @State private var rescanningHatchery: HatcheryEntity?
    @State private var rescanSetupController: HatcherySetupController?

    init(
        hatchery: HatcherySessionState,
        container: AppContainer,
        onSwitchHatchery: @escaping (HatcherySessionState) -> Void = { _ in },
        onCreateHatchery: @escaping () -> Void = {}
    ) {
        self.hatchery = hatchery
        self.container = container
        self.onSwitchHatchery = onSwitchHatchery
        self.onCreateHatchery = onCreateHatchery
        _hatcheryController = State(
            initialValue: container.makeHatcheryController(sessionState: hatchery)
        )
        _nestController = State(
            initialValue: container.makeNestController(hatcheryID: hatchery.hatchery.id)
        )
        _hatcheryListController = State(
            initialValue: container.makeHatcheryListController()
        )
    }

    var body: some View {
        @Bindable var router = router

        ZStack {
            NavigationStack(path: $router.path) {
                HomeView(
                    controller: hatcheryController,
                    onAddNest: {
                        nestController.reset()
                        router.push(.identity)
                    },
                    onOpenHatcheryMenu: {
                        presentHatcheryMenu()
                    }
                )
                .fullScreenCover(isPresented: $isShowingHatcheryManagement) {
                    HatcheryManagementView(
                        controller: hatcheryListController,
                        onSelect: { session in
                            isShowingHatcheryManagement = false
                            guard session.hatchery.id != hatchery.hatchery.id else { return }
                            onSwitchHatchery(session)
                        },
                        onCreateNew: {
                            isShowingHatcheryManagement = false
                            onCreateHatchery()
                        },
                        onRescan: beginRescan,
                        onRename: updateActiveHatchery
                    )
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: NestRoute.self) { route in
                    switch route {
                    case .identity:
                        AddNestIdentityView(
                            controller: nestController,
                            onSelectSection: { router.push(.sectionPicker) },
                            onNext: { router.push(.eggInformation) },
                            onCancel: finishAddNestFlow
                        )
                    case .sectionPicker:
                        NestSectionPickerView(
                            controller: nestController,
                            grid: hatchery.grid,
                            mapImage: hatchery.rectifiedPhoto,
                            usesMockMapCrop: hatchery.usesMockImage,
                            dashboard: hatcheryController.dashboard,
                            onCancel: router.pop,
                            onConfirm: router.pop
                        )
                    case .eggInformation:
                        AddNestEggInformationView(
                            controller: nestController,
                            onBack: router.pop,
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
                            nestNumber: nestController.draft.nestNumber,
                            eggCount: savedEggCount,
                            hatchDate: savedHatchDate,
                            temperatureC: hatcheryController.overview?.averageTemperatureC ?? 30,
                            onViewNest: {
                                guard let nest = nestController.lastSavedNest else { return }
                                router.push(
                                    .nestDetail(
                                        item: NestDashboardItem(
                                            nest: nest,
                                            latestTemperatureC: hatcheryController.overview?.averageTemperatureC
                                        ),
                                        ordinal: Int(nestController.draft.nestNumber) ?? 0,
                                        sectionID: nestController.draft.section
                                    )
                                )
                            },
                            onBackToHatchery: finishAddNestFlow
                        )
                    case .nestDetail(let item, let ordinal, let sectionID):
                        NestDetailView(
                            item: item,
                            ordinal: ordinal,
                            sectionID: sectionID
                        )
                        .toolbar(.hidden, for: .navigationBar)
                    }
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
        .fullScreenCover(item: $rescanningHatchery) { _ in
            if let rescanSetupController {
                HatcherySetupFlowView(
                    controller: rescanSetupController,
                    onSave: finishRescan,
                    entryPoint: .rescan,
                    onCancel: cancelRescan
                )
            } else {
                Color.clear
            }
        }
    }

    private func finishAddNestFlow() {
        nestController.reset()
        router.reset()
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

    private func beginRescan(_ hatchery: HatcheryEntity) {
        isShowingHatcheryManagement = false
        rescanSetupController = container.makeHatcherySetupController(
            editingHatchery: hatchery
        )

        // Let the management sheet and full-screen cover complete their
        // dismissal/presentation handoff before opening the scanner.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard rescanSetupController != nil else { return }
            rescanningHatchery = hatchery
        }
    }

    private func finishRescan(_ session: HatcherySessionState) {
        rescanningHatchery = nil
        rescanSetupController = nil
        onSwitchHatchery(session)
    }

    private func cancelRescan() {
        rescanningHatchery = nil
        rescanSetupController = nil
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
                grid: hatchery.grid
            )
        )
    }
}

#Preview {
    ContentView(hatchery: .previewSample, container: AppContainer())
}
