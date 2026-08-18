import Foundation

/// Coordinates the non-transactional Storage upload with the transactional
/// layout RPC. The database never points a current layout at an object until
/// upload and finalization have both succeeded.
nonisolated struct HatcheryLayoutService: Sendable {
    private let repository: any HatcheryLayoutRepository
    private let photoStore: any HatcheryPhotoStore

    init(
        repository: any HatcheryLayoutRepository,
        photoStore: any HatcheryPhotoStore
    ) {
        self.repository = repository
        self.photoStore = photoStore
    }

    func save(_ request: HatcheryLayoutSaveRequest) async throws -> HatcheryLayoutRevision {
        try request.grid.validate(boundary: request.boundary)
        guard request.sandRegion.isValid else {
            throw HatcheryLayoutPersistenceError.invalidBoundary
        }

        let pending = try await repository.begin(request)
        return try await uploadAndFinalize(pending: pending, request: request)
    }

    /// Creates the hatchery row and its pending first layout atomically before
    /// touching Storage, so a crash cannot expose a brand-new hatchery without
    /// the layout required to open it.
    func createNewHatchery(
        _ request: HatcheryLayoutSaveRequest
    ) async throws -> HatcheryLayoutRevision {
        try request.grid.validate(boundary: request.boundary)
        guard request.sandRegion.isValid else {
            throw HatcheryLayoutPersistenceError.invalidBoundary
        }

        let pending = try await repository.beginNewHatchery(request)
        return try await uploadAndFinalize(pending: pending, request: request)
    }

    /// Removes every layout photograph belonging to the signed-in person.
    ///
    /// Called immediately before the account deletion RPC, because the rows
    /// that record which object belongs to whom are about to go with it. It has
    /// to happen through the Storage API: Postgres refuses a direct delete on
    /// `storage.objects` outright, so the account deletion function cannot do
    /// this itself no matter what privileges it runs with.
    ///
    /// Best effort per object, and non-throwing overall. Deleting an account is
    /// something a person is entitled to; one stubborn file must not be able to
    /// stand in the way of it. A file left behind is a storage cost, and the
    /// alternative is an account that cannot be closed.
    func deleteCurrentUserPhotos() async {
        guard let paths = try? await repository.currentUserPhotoPaths() else { return }

        for path in paths {
            try? await photoStore.delete(path: path)
        }
    }

    private func uploadAndFinalize(
        pending: HatcheryLayoutRevision,
        request: HatcheryLayoutSaveRequest
    ) async throws -> HatcheryLayoutRevision {
        if pending.state == .ready {
            // The client did not receive a previous finalize response. The
            // immutable revision is already committed, so it is safe to reuse.
            return pending
        }
        guard pending.state == .uploading,
              pending.captureMode == request.captureMode
        else {
            throw HatcheryLayoutPersistenceError.unexpectedLayoutState
        }

        do {
            if let sourcePhoto = request.sourcePhoto {
                guard let path = pending.sourcePhotoPath else {
                    throw HatcheryLayoutPersistenceError.missingSourcePhoto
                }
                try await photoStore.upload(
                    path: path,
                    data: sourcePhoto.data,
                    contentType: HatcherySourcePhoto.jpegMIMEType
                )
            }

            return try await repository.finalize(
                layoutID: pending.id,
                sourcePhoto: request.sourcePhoto
            )
        } catch {
            // A network response can fail after Postgres committed the
            // transaction. Check first so we never delete a legitimately ready
            // immutable source photo.
            if let recovered = try? await repository.fetch(id: pending.id),
               recovered.state == .ready {
                return recovered
            }

            // `abandon` locks the revision. If finalization won the race it
            // returns `.ready`; otherwise it atomically changes the revision
            // to `.failed`. The Storage policy permits deletion only for that
            // failed state, so a late server finalization can never commit a
            // ready layout whose photo this client has just removed.
            if let abandoned = try? await repository.abandon(layoutID: pending.id) {
                if abandoned.state == .ready {
                    return abandoned
                }

                if abandoned.state == .failed {
                    if let path = abandoned.sourcePhotoPath {
                        try? await photoStore.delete(path: path)
                    }
                    // Best effort only: if the network drops after the object
                    // is deleted, the failed revision is inert and can be
                    // purged safely on the next cleanup pass.
                    try? await repository.purgeFailed(layoutID: abandoned.id)
                }
            }
            throw error
        }
    }

    func currentLayout(hatcheryID: UUID) async throws -> HatcheryLayoutRevision? {
        try await repository.fetchCurrent(hatcheryID: hatcheryID)
    }

    func sourcePhotoData(for layout: HatcheryLayoutRevision) async throws -> Data? {
        switch layout.captureMode {
        case .skipped:
            return nil
        case .captured:
            guard let path = layout.sourcePhotoPath else {
                throw HatcheryLayoutPersistenceError.missingSourcePhoto
            }
            return try await photoStore.download(path: path)
        }
    }
}
