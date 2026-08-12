import Foundation

struct Nest: Identifiable, Hashable, Sendable {
    let id: UUID
    var hatcheryID: UUID
    var founderID: UUID?
    var numberOfEggs: Int
    var dateEggsLaid: Date?
    var datePredictedHatch: Date?
    var placeEggsLaid: String?
    var successEggsHatch: Int?
    var failEggsHatch: Int?
    var placementRow: Int?
    var placementColumn: Int?

    var isHatched: Bool {
        successEggsHatch != nil || failEggsHatch != nil
    }

    var hatchRate: Double? {
        guard let successEggsHatch, numberOfEggs > 0 else { return nil }
        return Double(successEggsHatch) / Double(numberOfEggs)
    }

    var daysUntilHatch: Int? {
        guard let datePredictedHatch else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: datePredictedHatch).day
    }

    var sectionKey: String? {
        guard let placementRow, let placementColumn else { return nil }
        return "\(placementRow)-\(placementColumn)"
    }
}

struct CreateNestInput: Hashable, Sendable {
    var hatcheryID: UUID
    var founderID: UUID?
    var numberOfEggs: Int
    var dateEggsLaid: Date?
    var datePredictedHatch: Date?
    var placeEggsLaid: String?
    var placementRow: Int?
    var placementColumn: Int?
}

struct RecordHatchResultInput: Hashable, Sendable {
    var successEggsHatch: Int
    var failEggsHatch: Int
}

protocol NestRepository: Sendable {
    func fetchAll(hatcheryID: UUID) async throws -> [Nest]
    func create(_ input: CreateNestInput) async throws -> Nest
    func recordHatchResult(
        nestID: UUID,
        input: RecordHatchResultInput
    ) async throws -> Nest
}
