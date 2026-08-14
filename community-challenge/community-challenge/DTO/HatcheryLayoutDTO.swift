import Foundation

/// Wire representation returned by the immutable `hatchery_layout` revision
/// table and its lifecycle RPCs.
nonisolated struct HatcheryLayoutDTO: Codable, Sendable {
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
    let lengthM: Double
    let widthM: Double
    let gridRows: Int
    let gridColumns: Int
    let boundary: HatcheryBoundary
    let sandRegion: HatcherySandRegion
    let grid: HatcheryGridSnapshot
    let layoutSchemaVersion: Int
    let processingVersion: String
    let createdAt: Date
    let finalizedAt: Date?
    let supersededAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case hatcheryID = "hatchery_id"
        case revision
        case createdBy = "created_by"
        case state
        case isCurrent = "is_current"
        case captureMode = "capture_mode"
        case sourcePhotoPath = "source_photo_path"
        case sourcePhotoMIMEType = "source_photo_mime_type"
        case sourcePhotoBytes = "source_photo_bytes"
        case sourcePhotoWidth = "source_photo_width"
        case sourcePhotoHeight = "source_photo_height"
        case name
        case lengthM = "length_m"
        case widthM = "width_m"
        case gridRows = "grid_rows"
        case gridColumns = "grid_columns"
        case boundary = "boundary_json"
        case sandRegion = "sand_region_json"
        case grid = "grid_json"
        case layoutSchemaVersion = "layout_schema_version"
        case processingVersion = "processing_version"
        case createdAt = "created_at"
        case finalizedAt = "finalized_at"
        case supersededAt = "superseded_at"
    }
}

extension HatcheryLayoutDTO {
    nonisolated func toEntity() throws -> HatcheryLayoutRevision {
        guard
            revision > 0,
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            lengthM.isFinite,
            widthM.isFinite,
            lengthM > 0,
            widthM > 0,
            gridRows == grid.rows,
            gridColumns == grid.columns,
            layoutSchemaVersion == HatcheryGridSnapshot.currentSchemaVersion,
            grid.schemaVersion == HatcheryGridSnapshot.currentSchemaVersion,
            boundary.isValid,
            sandRegion.isValid,
            isCurrent == (state == .ready)
        else {
            throw DataMappingError.missingRequiredValue(field: "valid hatchery layout revision")
        }

        try grid.validate(boundary: boundary)

        switch captureMode {
        case .captured:
            guard sourcePhotoPath != nil else {
                throw DataMappingError.missingRequiredValue(field: "hatchery layout source photo")
            }
            if state == .ready || state == .superseded {
                guard
                    sourcePhotoMIMEType == HatcherySourcePhoto.jpegMIMEType,
                    sourcePhotoBytes ?? 0 > 0,
                    sourcePhotoWidth ?? 0 > 0,
                    sourcePhotoHeight ?? 0 > 0
                else {
                    throw DataMappingError.missingRequiredValue(field: "hatchery layout source photo metadata")
                }
            }
        case .skipped:
            guard
                sourcePhotoPath == nil,
                sourcePhotoMIMEType == nil,
                sourcePhotoBytes == nil,
                sourcePhotoWidth == nil,
                sourcePhotoHeight == nil
            else {
                throw DataMappingError.missingRequiredValue(field: "skipped hatchery layout photo")
            }
        }

        return HatcheryLayoutRevision(
            id: id,
            hatcheryID: hatcheryID,
            revision: revision,
            createdBy: createdBy,
            state: state,
            isCurrent: isCurrent,
            captureMode: captureMode,
            sourcePhotoPath: sourcePhotoPath,
            sourcePhotoMIMEType: sourcePhotoMIMEType,
            sourcePhotoBytes: sourcePhotoBytes,
            sourcePhotoWidth: sourcePhotoWidth,
            sourcePhotoHeight: sourcePhotoHeight,
            name: name,
            dimension: HatcheryDimension(widthM: widthM, heightM: lengthM),
            grid: grid,
            boundary: boundary,
            sandRegion: sandRegion,
            layoutSchemaVersion: layoutSchemaVersion,
            processingVersion: processingVersion,
            createdAt: createdAt,
            finalizedAt: finalizedAt,
            supersededAt: supersededAt
        )
    }
}

nonisolated struct HatcheryLayoutBeginDTO: Encodable, Sendable {
    let layoutID: UUID
    let hatcheryID: UUID
    let name: String
    let lengthM: Double
    let widthM: Double
    let gridRows: Int
    let gridColumns: Int
    let captureMode: HatcheryCaptureMode
    let boundary: HatcheryBoundary
    let sandRegion: HatcherySandRegion
    let grid: HatcheryGridSnapshot
    let processingVersion: String

    enum CodingKeys: String, CodingKey {
        case layoutID = "p_layout_id"
        case hatcheryID = "p_hatchery_id"
        case name = "p_name"
        case lengthM = "p_length_m"
        case widthM = "p_width_m"
        case gridRows = "p_grid_rows"
        case gridColumns = "p_grid_columns"
        case captureMode = "p_capture_mode"
        case boundary = "p_boundary_json"
        case sandRegion = "p_sand_region_json"
        case grid = "p_grid_json"
        case processingVersion = "p_processing_version"
    }
}

nonisolated struct HatcheryLayoutFinalizeDTO: Encodable, Sendable {
    let layoutID: UUID
    let sourcePhotoMIMEType: String?
    let sourcePhotoBytes: Int64?
    let sourcePhotoWidth: Int?
    let sourcePhotoHeight: Int?

    enum CodingKeys: String, CodingKey {
        case layoutID = "p_layout_id"
        case sourcePhotoMIMEType = "p_source_photo_mime_type"
        case sourcePhotoBytes = "p_source_photo_bytes"
        case sourcePhotoWidth = "p_source_photo_width"
        case sourcePhotoHeight = "p_source_photo_height"
    }
}

nonisolated struct HatcheryLayoutIDDTO: Encodable, Sendable {
    let layoutID: UUID

    enum CodingKeys: String, CodingKey {
        case layoutID = "p_layout_id"
    }
}

extension HatcheryLayoutBeginDTO {
    init(request: HatcheryLayoutSaveRequest) {
        self.init(
            layoutID: request.layoutID,
            hatcheryID: request.hatcheryID,
            name: request.name,
            lengthM: request.dimension.heightM,
            widthM: request.dimension.widthM,
            gridRows: request.grid.rows,
            gridColumns: request.grid.columns,
            captureMode: request.captureMode,
            boundary: request.boundary,
            sandRegion: request.sandRegion,
            grid: request.grid,
            processingVersion: request.processingVersion
        )
    }
}

extension HatcheryLayoutFinalizeDTO {
    init(layoutID: UUID, sourcePhoto: HatcherySourcePhoto?) {
        self.init(
            layoutID: layoutID,
            sourcePhotoMIMEType: sourcePhoto.map { _ in HatcherySourcePhoto.jpegMIMEType },
            sourcePhotoBytes: sourcePhoto.map { Int64($0.data.count) },
            sourcePhotoWidth: sourcePhoto?.width,
            sourcePhotoHeight: sourcePhoto?.height
        )
    }
}
