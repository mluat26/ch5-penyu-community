import Foundation

/// Backs the nest detail screen: the temperature history behind its chart and
/// the inspections behind its list. Both are per-nest queries the dashboard
/// does not already carry, so they load when the screen opens rather than
/// being fetched for every nest in a section up front.
@MainActor
@Observable
final class NestDetailController {
    private(set) var readings: [IoTDataEntity] = []
    private(set) var inspections: [InspectionEntity] = []
    /// The final tally, once one exists. Nil while the nest is still
    /// incubating, which is what the detail sheet reads to decide whether its
    /// action records a hatch or opens the report.
    private(set) var hatching: HatchingEntity?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Edited in place by the detail sheet's edit mode, committed by `save`.
    /// Seeded from the nest so cancelling simply discards these.
    var draftCollectionDate = Date()
    var draftPredictedHatch = Date()
    var draftInspectionDate = Date()
    var draftLocation = ""
    /// The pin behind `draftLocation`. Edited through the map picker, so the
    /// address and the coordinates cannot drift apart.
    var draftLatitude: Double?
    var draftLongitude: Double?
    private(set) var isSaving = false
    /// The founder's display name, shown as "Data logger". Nil until resolved,
    /// and stays nil if the nest has no founder or that person set no name.
    private(set) var dataLoggerName: String?

    private let nestID: UUID
    private let ioTDataRepository: any IoTDataRepository
    private let inspectionService: InspectionService
    private let nestService: NestService?
    private let profileRepository: (any ProfileRepository)?
    private let hatchingService: HatchingService?

    init(
        nestID: UUID,
        ioTDataRepository: any IoTDataRepository,
        inspectionService: InspectionService,
        nestService: NestService? = nil,
        profileRepository: (any ProfileRepository)? = nil,
        hatchingService: HatchingService? = nil
    ) {
        self.nestID = nestID
        self.ioTDataRepository = ioTDataRepository
        self.inspectionService = inspectionService
        self.nestService = nestService
        self.profileRepository = profileRepository
        self.hatchingService = hatchingService
    }

    /// Turns `founder_id` into a name. Readable only for people in the same
    /// organization, which is what the profile read policy allows.
    func loadDataLogger(founderID: UUID?) async {
        guard let founderID, let profileRepository else { return }
        dataLoggerName = try? await profileRepository.fetchProfile(id: founderID)?.displayName
    }

    /// Fills the draft from the nest being shown. Called when edit mode opens
    /// so the pickers start on the stored values rather than today.
    func beginEditing(_ nest: NestEntity) {
        draftCollectionDate = nest.dateEggsLaid ?? .now
        draftPredictedHatch = nest.datePredictedHatch ?? .now
        draftInspectionDate = nest.nextInspectionDate ?? .now
        draftLocation = nest.locationAddress ?? ""
        draftLatitude = nest.latitude
        draftLongitude = nest.longitude
        errorMessage = nil
    }

    /// Writes the edited fields back. Returns the saved nest so the sheet can
    /// show the new values without refetching.
    func save(_ nest: NestEntity) async -> NestEntity? {
        guard let nestService, !isSaving else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedLocation = draftLocation.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            return try await nestService.updateNest(
                id: nest.id,
                UpdateNestInput(
                    numberOfEggs: nest.numberOfEggs,
                    dateEggsLaid: draftCollectionDate,
                    datePredictedHatch: draftPredictedHatch,
                    bucketID: nest.bucketID,
                    nestNumber: nest.nestNumber,
                    latitude: draftLatitude,
                    longitude: draftLongitude,
                    locationAddress: trimmedLocation.isEmpty ? nil : trimmedLocation,
                    nextInspectionDate: draftInspectionDate,
                    placementRow: nest.placementRow,
                    placementColumn: nest.placementColumn
                )
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Readings for `day`, oldest first, which is the order the chart draws.
    func readings(on day: Date) -> [IoTDataEntity] {
        let calendar = Calendar.current
        return readings
            .filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    var latestTemperatureC: Double? {
        readings.max { $0.timestamp < $1.timestamp }?.temperatureC
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // A nest is read on a beach, so keep this to the window the chart
            // can actually show rather than every reading ever recorded.
            let window = DateInterval(
                start: Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now,
                end: .now
            )

            async let readings = ioTDataRepository.fetchReadings(nestIDs: [nestID], in: window)
            async let inspections = inspectionService.inspections(nestID: nestID)
            async let hatching = hatchingService?.hatching(nestID: nestID)

            self.readings = try await readings
            self.inspections = try await inspections.sorted { $0.inspectedOn < $1.inspectedOn }
            self.hatching = try await hatching ?? nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
