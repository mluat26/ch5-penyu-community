//
//  community_challengeApp.swift
//  community-challenge
//
//  Created by Nguyen Minh Luat on 10/8/26.
//

import SwiftUI

@main
struct community_challengeApp: App {
    @State private var session = AppSession()
    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            AppRootView(container: container, session: session)
        }
    }
}
