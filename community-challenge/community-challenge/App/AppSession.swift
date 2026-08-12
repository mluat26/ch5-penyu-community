import Observation

@MainActor
@Observable
final class AppSession {
    var activeHatchery: HatcherySessionData?

    func activate(_ hatchery: HatcherySessionData) {
        activeHatchery = hatchery
    }
}
