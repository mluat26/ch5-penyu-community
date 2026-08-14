import UIKit

extension HatcherySessionState {
    /// Rebuilds a session for a legacy hatchery loaded from the database.
    ///
    /// Modern hatcheries use the persisted-layout overload below. This remains
    /// only for rows created before scan-layout persistence shipped, so their
    /// sample image is clearly a compatibility fallback—not a saved scan.
    ///
    /// The grid is regenerated from the stored dimensions by the generator that
    /// produced the persisted row/column counts in the first place, so the two
    /// agree and nests land in their original sections. Returns nil only when
    /// the stored dimensions are too small for a single section, which the
    /// creation flow already rejects.
    static func reconstructed(from hatchery: HatcheryEntity) -> HatcherySessionState? {
        let dimension = HatcheryDimension(
            widthM: hatchery.widthM,
            heightM: hatchery.lengthM
        )
        guard
            let grid = HatcheryGridGenerator.generate(
                dimension: dimension,
                boundary: .fullImage
            )
        else {
            return nil
        }

        let placeholder = UIImage(named: "HatcherySamplePhoto") ?? UIImage()

        return HatcherySessionState(
            hatchery: hatchery,
            photo: placeholder,
            rectifiedPhoto: placeholder,
            usesMockImage: true,
            boundary: .fullImage,
            sandRegion: .default(from: .fullImage),
            grid: grid
        )
    }

    /// Rebuilds a session from the exact current scan revision. The source
    /// image, perspective boundary, sand mask, and active-cell grid all come
    /// from the durable layout record rather than being regenerated from a
    /// placeholder.
    @MainActor
    static func reconstructed(
        from hatchery: HatcheryEntity,
        layout: HatcheryLayoutRevision,
        sourcePhotoData: Data?
    ) async throws -> HatcherySessionState {
        guard
            layout.hatcheryID == hatchery.id,
            layout.state == .ready,
            layout.isCurrent,
            layout.dimension.widthM == hatchery.widthM,
            layout.dimension.heightM == hatchery.lengthM,
            layout.grid.rows == hatchery.numberOfRows,
            layout.grid.columns == hatchery.numberOfColumns
        else {
            throw HatcheryLayoutPersistenceError.unexpectedLayoutState
        }

        let images = try await HatcheryImageProcessor.restoredImagePayloads(
            captureMode: layout.captureMode,
            sourcePhotoData: sourcePhotoData,
            boundary: layout.boundary
        )
        try Task.checkCancellation()

        let grid = try layout.grid.makeGrid(boundary: layout.boundary)

        return HatcherySessionState(
            hatchery: hatchery,
            photo: HatcheryImageProcessor.displayImage(from: images.photo),
            rectifiedPhoto: HatcheryImageProcessor.displayImage(from: images.rectifiedPhoto),
            usesMockImage: false,
            boundary: layout.boundary,
            sandRegion: layout.sandRegion,
            grid: grid
        )
    }
}
