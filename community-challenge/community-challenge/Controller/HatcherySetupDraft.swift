import UIKit

struct HatcherySetupDraft {
    var name = ""
    var image: UIImage?
    var rectifiedImage: UIImage?
    var usesMockImage = false
    var boundary: HatcheryBoundary?
    /// The editable usable-sand outline. It is separate from `boundary`,
    /// which remains the four-corner perspective plane for rectification.
    var sandRegion: HatcherySandRegion?
    var dimension = HatcheryDimension(widthM: 15, heightM: 7)
    var grid: HatcheryGrid?
}
