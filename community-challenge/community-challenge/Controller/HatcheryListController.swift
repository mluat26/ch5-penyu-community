import Foundation
import Observation

@MainActor
@Observable
final class HatcheryListController {
    private(set) var hatcheries: [HatcheryEntity] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Distinguishes "no hatcheries" from "not asked yet", so the launch screen
    /// does not flash the setup flow before the first load returns.
    private(set) var hasLoaded = false

    private let hatcheryService: HatcheryService

    init(hatcheryService: HatcheryService) {
        self.hatcheryService = hatcheryService
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            hatcheries = try await hatcheryService.hatcheries()
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }

    /// Builds the session for a hatchery the user picked from the list. Fails
    /// only when the stored dimensions cannot produce a grid, which the setup
    /// flow already prevents.
    func session(for hatchery: HatcheryEntity) -> HatcherySessionState? {
        let session = HatcherySessionState.reconstructed(from: hatchery)
        if session == nil {
            errorMessage = "This hatchery's saved dimensions are too small to open."
        }
        return session
    }
}
