import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    let session: AppSessionController

    @State private var hatcherySetupController: HatcherySetupController

    init(container: AppContainer, session: AppSessionController) {
        self.container = container
        self.session = session
        _hatcherySetupController = State(
            initialValue: container.makeHatcherySetupController()
        )
    }

    var body: some View {
        if let activeHatchery = session.activeHatchery {
            ContentView(hatchery: activeHatchery, container: container)
        } else {
            HatcherySetupFlowView(
                controller: hatcherySetupController,
                onSave: session.activate
            )
        }
    }
}
