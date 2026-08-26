import Foundation
import Observation
import UIKit

/// Working state while the setup flow is being filled in. Everything is
/// optional because the user is part-way through; `completeSetup()` is the gate
/// that unwraps it into a `HatcherySessionState`, whose equivalents are
/// non-optional and so cannot be half-built.
struct HatcherySetupDraft {
    var name = ""
    var image: UIImage?
    var rectifiedImage: UIImage?
    var usesMockImage = false
    /// `true` when the user bypasses scanning. A white raster keeps the
    /// remainder of setup functional, while this state lets the UI reserve
    /// the photo area without showing a fake hatchery image.
    var isAwaitingScan = false
    var boundary: HatcheryBoundary?
    /// The editable usable-sand outline. It is separate from `boundary`,
    /// which remains the four-corner perspective plane for rectification.
    var sandRegion: HatcherySandRegion?
    /// The same sand outline after it has been mapped into the perspective-
    /// corrected photo shown by the later setup screens.
    var rectifiedSandRegion: HatcherySandRegion?
    var dimension = HatcheryDimension(widthM: 15, heightM: 7)
    var grid: HatcheryGrid?
}

@MainActor
@Observable
final class HatcherySetupController {
    var draft = HatcherySetupDraft()
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private let hatcheryService: HatcheryService
    private let layoutService: HatcheryLayoutService?
    /// When non-nil, this setup run re-scans an existing hatchery instead of
    /// creating another row.
    private let existingHatchery: HatcheryEntity?
    /// The scan confirmation pre-encodes this immutable upload payload, so the
    /// final save can begin its network work immediately.
    private var preparedSourcePhoto: HatcherySourcePhoto?

    init(
        hatcheryService: HatcheryService,
        layoutService: HatcheryLayoutService? = nil,
        existingHatchery: HatcheryEntity? = nil
    ) {
        self.hatcheryService = hatcheryService
        self.layoutService = layoutService
        self.existingHatchery = existingHatchery

        if let existingHatchery {
            draft.name = existingHatchery.name
            draft.dimension = HatcheryDimension(
                widthM: existingHatchery.widthM,
                heightM: existingHatchery.lengthM
            )
        }
    }

    func setName(_ name: String) {
        draft.name = HatcheryName.trimmed(name)
        errorMessage = nil
    }

    /// Checks the current owner's hatcheries before we leave the Figma name
    /// screen. The database repeats this check atomically at save time, so a
    /// stale list or second device cannot create a duplicate.
    func validateNewHatcheryName(_ name: String) async throws {
        guard existingHatchery == nil else { return }
        try await hatcheryService.validateAvailableHatcheryName(name)
    }

    func skipScanning() {
        resetPreparedSourcePhoto()
        let image = HatcheryImageProcessor.blankHatcheryImage()
        draft.image = image
        draft.rectifiedImage = image
        draft.usesMockImage = false
        draft.isAwaitingScan = true
        draft.boundary = .fullImage
        draft.sandRegion = .default(from: .fullImage)
        draft.rectifiedSandRegion = .default(from: .fullImage)
        draft.grid = nil
        errorMessage = nil
    }

    /// Stores a fresh capture with the whole frame as its starting outline.
    ///
    /// The camera's detected quad is deliberately not used as the seed. Since
    /// `confirmBoundary` reads the outline as the plane to straighten, seeding
    /// it from automatic detection meant pressing the tick without dragging
    /// accepted whatever the detector had locked onto -- a window frame, a
    /// floor seam -- and straightened that surface instead of the hatchery.
    ///
    /// Starting from the whole frame makes the two ways in behave identically:
    /// accepting without dragging applies no correction and keeps the photo as
    /// taken, and any correction is one somebody asked for by moving corners.
    func storeCapturedImage(_ image: UIImage) {
        resetPreparedSourcePhoto()
        draft.image = image
        draft.rectifiedImage = nil
        draft.usesMockImage = false
        draft.isAwaitingScan = false
        draft.boundary = .fullImage
        draft.sandRegion = .default(from: .fullImage)
        draft.rectifiedSandRegion = nil
        draft.grid = nil
        errorMessage = nil
    }

