import Foundation
import Observation

/// In-progress state for the Hatchling details screens.
///
/// The counts are `String` for the same reason `NestFormDraft`'s are: they are
/// mid-edit, and a half-typed number has no `Int` to be. `hatchedOn` is a real
/// `Date` because it is only ever set by a graphical picker, never typed, so
/// there is no unparseable intermediate state to preserve.
struct HatchingFormDraft: Hashable {
    var hatchedOn: Date
    var rottenEggs: String
    var unhatchedEggs: String
    /// Empty means "use the suggestion". Not pre-filled with the computed
    /// number, because a field that already holds a value cannot be told apart
    /// from one a person looked at and confirmed.
    var hatchedEggs: String

    static var sample: HatchingFormDraft {
        HatchingFormDraft(
            hatchedOn: Date(),
            rottenEggs: "0",
            unhatchedEggs: "0",
            hatchedEggs: ""
        )
    }
}

/// Backs the three screens that record a nest's final tally.
///
/// Holds the nest it is recording against, so every screen in the flow reads
/// its figures from one place: the review screen cannot arrive at a different
/// hatch rate from the form, and the success screen cannot disagree with
/// either.
@MainActor
@Observable
final class HatchingController {
    var draft = HatchingFormDraft.sample
    private(set) var isSaving = false
    /// Save-time failures only.
    ///
    /// Per-field problems are the computed flags below, which the screens read
    /// directly. `NestController` learned this the hard way: a validation
    /// message written in here was never cleared once the field was fixed, so
    /// it went on complaining about a problem that no longer existed.
    private(set) var errorMessage: String?
    private(set) var saved: HatchingEntity?
    /// Average, high and low across the whole incubation. Nil until loaded, and
    /// legitimately nil afterwards for a nest whose logger never reported.
    private(set) var temperatureStats: NestTemperatureStats?

    let nest: NestEntity

    private let hatchingService: HatchingService
    private let ioTDataRepository: any IoTDataRepository

    init(
        nest: NestEntity,
        hatchingService: HatchingService,
        ioTDataRepository: any IoTDataRepository
    ) {
        self.nest = nest
        self.hatchingService = hatchingService
        self.ioTDataRepository = ioTDataRepository
        self.draft.hatchedOn = Date()
    }

    // MARK: - Parsed values

    var rottenEggs: Int { Int(draft.rottenEggs) ?? 0 }
    var unhatchedEggs: Int { Int(draft.unhatchedEggs) ?? 0 }

    /// What the Hatched eggs field shows before anyone edits it, so the
    /// inspector confirms a number instead of doing arithmetic on a beach.
    var suggestedHatchedCount: Int {
        hatchingService.suggestedHatchedCount(
            clutchSize: nest.numberOfEggs,
            eggsRotten: rottenEggs,
            eggsUnhatched: unhatchedEggs
        )
    }

    var hatchedEggs: Int {
        draft.hatchedEggs.isEmpty ? suggestedHatchedCount : (Int(draft.hatchedEggs) ?? 0)
    }

    var totalAccountedFor: Int { hatchedEggs + rottenEggs + unhatchedEggs }

    // MARK: - Per-field validation

    var isRottenInvalid: Bool { !isCountValid(draft.rottenEggs) }
    var isUnhatchedInvalid: Bool { !isCountValid(draft.unhatchedEggs) }
    /// Empty is fine here and nowhere else: it means the suggestion stands.
    var isHatchedInvalid: Bool { draft.hatchedEggs.isEmpty ? false : !isCountValid(draft.hatchedEggs) }

    /// Mirrors the `hatching_within_clutch` trigger, so a transposed digit is
    /// caught on the device rather than coming back as a Postgres exception.
    var exceedsClutch: Bool { totalAccountedFor > nest.numberOfEggs }

    var canSubmit: Bool {
        !isSaving && !isRottenInvalid && !isUnhatchedInvalid && !isHatchedInvalid && !exceedsClutch
    }

    private func isCountValid(_ text: String) -> Bool {
        guard let value = Int(text) else { return false }
        return value >= 0
    }

    // MARK: - Shared display values

    /// Collection to hatch, counted between calendar days. This is the figure
    /// the review screen shows, and the same span `loadTemperatureStats` reads
    /// its average over.
    var incubationDays: Int? {
        guard let laid = nest.dateEggsLaid else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: laid),
            to: calendar.startOfDay(for: draft.hatchedOn)
        ).day.map { max($0, 0) }
    }

    /// Share of the whole clutch that hatched -- not of the eggs accounted for.
    /// Eggs go missing on a beach, and dividing by the smaller number would
    /// flatter every nest that lost some.
    var hatchRatePercent: Double {
        guard nest.numberOfEggs > 0 else { return 0 }
        return Double(hatchedEggs) / Double(nest.numberOfEggs) * 100
    }

    var hatchedOnOrdinalText: String { AppDateFormatting.ordinalDate(draft.hatchedOn) }

    // MARK: - Saving

    func save() async -> HatchingEntity? {
        guard !isSaving else { return nil }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let result = try await hatchingService.recordHatching(
                RecordHatchingInput(
                    nestID: nest.id,
                    hatchedOn: draft.hatchedOn,
                    eggsHatched: hatchedEggs,
                    eggsRotten: rottenEggs,
                    eggsUnhatched: unhatchedEggs
                )
            )
            saved = result
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// The average temperature the success screen shows, over the same window
    /// `incubationDays` measures: collection to the day of the hatch.
    ///
    /// Deliberately forgiving. Most nests have no logger, and a nest that has
    /// just been recorded must not be held back by a missing statistic.
    func loadTemperatureStats(hatchedOn: Date) async {
        let calendar = Calendar.current
        let from = nest.dateEggsLaid ?? nest.createdAt ?? hatchedOn
        // Half-open upstream, so the hatch day itself has to be included by
        // reaching to the start of the next one.
        let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: hatchedOn))
            ?? hatchedOn

        temperatureStats = try? await ioTDataRepository.temperatureStats(
            nestID: nest.id,
            from: calendar.startOfDay(for: from),
            to: to
        )
    }
}
