import Foundation

/// UI-only draft. Bucket ID, user-facing nest number, and inspection date are
/// kept here because their backing Supabase columns have not been confirmed.
struct NestFormDraft: Hashable {
    var bucketID: String
    var nestNumber: String
    var section: String
    var numberOfEggs: String
    var collectionDate: String
    var inspectionDate: String
    var hatchDate: String

    static let sample = NestFormDraft(
        bucketID: "00000000",
        nestNumber: "055",
        section: "Section B",
        numberOfEggs: "100",
        collectionDate: "01.01.2026",
        inspectionDate: "01.02.2026",
        hatchDate: "01.03.2026"
    )
}
