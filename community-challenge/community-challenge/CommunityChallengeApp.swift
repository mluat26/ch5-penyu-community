//
//  community_challengeApp.swift
//  community-challenge
//
//  Created by Nguyen Minh Luat on 10/8/26.
//

import SwiftUI

@main
struct CommunityChallengeApp: App {
    @State private var session = AppSessionController()
    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Set FIGMA_SCREEN in the scheme or `simctl launch` to render one
            // screen for pixel measurement. Unset, the real app runs.
            if let screen = FigmaMeasurementHarness.requestedScreen {
                FigmaMeasurementHarness.view(for: screen)
            } else {
                AppRootView(container: container, session: session)
            }
            #else
            AppRootView(container: container, session: session)
            #endif
        }
    }
}
