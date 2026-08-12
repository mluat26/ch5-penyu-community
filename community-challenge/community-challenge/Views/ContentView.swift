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
                onAddNest: { router.push(.scan) }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: NestRoute.self) { route in
                switch route {
                case .scan:
                    AddNestScanView(
                        onScanned: { router.push(.nestInfo) },
                        onManualEntry: { router.push(.nestInfo) }
                    )
                case .nestInfo:
                    NewNestView(controller: nestController) {
                        router.push(.review)
                    }
                case .review:
                    ReviewNewNestView(controller: nestController) {
                        Task {
                            guard await nestController.save() != nil else { return }
                            nestController.reset()
                            router.reset()
                            await hatcheryController.load()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView(hatchery: .previewSample, container: AppContainer())
}
