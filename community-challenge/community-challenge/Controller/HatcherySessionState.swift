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
