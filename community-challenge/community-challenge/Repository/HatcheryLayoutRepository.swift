import Foundation

/// Persistence boundary for immutable hatchery scan revisions. Layout writes
/// deliberately use lifecycle RPCs rather than direct table mutations so a
/// partially uploaded photo can never become the current map.
protocol HatcheryLayoutRepository: Sendable {
    func fetchCurrent(hatcheryID: UUID) async throws -> HatcheryLayoutRevision?
    func fetch(id: UUID) async throws -> HatcheryLayoutRevision?
    func begin(_ request: HatcheryLayoutSaveRequest) async throws -> HatcheryLayoutRevision
    func beginNewHatchery(_ request: HatcheryLayoutSaveRequest) async throws -> HatcheryLayoutRevision
    func finalize(
        layoutID: UUID,
        sourcePhoto: HatcherySourcePhoto?
    ) async throws -> HatcheryLayoutRevision
    /// Serializes a failed client attempt with finalization. It returns the
    /// locked revision so callers only remove a photo after the server has
    /// conclusively moved it out of `uploading`.
    func abandon(layoutID: UUID) async throws -> HatcheryLayoutRevision
    /// Removes a failed revision after its private Storage object is gone.
    /// For a failed first layout this also removes the otherwise-hidden parent
    /// hatchery, so an interrupted setup never becomes a permanent ghost row.
    func purgeFailed(layoutID: UUID) async throws
}

/// Private object storage for the source photo of a layout revision.
protocol HatcheryPhotoStore: Sendable {
    func upload(path: String, data: Data, contentType: String) async throws
    func download(path: String) async throws -> Data
    func delete(path: String) async throws
}

nonisolated enum HatcheryLayoutStorage {
    static let bucketName = "hatchery-layouts"
}
