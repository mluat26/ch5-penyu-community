import Foundation
import Observation

@MainActor
@Observable
final class NestController {
    var draft = NestFormDraft.sample
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private let hatcheryID: UUID
    private let nestService: NestService

    init(hatcheryID: UUID, nestService: NestService) {
        self.hatcheryID = hatcheryID
        self.nestService = nestService
    }

    func save() async -> Nest? {
        guard let eggCount = Int(draft.numberOfEggs), eggCount > 0 else {
            errorMessage = "Enter a valid number of eggs."
            return nil
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let nest = try await nestService.createNest(
                CreateNestInput(
                    hatcheryID: hatcheryID,
                    founderID: nil,
                    numberOfEggs: eggCount,
                    dateEggsLaid: AppDateFormatting.parseNestDraftDate(draft.collectionDate),
                    datePredictedHatch: AppDateFormatting.parseNestDraftDate(draft.hatchDate),
                    placeEggsLaid: nil,
                    placementRow: nil,
                    placementColumn: nil
                )
            )
            return nest
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func reset() {
        draft = .sample
        errorMessage = nil
    }
}
