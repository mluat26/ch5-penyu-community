//
//  ContentView.swift
//  community-challenge
//
//  Created by Nguyen Minh Luat on 10/8/26.
//

import SwiftUI

struct ContentView: View {
    let hatchery: SavedHatchery

    @State private var addNestPath: [AddNestRoute] = []

    var body: some View {
        NavigationStack(path: $addNestPath) {
            HomeView(
                hatchery: hatchery,
                onAddNest: { addNestPath.append(.scan) }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AddNestRoute.self) { route in
                switch route {
                case .scan:
                    AddNestScanView(
                        onScanned: { addNestPath.append(.nestInfo) },
                        onManualEntry: { addNestPath.append(.nestInfo) }
                    )
                case .nestInfo:
                    NewNestView {
                        addNestPath.append(.review)
                    }
                case .review:
                    ReviewNewNestView {
                        addNestPath.removeAll()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView(hatchery: .previewSample)
}
