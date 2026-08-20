import Foundation
import Observation

/// The extra dashboard information rendered on each hatchery-management card.
/// A failed telemetry query should not hide an otherwise valid hatchery, so the
/// overview remains optional and the list itself stays usable.
struct HatcheryManagementSummary: Identifiable, Hashable {
    let hatchery: HatcheryEntity
    let overview: HatcheryOverview?

    var id: UUID { hatchery.id }
}

@MainActor
@Observable
final class HatcheryListController {
    private(set) var hatcheries: [HatcheryEntity] = []
    private(set) var managementSummaries: [HatcheryManagementSummary] = []
    private(set) var isLoading = false
    private(set) var isLoadingManagement = false
    private(set) var updatingHatcheryID: UUID?
    /// A layout restore may include a private Storage download. Keep it
    /// single-flight so two quick taps cannot finish out of order and activate
    /// a different hatchery from the one the person most recently saw.
    private(set) var openingHatcheryID: UUID?
    private(set) var errorMessage: String?
    /// `hasLoaded` tells the launch UI it may stop showing a blank state;
    /// `hasSuccessfulLoad` prevents an offline/error response from being
    /// mistaken for a genuinely empty account.
    private(set) var hasSuccessfulLoad = false
    /// Distinguishes "no hatcheries" from "not asked yet", so the launch screen
    /// does not flash the setup flow before the first load returns.
    private(set) var hasLoaded = false

    private let hatcheryService: HatcheryService
    private let layoutService: HatcheryLayoutService?
    @ObservationIgnored private var listLoadTask: Task<Void, Never>?

    init(
        hatcheryService: HatcheryService,
        layoutService: HatcheryLayoutService? = nil
    ) {
        self.hatcheryService = hatcheryService
        self.layoutService = layoutService
    }

    func load() async {
        if let listLoadTask {
            await listLoadTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        listLoadTask = task
        await task.value
    }

    private func performLoad() async {
        isLoading = true
        errorMessage = nil
        // `hasSuccessfulLoad` describes the last outcome, not the in-flight
        // request. Clearing it here made every reload transiently render the
        // failure screen, which destroyed and rebuilt the onboarding view and
        // reset its step back to `.welcome` after a successful Apple sign-in.
        defer {
            isLoading = false
            hasLoaded = true
            listLoadTask = nil
        }

        do {
            hatcheries = try await hatcheryService.hatcheries()
            hasSuccessfulLoad = true
        } catch {
            hatcheries = []
            hasSuccessfulLoad = false
            errorMessage = error.localizedDescription
        }
    }

    /// Loads the list plus the live values used by the Figma management cards.
    /// Hatchery rows still render when a dashboard request cannot be resolved
    /// (for example before a device has produced its first reading).
    func loadManagement(refreshHatcheries: Bool = false) async {
        guard !isLoadingManagement else { return }
        isLoadingManagement = true
        defer { isLoadingManagement = false }

        // The initial picker load already has the hatchery rows. Do not add a
        // second network request merely to open Management; callers that have
        // just saved can explicitly ask for fresh rows.
        if refreshHatcheries || !hasSuccessfulLoad {
            await load()
        }
        guard hasSuccessfulLoad else {
            managementSummaries = []
            return
        }

        // Each card is independent. Fetch them concurrently and reuse the
        // hatchery rows already loaded above instead of serially refetching the
        // parent row for every card.
        let loadedHatcheries = hatcheries
        let overviewByHatcheryID = await withTaskGroup(
            of: (UUID, HatcheryOverview?).self,
            returning: [UUID: HatcheryOverview].self
        ) { group in
            for hatchery in loadedHatcheries {
                group.addTask { [hatcheryService] in
                    (
                        hatchery.id,
                        try? await hatcheryService.loadOverview(hatcheryID: hatchery.id)
                    )
                }
            }

            var overviews: [UUID: HatcheryOverview] = [:]
            for await (hatcheryID, overview) in group {
                if let overview {
                    overviews[hatcheryID] = overview
                }
            }
            return overviews
        }

        managementSummaries = loadedHatcheries.map { hatchery in
            HatcheryManagementSummary(
                hatchery: hatchery,
                overview: overviewByHatcheryID[hatchery.id]
            )
        }
    }

    /// Persists a hatchery-management edit through the same service used by
    /// setup. Passing the unchanged grid and dimensions makes this safe for a
    /// name-only edit while retaining the service's nest-safety validation for
    /// future dimension edits.
    func update(
        hatchery: HatcheryEntity,
        name: String
    ) async -> HatcheryEntity? {
        guard updatingHatcheryID == nil else { return nil }
        updatingHatcheryID = hatchery.id
        errorMessage = nil
        defer { updatingHatcheryID = nil }

        do {
            let updated = try await hatcheryService.updateHatchery(
                id: hatchery.id,
                UpdateHatcheryInput(
                    name: name,
                    numberOfRows: hatchery.numberOfRows,
                    numberOfColumns: hatchery.numberOfColumns,
                    lengthM: hatchery.lengthM,
                    widthM: hatchery.widthM
                )
            )
            if let index = hatcheries.firstIndex(where: { $0.id == updated.id }) {
                hatcheries[index] = updated
            }
            await loadManagement()
            return updated
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Builds a session for a hatchery the user picked from the list. Modern
    /// rows restore their private photo and exact persisted geometry; only
    /// legacy rows with no layout revision use the compatibility placeholder.
    func session(for hatchery: HatcheryEntity) async -> HatcherySessionState? {
        guard openingHatcheryID == nil else { return nil }
        openingHatcheryID = hatchery.id
        errorMessage = nil
        defer { openingHatcheryID = nil }

        do {
            // The list can be stale after a rename or a re-scan on another
            // device. Reconstruct against the authoritative row so its
            // dimensions always agree with the immutable current revision.
            if let layoutService {
                // These two records are independent reads. Starting them
                // together removes one round-trip before the unavoidable
                // private-photo download begins.
                async let currentHatchery = hatcheryService.hatchery(id: hatchery.id)
                async let currentLayout = layoutService.currentLayout(hatcheryID: hatchery.id)
                let (resolvedHatchery, layout) = try await (currentHatchery, currentLayout)

                if let layout {
                    let sourcePhotoData = try await layoutService.sourcePhotoData(for: layout)
                    return try await HatcherySessionState.reconstructed(
                        from: resolvedHatchery,
                        layout: layout,
                        sourcePhotoData: sourcePhotoData
                    )
                }

                let legacySession = HatcherySessionState.reconstructed(from: resolvedHatchery)
                if legacySession == nil {
                    errorMessage = "This hatchery's saved dimensions are too small to open."
                }
                return legacySession
            }

            let currentHatchery = try await hatcheryService.hatchery(id: hatchery.id)
            let legacySession = HatcherySessionState.reconstructed(from: currentHatchery)
            if legacySession == nil {
                errorMessage = "This hatchery's saved dimensions are too small to open."
            }
            return legacySession
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Restores the first hatchery in the backend's stable list ordering for
    /// app launch. The repository orders the list by name, so Hatch_01 opens
    /// before later hatcheries while keeping selection logic in one place.
    func firstSession() async -> HatcherySessionState? {
        guard hasSuccessfulLoad, let firstHatchery = hatcheries.first else { return nil }
        return await session(for: firstHatchery)
    }
}