    /// The outline someone drew, read as the hatchery's plane.
    ///
    /// Nil unless it has exactly four corners. A plane needs four; a polygon
    /// with more describes an irregular sand shape that no single perspective
    /// correction can flatten, and one with fewer is not a shape at all.
    ///
    /// The order is the order `HatcherySandRegion(boundary:)` writes and
    /// `moveVertex` preserves -- top-left, top-right, bottom-right,
    /// bottom-left -- so dragging corners keeps the correspondence.
    private static func plane(from outline: HatcherySandRegion) -> HatcheryBoundary? {
        guard outline.points.count == 4 else { return nil }

        let candidate = HatcheryBoundary(
            topLeft: outline.points[0],
            topRight: outline.points[1],
            bottomRight: outline.points[2],
            bottomLeft: outline.points[3]
        )
        return candidate.isValid ? candidate : nil
    }

    func confirmBoundary(
        image: UIImage,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion
    ) async -> Bool {
        // Straighten what was outlined, not what a detector guessed.
        //
        // `boundary` arrives from automatic rectangle detection and is not
        // editable anywhere in the flow, while `inputCrop` makes the corrected
        // photo *be* that quad -- so a detector that locked onto a window frame
        // or a floor seam produced a photo of the wrong surface, with the drawn
        // outline squashed into a corner of it. Nothing in the UI could correct
        // that, because the only shape a person can move is the outline.
        //
        // So the outline is the plane. Falling back to the detected quad only
        // when the outline is not four corners, where no homography applies.
        let plane = Self.plane(from: sandRegion) ?? boundary

        do {
            let sourcePayload = try HatcheryImageProcessor.payload(from: image)
            resetPreparedSourcePhoto()
            let preparedCapture = try await HatcheryImageProcessor.prepareCapturedLayout(
                from: sourcePayload,
                boundary: plane,
                sandRegion: sandRegion
            )
            try Task.checkCancellation()

            draft.image = HatcheryImageProcessor.displayImage(from: preparedCapture.photo)
            draft.boundary = plane
            draft.sandRegion = sandRegion
            draft.rectifiedSandRegion = preparedCapture.rectifiedSandRegion
            draft.isAwaitingScan = false
            draft.rectifiedImage = HatcheryImageProcessor.displayImage(
                from: preparedCapture.rectifiedPhoto
            )
            preparedSourcePhoto = preparedCapture.sourcePhoto
            draft.grid = nil
            errorMessage = nil
            return true
        } catch is CancellationError {
            resetPreparedSourcePhoto()
            return false
        } catch {
            resetPreparedSourcePhoto()
            errorMessage = error.localizedDescription
            return false
        }
    }

    func generateGrid(for dimension: HatcheryDimension) -> Bool {
        guard let boundary = draft.boundary,
              let grid = HatcheryGridGenerator.generate(
                dimension: dimension,
                boundary: boundary,
                sandRegion: draft.sandRegion
              )
        else {
            errorMessage = String(localized: "Unable to create a grid for this hatchery.")
            return false
        }

        draft.dimension = dimension
        draft.grid = grid
        errorMessage = nil
        return true
    }

    func discardCaptureState() {
        resetPreparedSourcePhoto()
        draft.image = nil
        draft.rectifiedImage = nil
        draft.usesMockImage = false
        draft.isAwaitingScan = false
        draft.boundary = nil
        draft.sandRegion = nil
        draft.rectifiedSandRegion = nil
        draft.grid = nil
        errorMessage = nil
    }

