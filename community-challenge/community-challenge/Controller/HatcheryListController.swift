import Foundation
import Observation

/// The extra dashboard information rendered on each hatchery-management card.
/// A failed telemetry query should not hide an otherwise valid hatchery, so the
/// overview remains optional and the list itself stays usable.
struct HatcheryManagementSummary: Identifiable, Hashable {
    let hatchery: HatcheryEntity
    let overview: HatcheryOverview?
    /// Sections that fall on sand, from the current layout's stored mask.
    ///
    /// Nil when the hatchery has no layout revision, or when reading it
    /// failed. `sectionsInUse` resolves that case rather than callers, so a
    /// missing layout cannot quietly become a zero.
    let activeSectionCount: Int?

    var id: UUID { hatchery.id }

    /// The sections a nest can actually be placed in.
    ///
    /// Falls back to the whole grid without a layout, and that is the right
    /// answer rather than a guess: `HatcheryGridGenerator` marks a cell active
    /// when there is no sand region to test it against, so a hatchery with no
    /// mask genuinely has every cell in use.
    var sectionsInUse: Int { activeSectionCount ?? hatchery.sectionCount }
}

@MainActor
@Observable
final class HatcheryListController {
    private(set) var hatcheries: [HatcheryEntity] = []
    private(set) var managementSummaries: [HatcheryManagementSummary] = []
    private(set) var isLoading = false
    private(set) var isLoadingManagement = false
    private(set) var updatingHatcheryID: UUID?
    private(set) var deletingHatcheryID: UUID?
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

        // A second concurrent pass rather than a field on `HatcheryOverview`:
        // the overview is built by `HatcheryService`, which has no layout
        // access, and the count comes from the layout's stored sand mask.
        //
        // This reads the revision row only. `sourcePhotoData` is what costs a
        // private download, and it is deliberately not called here -- opening
        // Management must not pull every hatchery's photo.
        let activeSectionsByHatcheryID = await withTaskGroup(
            of: (UUID, Int?).self,
            returning: [UUID: Int].self
        ) { group in
            for hatchery in loadedHatcheries {
                group.addTask { [layoutService] in
                    let layout = try? await layoutService?.currentLayout(
                        hatcheryID: hatchery.id
                    )
                    return (hatchery.id, layout?.grid.activeCells.count)
                }
            }

            var counts: [UUID: Int] = [:]
            for await (hatcheryID, count) in group {
                if let count {
                    counts[hatcheryID] = count
                }
            }
            return counts
        }

        managementSummaries = loadedHatcheries.map { hatchery in
            HatcheryManagementSummary(
                hatchery: hatchery,
                overview: overviewByHatcheryID[hatchery.id],
                activeSectionCount: activeSectionsByHatcheryID[hatchery.id]
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

    /// Deletes a hatchery, and returns whether it went.
    ///
    /// The order is the whole of it, and it mirrors `AppContainer.deleteAccount`
    /// for the same reason. The refusal comes first: a hatchery still holding
    /// nests keeps its photographs, because removing them is not undoable and
    /// the delete is about to be turned down anyway. Then the photographs, then
    /// the row -- `hatchery_layout` cascades with the hatchery, and the bucket's
    /// delete policy is written against a layout row that would no longer
    /// exist, so this is the last moment those objects can be removed at all.
    func delete(_ hatchery: HatcheryEntity) async -> Bool {
        guard deletingHatcheryID == nil else { return false }
        deletingHatcheryID = hatchery.id
        errorMessage = nil
        defer { deletingHatcheryID = nil }

        do {
            try await hatcheryService.assertHatcheryIsEmpty(id: hatchery.id)
            await layoutService?.deletePhotos(hatcheryID: hatchery.id)
            try await hatcheryService.deleteHatchery(id: hatchery.id)
            hatcheries.removeAll { $0.id == hatchery.id }
            managementSummaries.removeAll { $0.id == hatchery.id }
            await loadManagement()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
                    errorMessage = String(localized: "This hatchery's saved dimensions are too small to open.")
                }
                return legacySession
            }

            let currentHatchery = try await hatcheryService.hatchery(id: hatchery.id)
            let legacySession = HatcherySessionState.reconstructed(from: currentHatchery)
            if legacySession == nil {
                errorMessage = String(localized: "This hatchery's saved dimensions are too small to open.")
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
