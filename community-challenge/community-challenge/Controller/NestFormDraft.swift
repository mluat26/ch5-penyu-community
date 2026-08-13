import Foundation

enum NestInspectionDateMode: Hashable {
    case selectDate
    case afterCollectionDays
}

/// UI-only draft. Bucket ID, user-facing nest number, and inspection date are
/// kept here because their backing Supabase columns have not been confirmed.
struct NestFormDraft: Hashable {
    var bucketID: String
    var nestNumber: String
    var section: String
    var sectionRow: Int?
    var sectionColumn: Int?
    var numberOfEggs: String
    var collectionDate: String
    var inspectionDate: String
    var hatchDate: String
    var inspectionDateMode: NestInspectionDateMode
    var daysAfterCollection: String
    /// Presentation-only copy used by the Figma preview until live timeline data exists.
    var daysLeftDisplay: String

    static let sample = NestFormDraft(
        bucketID: "00000000",
        nestNumber: "055",
        section: "",
        sectionRow: nil,
        sectionColumn: nil,
        numberOfEggs: "100",
        collectionDate: "01.01.2026",
        inspectionDate: "01.02.2026",
        hatchDate: "01.03.2026",
        inspectionDateMode: .afterCollectionDays,
        daysAfterCollection: "59",
        daysLeftDisplay: "90"
    )
}
