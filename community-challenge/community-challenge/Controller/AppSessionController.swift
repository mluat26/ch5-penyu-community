import Observation

@MainActor
@Observable
final class AppSessionController {
    var activeHatchery: HatcherySessionState?

    func activate(_ hatchery: HatcherySessionState) {
        activeHatchery = hatchery
    }

    /// Returns to the setup flow so another hatchery can be created.
    func startNewHatchery() {
        activeHatchery = nil
    }
}
