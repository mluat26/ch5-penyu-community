import Foundation

/// Whether a scan has a real camera photo or intentionally uses the blank
/// canvas from the “Skip for now” path. A skipped hatchery never uploads a
/// fabricated image.
nonisolated enum HatcheryCaptureMode: String, Codable, Hashable, Sendable {
    case captured
    case skipped
}

/// Lifecycle state of an immutable saved scan revision.
nonisolated enum HatcheryLayoutRevisionState: String, Codable, Hashable, Sendable {
    case uploading
    case ready
    case superseded
    case failed
}

/// The immutable, durable form of a hatchery scan. The image lives in private
/// Supabase Storage; this value carries only its object path and metadata.
nonisolated struct HatcheryLayoutRevision: Identifiable, Hashable, Sendable {
    let id: UUID
    let hatcheryID: UUID
    let revision: Int
    let createdBy: UUID
    let state: HatcheryLayoutRevisionState
    let isCurrent: Bool
    let captureMode: HatcheryCaptureMode
    let sourcePhotoPath: String?
    let sourcePhotoMIMEType: String?
    let sourcePhotoBytes: Int64?
    let sourcePhotoWidth: Int?
    let sourcePhotoHeight: Int?
    let name: String
    let dimension: HatcheryDimension
    let grid: HatcheryGridSnapshot
    let boundary: HatcheryBoundary
    let sandRegion: HatcherySandRegion
    let layoutSchemaVersion: Int
    let processingVersion: String
    let createdAt: Date
    let finalizedAt: Date?
    let supersededAt: Date?
}

/// JPEG data and its image dimensions, ready for the immutable Storage upload.
nonisolated struct HatcherySourcePhoto: Sendable {
    static let jpegMIMEType = "image/jpeg"

    let data: Data
    let width: Int
    let height: Int

    init(
        data: Data,
        width: Int,
        height: Int
    ) {
        self.data = data
        self.width = width
        self.height = height
    }
}

/// Complete client-side payload for one new immutable scan revision.
nonisolated struct HatcheryLayoutSaveRequest: Sendable {
    let layoutID: UUID
    let hatcheryID: UUID
    let name: String
    let dimension: HatcheryDimension
    let boundary: HatcheryBoundary
    let sandRegion: HatcherySandRegion
    let grid: HatcheryGridSnapshot
    let processingVersion: String
    let sourcePhoto: HatcherySourcePhoto?

    init(
        layoutID: UUID = UUID(),
        hatcheryID: UUID,
        name: String,
        dimension: HatcheryDimension,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion,
        grid: HatcheryGridSnapshot,
        processingVersion: String,
        sourcePhoto: HatcherySourcePhoto?
    ) {
        self.layoutID = layoutID
        self.hatcheryID = hatcheryID
        self.name = name
        self.dimension = dimension
        self.boundary = boundary
        self.sandRegion = sandRegion
        self.grid = grid
        self.processingVersion = processingVersion
        self.sourcePhoto = sourcePhoto
    }

    var captureMode: HatcheryCaptureMode {
        sourcePhoto == nil ? .skipped : .captured
    }
}