    func completeSetup() async -> HatcherySessionState? {
        // SwiftUI disables the Done button once its task starts, but rapid
        // taps can enqueue more than one task before that state is rendered.
        // Reject them here at the persistence boundary as well.
        guard !isSaving else { return nil }

        guard
            let photo = draft.image,
            let boundary = draft.boundary,
            let sandRegion = draft.sandRegion,
            let grid = draft.grid
        else {
            errorMessage = String(localized: "Finish the hatchery setup before saving.")
            return nil
        }

        // Was `draft.rectifiedImage ?? draft.image`, which saved the raw camera
        // photo under the name `rectifiedPhoto` whenever perspective correction
        // had not produced one -- and nothing downstream could tell. The
        // dashboard drew an un-flattened photo and laid a uniform cell grid
        // over it, so the sections did not match the sand, with no error shown
        // at any point.
        //
        // Unreachable on every normal path: `skipScanning` sets this to the
        // blank image, and `confirmBoundary` both sets it and refuses to
        // advance without it. So this fires only when correction genuinely
        // failed, which is worth saying out loud rather than papering over.
        guard let rectifiedPhoto = draft.rectifiedImage else {
            errorMessage = String(localized: "This scan could not be flattened. Rescan the hatchery before saving.")
            return nil
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let hatchery: HatcheryEntity
            if let existingHatchery {
                if let layoutService {
                    let savedLayout = try await layoutService.save(
                        try await makeLayoutSaveRequest(
                            hatcheryID: existingHatchery.id,
                            photo: photo,
                            boundary: boundary,
                            sandRegion: sandRegion,
                            grid: grid
                        )
                    )
                    hatchery = try makeHatcheryEntity(
                        from: savedLayout,
                        expectedHatcheryID: existingHatchery.id,
                        shape: existingHatchery.shape,
                        organizationID: existingHatchery.organizationID,
                        createdAt: existingHatchery.createdAt
                    )
                } else {
                    hatchery = try await hatcheryService.updateHatchery(
                        id: existingHatchery.id,
                        UpdateHatcheryInput(
                            name: draft.name,
                            numberOfRows: grid.rows,
                            numberOfColumns: grid.columns,
                            lengthM: draft.dimension.heightM,
                            widthM: draft.dimension.widthM
                        )
                    )
                }
            } else {
                if let layoutService {
                    let hatcheryID = UUID()
                    let savedLayout = try await layoutService.createNewHatchery(
                        try await makeLayoutSaveRequest(
                            hatcheryID: hatcheryID,
                            photo: photo,
                            boundary: boundary,
                            sandRegion: sandRegion,
                            grid: grid
                        )
                    )
                    hatchery = try makeHatcheryEntity(
                        from: savedLayout,
                        expectedHatcheryID: hatcheryID,
                        shape: .rectangle,
                        organizationID: nil,
                        createdAt: savedLayout.createdAt
                    )
                } else {
                    hatchery = try await hatcheryService.createHatchery(
                        CreateHatcheryInput(
                            name: draft.name,
                            shape: .rectangle,
                            numberOfRows: grid.rows,
                            numberOfColumns: grid.columns,
                            lengthM: draft.dimension.heightM,
                            widthM: draft.dimension.widthM,
                            organizationID: nil
                        )
                    )
                }
            }

            return HatcherySessionState(
                hatchery: hatchery,
                photo: photo,
                rectifiedPhoto: rectifiedPhoto,
                usesMockImage: draft.usesMockImage,
                boundary: boundary,
                sandRegion: sandRegion,
                rectifiedSandRegion: draft.rectifiedSandRegion,
                grid: grid
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func makeLayoutSaveRequest(
        hatcheryID: UUID,
        photo: UIImage,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion,
        grid: HatcheryGrid
    ) async throws -> HatcheryLayoutSaveRequest {
        let sourcePhoto: HatcherySourcePhoto?
        if draft.isAwaitingScan {
            sourcePhoto = nil
        } else if let preparedSourcePhoto {
            sourcePhoto = preparedSourcePhoto
        } else {
            let sourcePayload = try HatcheryImageProcessor.payload(from: photo)
            sourcePhoto = try await HatcheryImageProcessor.sourcePhoto(from: sourcePayload)
        }

        return HatcheryLayoutSaveRequest(
            hatcheryID: hatcheryID,
            name: draft.name,
            dimension: draft.dimension,
            boundary: boundary,
            sandRegion: sandRegion,
            grid: HatcheryGridSnapshot(grid: grid),
            processingVersion: "ios-grid-v1",
            sourcePhoto: sourcePhoto
        )
    }

    /// The finalize RPC has already atomically committed these dynamic fields.
    /// Reusing its canonical response removes a redundant follow-up GET from
    /// both first-hatch creation and rescans.
    private func makeHatcheryEntity(
        from layout: HatcheryLayoutRevision,
        expectedHatcheryID: UUID,
        shape: HatcheryShape,
        organizationID: UUID?,
        createdAt: Date?
    ) throws -> HatcheryEntity {
        guard
            layout.hatcheryID == expectedHatcheryID,
            layout.state == .ready,
            layout.isCurrent
        else {
            throw HatcheryLayoutPersistenceError.unexpectedLayoutState
        }

        return HatcheryEntity(
            id: layout.hatcheryID,
            name: layout.name,
            shape: shape,
            numberOfRows: layout.grid.rows,
            numberOfColumns: layout.grid.columns,
            lengthM: layout.dimension.heightM,
            widthM: layout.dimension.widthM,
            organizationID: organizationID,
            createdAt: createdAt
        )
    }

    private func resetPreparedSourcePhoto() {
        preparedSourcePhoto = nil
    }
}
