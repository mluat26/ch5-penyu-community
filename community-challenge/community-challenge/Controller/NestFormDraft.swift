import Foundation

enum NestInspectionDateMode: Hashable {
    case selectDate
    case afterCollectionDays
}

/// In-progress form state. Everything is a string because it is mid-edit; the
/// controller parses and validates on the way out.
struct NestFormDraft: Hashable {
    var bucketID: String
    var nestNumber: String
    /// The logger named by the bucket's NFC tag, once one has been scanned.
    ///
    /// This, not `bucketID`, is what attaches readings to the nest: the tag
    /// carries a `device.id`, and the assignment is made against that. The
    /// bucket ID stays a human label for the container.
    var scannedDeviceID: UUID? = nil
    var section: String
    var sectionRow: Int?
    var sectionColumn: Int?
    /// Set only once the map step has been completed, which is optional.
    var latitude: Double? = nil
    var longitude: Double? = nil
    var locationAddress: String? = nil
    var numberOfEggs: String
    var collectionDate: String
    var inspectionDate: String
    var hatchDate: String
    /// Set once someone types a hatch date themselves, which stops the
    /// collection-date estimate replacing it. Nothing on the create form
    /// offers that yet; the flag exists so adding one cannot silently
    /// reintroduce the overwrite.
    var hasManualHatchDate = false
    var inspectionDateMode: NestInspectionDateMode
    /// How long after collection the first inspection is due. Resolved into
    /// `inspectionDate` by the controller; it is not the incubation period,
    /// which the hatch estimate owns separately.
    var daysAfterCollection: String

    /// A `var`, not `let`: this must re-evaluate `Date()` on every access, not
    /// bake in whatever moment the app first touched it. `inspectionDate` and
    /// `hatchDate` are seeded to today as inert placeholders -- correct values
    /// depend on `daysAfterCollection` and the incubation constant, which live
    /// on `NestController`, so the controller derives them for real as soon as
    /// its timeline screen appears. A placeholder of "today" is only ever
    /// visible for the one frame before that happens, and even then it is a
    /// plausible date rather than a stale one.
    static var sample: NestFormDraft {
        let today = AppDateFormatting.nestDraftDateString(Date())
        return NestFormDraft(
            // Placeholders only. Both identifiers are issued by
            // `NestController.prepareIdentifiers()` when the identity screen
            // appears; these are what shows if that lookup fails, and they are
            // the correct values for a hatchery's very first nest.
            bucketID: "001",
            nestNumber: "001",
            section: "",
            sectionRow: nil,
            sectionColumn: nil,
            numberOfEggs: "100",
            collectionDate: today,
            inspectionDate: today,
            hatchDate: today,
            inspectionDateMode: .afterCollectionDays,
            daysAfterCollection: "5"
        )
    }
}
