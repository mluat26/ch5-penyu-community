import UIKit

/// Presentation state for the currently configured hatchery.
///
/// Photos, rectification, grid projection, and sand-region metadata stay here
/// until their Supabase Storage and database contract is defined.
struct HatcherySessionState: Identifiable {
    let hatchery: HatcheryEntity
    let photo: UIImage
    let rectifiedPhoto: UIImage
    let usesMockImage: Bool
    let boundary: HatcheryBoundary
    let sandRegion: HatcherySandRegion?
    let grid: HatcheryGrid

    var id: UUID { hatchery.id }

    init(
        hatchery: HatcheryEntity,
        photo: UIImage,
        rectifiedPhoto: UIImage,
        usesMockImage: Bool = false,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion? = nil,
        grid: HatcheryGrid
    ) {
        self.hatchery = hatchery
        self.photo = photo
        self.rectifiedPhoto = rectifiedPhoto
        self.usesMockImage = usesMockImage
        self.boundary = boundary
        self.sandRegion = sandRegion
        self.grid = grid
    }

    /// Rebuilds a session for a hatchery loaded from the database.
    ///
    /// Only name, shape, dimensions, and grid counts are persisted. The photo,
    /// boundary, and sand region exist solely because the scan flow produced
    /// them and have no Supabase Storage contract yet, so opening an existing
    /// hatchery reconstructs the same placeholders `skipScanning()` uses.
    ///
    /// The grid is regenerated from the stored dimensions by the generator that
    /// produced the persisted row and column counts in the first place, so the
    /// two agree and nests land in their original sections. Returns nil only
    /// when the stored dimensions are too small for a single section, which the
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
            grid: grid
        )
    }()
}
#endif
