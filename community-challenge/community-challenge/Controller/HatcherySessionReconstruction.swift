import UIKit

extension HatcherySessionState {
    /// Rebuilds a session for a hatchery loaded from the database.
    ///
    /// Only name, shape, dimensions, and grid counts are persisted. The photo,
    /// boundary, and sand region exist solely because the scan flow produced
    /// them and have no Supabase Storage contract yet, so switching to an
    /// existing hatchery reconstructs the same placeholders `skipScanning()`
    /// uses.
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
}
