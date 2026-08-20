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
    /// Whether this hatchery was ever photographed. A skipped scan still has a
    /// valid grid, so only this distinguishes it from a real capture — the
    /// dashboard shows its scan prompt rather than a blank photo.
    let captureMode: HatcheryCaptureMode

    var hasBeenScanned: Bool { captureMode == .captured }

    var id: UUID { hatchery.id }

    init(
        hatchery: HatcheryEntity,
        photo: UIImage,
        rectifiedPhoto: UIImage,
        usesMockImage: Bool = false,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion? = nil,
        rectifiedSandRegion: HatcherySandRegion? = nil,
        grid: HatcheryGrid,
        captureMode: HatcheryCaptureMode = .captured
    ) {
        self.hatchery = hatchery
        self.photo = photo
        self.rectifiedPhoto = rectifiedPhoto
        self.usesMockImage = usesMockImage
        self.boundary = boundary
        self.sandRegion = sandRegion
        self.rectifiedSandRegion = rectifiedSandRegion
        self.grid = grid
        self.captureMode = captureMode
    }

    /// Rebuilds a session for a legacy hatchery loaded from the database.
    ///
    /// Modern hatcheries use the persisted-layout overload below. This remains
    /// only for rows created before scan-layout persistence shipped, so their
    /// sample image is clearly a compatibility fallback—not a saved scan.
    ///
    /// The grid is built directly from the entity's own stored row/column
    /// counts rather than re-derived from its dimensions, so nests land in
    /// their original sections no matter how the section-sizing algorithm
    /// that originally produced those counts has since changed.
    static func reconstructed(from hatchery: HatcheryEntity) -> HatcherySessionState? {
        guard hatchery.numberOfRows > 0, hatchery.numberOfColumns > 0 else { return nil }

        let cellSize = hatchery.cellSize
        let boundary = HatcheryBoundary.fullImage
        let sections = (0..<hatchery.numberOfRows).flatMap { row in
            (0..<hatchery.numberOfColumns).map { column in
                HatcherySection(
                    id: "\(HatcheryGrid.columnLabel(column))\(row + 1)",
                    row: row,
                    column: column,
                    widthM: cellSize.width,
                    heightM: cellSize.height,
                    boundary: boundary.sectionBoundary(
                        row: row,
                        column: column,
                        rowCount: hatchery.numberOfRows,
                        columnCount: hatchery.numberOfColumns
                    )
                )
            }
        }
        let grid = HatcheryGrid(rows: hatchery.numberOfRows, columns: hatchery.numberOfColumns, sections: sections)

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
            grid: grid,
            captureMode: layout.captureMode
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
