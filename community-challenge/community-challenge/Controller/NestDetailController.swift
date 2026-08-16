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
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let nestID: UUID
    private let ioTDataRepository: any IoTDataRepository
    private let inspectionService: InspectionService

    init(
        nestID: UUID,
        ioTDataRepository: any IoTDataRepository,
        inspectionService: InspectionService
    ) {
        self.nestID = nestID
        self.ioTDataRepository = ioTDataRepository
        self.inspectionService = inspectionService
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

            self.readings = try await readings
            self.inspections = try await inspections.sorted { $0.inspectedOn < $1.inspectedOn }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
