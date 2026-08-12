import Foundation
import Observation

@MainActor
@Observable
final class HatcheryController {
    let sessionState: HatcherySessionState

    private(set) var dashboard: HatcheryDashboard?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var selectedSectionID: String?
    var showsSectionSheet = false

    private let hatcheryService: HatcheryService
    private let demoDataSeeder: (any HatcheryDemoDataSeeding)?

    init(
        sessionState: HatcherySessionState,
        hatcheryService: HatcheryService,
        demoDataSeeder: (any HatcheryDemoDataSeeding)? = nil
    ) {
        self.sessionState = sessionState
        self.hatcheryService = hatcheryService
        self.demoDataSeeder = demoDataSeeder
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if let demoDataSeeder {
            await demoDataSeeder.seedDashboard(for: sessionState.hatchery)
        }

        do {
            dashboard = try await hatcheryService.loadDashboard(
                hatcheryID: sessionState.hatchery.id
            )
            clearInactiveSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectSection(id: String) {
        guard isSectionActive(id: id) else { return }
        selectedSectionID = id
    }

    func showSelectedSection() {
        showsSectionSheet = selectedSection != nil
    }

    func clearInactiveSelection() {
        guard let selectedSectionID, isSectionActive(id: selectedSectionID) else {
            self.selectedSectionID = nil
            showsSectionSheet = false
            return
        }
    }

    func gridSection(row: Int, column: Int) -> HatcherySection? {
        sessionState.grid.sections.first { $0.row == row && $0.column == column }
    }

    var selectedSection: HatcherySectionDashboard? {
        guard let selectedSectionID, isSectionActive(id: selectedSectionID) else {
            return nil
        }
        return dashboard?.sections.first { $0.id == selectedSectionID }
    }

    var overview: HatcheryOverview? {
        dashboard?.overview
    }

    private func isSectionActive(id: String) -> Bool {
        sessionState.grid.sections.contains { $0.id == id && $0.isActive }
    }
}
