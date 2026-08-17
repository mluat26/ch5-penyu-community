import UIKit

/// Presentation state for the currently configured hatchery.
///
/// The private source photo and normalized layout are persisted as an immutable
/// scan revision; rectification and section projection are rebuilt locally for
/// the active session.
struct HatcherySessionState: Identifiable {
    let hatchery: HatcheryEntity
    let photo: UIImage
    let rectifiedPhoto: UIImage
    let usesMockImage: Bool
    let boundary: HatcheryBoundary
    let sandRegion: HatcherySandRegion?
    /// Sand outline in the coordinate space of `rectifiedPhoto`.
    let rectifiedSandRegion: HatcherySandRegion?
    let grid: HatcheryGrid

    var id: UUID { hatchery.id }

    init(
        hatchery: HatcheryEntity,
        photo: UIImage,
        rectifiedPhoto: UIImage,
        usesMockImage: Bool = false,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion? = nil,
        rectifiedSandRegion: HatcherySandRegion? = nil,
        grid: HatcheryGrid
    ) {
        self.hatchery = hatchery
        self.photo = photo
        self.rectifiedPhoto = rectifiedPhoto
        self.usesMockImage = usesMockImage
        self.boundary = boundary
        self.sandRegion = sandRegion
        self.rectifiedSandRegion = rectifiedSandRegion
        self.grid = grid
    }

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
            boundary: layout.boundary,
            sandRegion: layout.sandRegion
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
            rectifiedSandRegion: images.rectifiedSandRegion,
            grid: grid
        )
    }
}

#if DEBUG
extension HatcherySessionState {
    static let previewSample: HatcherySessionState = {
        let boundary = HatcheryBoundary.fullImage
        let dimension = HatcheryDimension(widthM: 8, heightM: 6)
        let grid = HatcheryGridGenerator.generate(
            dimension: dimension,
            boundary: boundary
        )!
        let photo = UIImage(named: "HatcherySamplePhoto") ?? UIImage()

        return HatcherySessionState(
            hatchery: HatcheryEntity(
                id: UUID(),
                name: "Hatch_01",
                shape: .rectangle,
                numberOfRows: grid.rows,
                numberOfColumns: grid.columns,
                lengthM: dimension.heightM,
                widthM: dimension.widthM,
                organizationID: nil
            ),
            photo: photo,
            rectifiedPhoto: photo,
            usesMockImage: true,
            boundary: boundary,
            sandRegion: .default(from: boundary),
            rectifiedSandRegion: .default(from: .fullImage),
            grid: grid
        )
    }()
}
#endif
