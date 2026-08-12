import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    let session: AppSession

    @State private var onboardingController: OnboardingController

    init(container: AppContainer, session: AppSession) {
        self.container = container
        self.session = session
        _onboardingController = State(
            initialValue: container.makeOnboardingController()
        )
    }

    var body: some View {
        if let activeHatchery = session.activeHatchery {
            ContentView(hatchery: activeHatchery, container: container)
        } else {
            OnboardingFlowView(
                controller: onboardingController,
                onSave: session.activate
            )
        }
    }
}
