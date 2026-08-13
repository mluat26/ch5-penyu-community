import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    let session: AppSessionController

    @State private var hatcherySetupController: HatcherySetupController
    @State private var hatcheryListController: HatcheryListController
    @State private var isCreatingHatchery = false

    init(container: AppContainer, session: AppSessionController) {
        self.container = container
        self.session = session
        _hatcherySetupController = State(
            initialValue: container.makeHatcherySetupController()
        )
        _hatcheryListController = State(
            initialValue: container.makeHatcheryListController()
        )
    }

    var body: some View {
        if let activeHatchery = session.activeHatchery {
            ContentView(
                hatchery: activeHatchery,
                container: container,
                onSwitchHatchery: session.activate,
                onCreateHatchery: startNewHatchery
            )
            // ContentView builds its controllers in init, so switching hatcheries
            // has to produce a new instance rather than reusing one still bound
            // to the previous hatchery's id.
            .id(activeHatchery.hatchery.id)
        } else if isCreatingHatchery {
            HatcherySetupFlowView(
                controller: hatcherySetupController,
                onSave: session.activate
            )
        } else if !hatcheryListController.hasLoaded {
            // Neither screen is the right answer until the query returns:
            // showing one and swapping to the other reads as a glitch.
            Color.appOffWhite
                .ignoresSafeArea()
                .task { await hatcheryListController.load() }
        } else if hatcheryListController.hatcheries.isEmpty {
            // Nothing to open, so setup is the only useful screen.
            HatcherySetupFlowView(
                controller: hatcherySetupController,
                onSave: session.activate
            )
        } else {
            HatcheryPickerView(
                controller: hatcheryListController,
                onSelect: session.activate,
                onCreateNew: startNewHatchery
            )
        }
    }

    private func startNewHatchery() {
        session.startNewHatchery()
        isCreatingHatchery = true
    }
}
