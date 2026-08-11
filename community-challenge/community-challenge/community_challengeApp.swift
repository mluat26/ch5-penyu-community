//
//  community_challengeApp.swift
//  community-challenge
//
//  Created by Nguyen Minh Luat on 10/8/26.
//

import SwiftUI

@main
struct community_challengeApp: App {
    @State private var savedHatchery: SavedHatchery?

    var body: some Scene {
        WindowGroup {
            if let savedHatchery {
                ContentView(hatchery: savedHatchery)
            } else {
                OnboardingFlowController { savedHatchery = $0 }
            }
        }
    }
}
