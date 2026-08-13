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

    @State private var router = NestRouter()
    @State private var hatcheryController: HatcheryController
    @State private var nestController: NestController

    init(hatchery: HatcherySessionState, container: AppContainer) {
        self.hatchery = hatchery
        self.container = container
        _hatcheryController = State(
            initialValue: container.makeHatcheryController(sessionState: hatchery)
        )
        _nestController = State(
            initialValue: container.makeNestController(hatcheryID: hatchery.hatchery.id)
        )
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            HomeView(
                controller: hatcheryController,
                onAddNest: {
                    nestController.reset()
                    router.push(.identity)
                }
            )
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
    }

    private func finishAddNestFlow() {
        nestController.reset()
        router.reset()
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
}

#Preview {
    ContentView(hatchery: .previewSample, container: AppContainer())
}
