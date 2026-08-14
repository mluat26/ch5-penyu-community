import Foundation
import Observation

@MainActor
@Observable
final class NestController {
    var draft = NestFormDraft.sample
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var lastSavedNest: NestEntity?

    private let hatcheryID: UUID
    private let nestService: NestService

    init(hatcheryID: UUID, nestService: NestService) {
        self.hatcheryID = hatcheryID
        self.nestService = nestService
    }

    func save() async -> NestEntity? {
        guard let eggCount = Int(draft.numberOfEggs), eggCount > 0 else {
            errorMessage = "Enter a valid number of eggs."
            return nil
        }

        guard let sectionRow = draft.sectionRow, let sectionColumn = draft.sectionColumn else {
            errorMessage = "Select a section on the map."
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
                    placementRow: sectionRow,
                    placementColumn: sectionColumn,
                    // Queues the nest for its first visit. The wizard already
                    // asks for this date; without persisting it the nest is
                    // never due for inspection and nobody is prompted to look.
                    nextInspectionDate: AppDateFormatting.parseNestDraftDate(
                        draft.inspectionDate
                    )
                )
            )
            lastSavedNest = nest
            return nest
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func reset() {
        draft = .sample
        errorMessage = nil
        lastSavedNest = nil
    }

    func validateIdentity() -> Bool {
        guard !draft.bucketID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a QR or bucket ID."
            return false
        }

        guard !draft.nestNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a nest number."
            return false
        }

        guard draft.sectionRow != nil, draft.sectionColumn != nil else {
            errorMessage = "Select a section on the map."
            return false
        }

        errorMessage = nil
        return true
    }

    func updateEstimatedHatchDate() {
        guard
            let collectionDate = AppDateFormatting.parseNestDraftDate(draft.collectionDate),
            let days = Int(draft.daysAfterCollection),
            days >= 0,
            let estimatedDate = Calendar.current.date(
                byAdding: .day,
                value: days,
                to: collectionDate
            )
        else {
            return
        }

        draft.hatchDate = AppDateFormatting.nestDraftDateString(estimatedDate)
    }
}
