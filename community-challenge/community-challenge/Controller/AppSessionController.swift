import Observation

@MainActor
@Observable
final class AppSessionController {
    var activeHatchery: HatcherySessionState?

    func activate(_ hatchery: HatcherySessionState) {
        activeHatchery = hatchery
    }
}
