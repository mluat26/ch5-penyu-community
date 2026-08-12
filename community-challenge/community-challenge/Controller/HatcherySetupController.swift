import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class HatcherySetupController {
    var draft = HatcherySetupDraft()
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private let hatcheryService: HatcheryService

    init(hatcheryService: HatcheryService) {
        self.hatcheryService = hatcheryService
    }

    func setName(_ name: String) {
        draft.name = name
        errorMessage = nil
    }

    func skipScanning() {
        let image = UIImage(named: "HatcherySamplePhoto") ?? UIImage()
        draft.image = image
        draft.rectifiedImage = image
        draft.usesMockImage = true
        draft.boundary = .fullImage
        draft.sandRegion = .default(from: .fullImage)
        draft.grid = nil
        errorMessage = nil
    }

    func storeCapturedImage(_ image: UIImage, boundary: HatcheryBoundary) {
        draft.image = image
        draft.rectifiedImage = nil
        draft.usesMockImage = false
        draft.boundary = boundary
        draft.sandRegion = .default(from: boundary)
        draft.grid = nil
        errorMessage = nil
    }

    func confirmBoundary(
        image: UIImage,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion
    ) {
        draft.image = image
        draft.boundary = boundary
        draft.sandRegion = sandRegion
        draft.rectifiedImage = HatcheryImageProcessor.rectifiedImage(
            from: image,
            boundary: boundary
        )
        draft.grid = nil
        errorMessage = nil
    }

    func generateGrid(for dimension: HatcheryDimension) -> Bool {
        guard let boundary = draft.boundary,
              let grid = HatcheryGridGenerator.generate(
                dimension: dimension,
                boundary: boundary,
                sandRegion: draft.sandRegion
              )
        else {
            errorMessage = "Unable to create a grid for this hatchery."
            return false
        }

        draft.dimension = dimension
        draft.grid = grid
        errorMessage = nil
        return true
    }

    func discardCaptureState() {
        draft.image = nil
        draft.rectifiedImage = nil
        draft.usesMockImage = false
        draft.boundary = nil
        draft.sandRegion = nil
        draft.grid = nil
        errorMessage = nil
    }

    func completeSetup() async -> HatcherySessionState? {
        guard
            let photo = draft.image,
            let rectifiedPhoto = draft.rectifiedImage ?? draft.image,
            let boundary = draft.boundary,
            let sandRegion = draft.sandRegion,
            let grid = draft.grid
        else {
            errorMessage = "Finish the hatchery setup before saving."
            return nil
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let hatchery = try await hatcheryService.createHatchery(
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

            return HatcherySessionState(
                hatchery: hatchery,
                photo: photo,
                rectifiedPhoto: rectifiedPhoto,
                boundary: boundary,
                sandRegion: sandRegion,
                grid: grid
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
