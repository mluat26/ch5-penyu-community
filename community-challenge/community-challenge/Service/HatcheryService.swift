import Foundation

struct CreateHatcheryInput: Hashable, Sendable {
    var name: String
    var shape: HatcheryShape
    var numberOfRows: Int
    var numberOfColumns: Int
    var lengthM: Double
    var widthM: Double
    var organizationID: UUID?
}

/// Edit payload for the columns currently present in `public.hatchery`.
///
/// `shape` is deliberately absent: the setup flow always creates rectangles and
/// nothing offers a choice, so there is no edit to make.
struct UpdateHatcheryInput: Hashable, Sendable {
    var name: String
    var numberOfRows: Int
    var numberOfColumns: Int
    var lengthM: Double
    var widthM: Double
}

struct HatcheryService: Sendable {
    private let hatcheryRepository: any HatcheryRepository
    private let nestRepository: any NestRepository
    private let ioTDataRepository: any IoTDataRepository

    init(
        hatcheryRepository: any HatcheryRepository,
        nestRepository: any NestRepository,
        ioTDataRepository: any IoTDataRepository
    ) {
        self.hatcheryRepository = hatcheryRepository
        self.nestRepository = nestRepository
        self.ioTDataRepository = ioTDataRepository
    }

    func createHatchery(_ input: CreateHatcheryInput) async throws -> HatcheryEntity {
        var sanitizedInput = input
        sanitizedInput.name = HatcheryName.trimmed(input.name)
        try await validateAvailableHatcheryName(sanitizedInput.name)
        guard
            sanitizedInput.numberOfRows > 0,
            sanitizedInput.numberOfColumns > 0,
            sanitizedInput.lengthM > 0,
            sanitizedInput.widthM > 0
        else {
            throw DomainValidationError.invalidDimensions
        }

        return try await hatcheryRepository.create(sanitizedInput)
    }

    /// Fast, owner-scoped feedback for the name-entry screen. The database
    /// still enforces this atomically when saving, because this list can become
    /// stale while another device is creating a hatchery.
    func validateAvailableHatcheryName(
        _ name: String,
        excludingHatcheryID: UUID? = nil
    ) async throws {
        let normalizedName = HatcheryName.normalized(name)
        guard !normalizedName.isEmpty else {
            throw DomainValidationError.emptyName
        }

        let existingHatcheries = try await hatcheryRepository.fetchAll()
        guard !existingHatcheries.contains(where: {
            $0.id != excludingHatcheryID
                && HatcheryName.normalized($0.name) == normalizedName
        }) else {
            throw DomainValidationError.duplicateHatcheryName
        }
    }

    func hatcheries() async throws -> [HatcheryEntity] {
        try await hatcheryRepository.fetchAll()
    }

    func hatchery(id: UUID) async throws -> HatcheryEntity {
        try await hatcheryRepository.fetch(id: id)
    }

    /// The management cards only need aggregate nest data, not another copy of
    /// their hatchery row. Keeping this separate avoids an N+1 read when the
    /// list already has those rows.
    func loadOverview(hatcheryID: UUID) async throws -> HatcheryOverview {
        let loadedNests = try await nestRepository.fetchAll(hatcheryID: hatcheryID)
        let readings = try await ioTDataRepository.fetchReadings(
            nestIDs: loadedNests.map(\.id),
            in: nil
        )
        let latestReadings = Dictionary(grouping: readings, by: \.nestID)
            .values
            .compactMap { $0.max { $0.timestamp < $1.timestamp } }

        return HatcheryOverview(
            averageTemperatureC: averageTemperature(in: latestReadings),
            nestCount: loadedNests.count,
            totalEggs: loadedNests.reduce(0) { $0 + $1.numberOfEggs }
        )
    }

    /// Renaming is always safe; resizing is not. Shrinking the grid can leave
    /// nests on coordinates that no longer exist, which makes them invisible in
    /// every section while still counting toward the dashboard totals, so that
    /// case is refused rather than silently accepted.
    func updateHatchery(
        id: UUID,
        _ input: UpdateHatcheryInput
    ) async throws -> HatcheryEntity {
        var sanitizedInput = input
        sanitizedInput.name = HatcheryName.trimmed(input.name)
        guard !sanitizedInput.name.isEmpty else {
            throw DomainValidationError.emptyName
        }
        guard
            sanitizedInput.numberOfRows > 0,
            sanitizedInput.numberOfColumns > 0,
            sanitizedInput.lengthM > 0,
            sanitizedInput.widthM > 0
        else {
            throw DomainValidationError.invalidDimensions
        }

        let strandedCount = try await nestRepository
            .fetchAll(hatcheryID: id)
            .filter { nest in
                guard let row = nest.placementRow, let column = nest.placementColumn else {
                    return false
                }
                return row >= sanitizedInput.numberOfRows || column >= sanitizedInput.numberOfColumns
            }
            .count

        guard strandedCount == 0 else {
            throw DomainValidationError.resizeWouldStrandNests(count: strandedCount)
        }

        return try await hatcheryRepository.update(id: id, sanitizedInput)
    }

    /// `nest_hatchery_id_fkey` would reject this anyway, but a raw foreign key
    /// violation is not something the UI can explain. Counting first turns it
    /// into a message naming how many nests are in the way.
    ///
    /// Separate from `deleteHatchery` because deleting a hatchery also destroys
    /// its layout photographs, and that has to happen before the row goes --
    /// so the refusal has to come before the photographs, not with the row.
    func assertHatcheryIsEmpty(id: UUID) async throws {
        let nestCount = try await nestRepository.fetchAll(hatcheryID: id).count
        guard nestCount == 0 else {
            throw DomainValidationError.hatcheryNotEmpty(nestCount: nestCount)
        }
    }

    func deleteHatchery(id: UUID) async throws {
        try await assertHatcheryIsEmpty(id: id)
        try await hatcheryRepository.delete(id: id)
    }

    func loadDashboard(hatcheryID: UUID) async throws -> HatcheryDashboard {
        async let hatchery = hatcheryRepository.fetch(id: hatcheryID)
        async let nests = nestRepository.fetchAll(hatcheryID: hatcheryID)

        let (loadedHatchery, loadedNests) = try await (hatchery, nests)
        let readings = try await ioTDataRepository.fetchReadings(
            nestIDs: loadedNests.map(\.id),
            in: nil
        )
        let latestReadingByNestID = Dictionary(
            uniqueKeysWithValues: Dictionary(
                grouping: readings,
                by: \.nestID
            ).compactMap { nestID, nestReadings in
                nestReadings.max { $0.timestamp < $1.timestamp }
                    .map { (nestID, $0) }
            }
        )

        let sections = makeSections(
            hatchery: loadedHatchery,
            nests: loadedNests,
            latestReadingByNestID: latestReadingByNestID
        )
        let latestReadings = Array(latestReadingByNestID.values)

        return HatcheryDashboard(
            hatchery: loadedHatchery,
            overview: HatcheryOverview(
                averageTemperatureC: averageTemperature(in: latestReadings),
                nestCount: loadedNests.count,
                totalEggs: loadedNests.reduce(0) { $0 + $1.numberOfEggs }
            ),
            sections: sections
        )
    }

    private func makeSections(
        hatchery: HatcheryEntity,
        nests: [NestEntity],
        latestReadingByNestID: [UUID: IoTDataEntity]
    ) -> [HatcherySectionDashboard] {
        (0..<max(hatchery.numberOfRows, 0)).flatMap { row in
            (0..<max(hatchery.numberOfColumns, 0)).map { column in
                let sectionNests = nests.filter {
                    $0.placementRow == row && $0.placementColumn == column
                }
                let items = sectionNests.map { nest in
                    NestDashboardItem(
                        nest: nest,
                        latestTemperatureC: latestReadingByNestID[nest.id]?.temperatureC,
                        latestBatteryVoltage: latestReadingByNestID[nest.id]?.batteryVoltage
                    )
                }

                return HatcherySectionDashboard(
                    id: HatcherySectionIdentifier.make(row: row, column: column),
                    row: row,
                    column: column,
                    averageTemperatureC: averageTemperature(
                        in: sectionNests.compactMap { latestReadingByNestID[$0.id] }
                    ),
                    nestCount: sectionNests.count,
                    totalEggs: sectionNests.reduce(0) { $0 + $1.numberOfEggs },
                    nextHatchDate: sectionNests.compactMap(\.datePredictedHatch).min(),
                    nests: items
                )
            }
        }
    }

    private func averageTemperature(in readings: [IoTDataEntity]) -> Double? {
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0) { $0 + $1.temperatureC } / Double(readings.count)
    }
}

enum HatcherySectionIdentifier {
    static func make(row: Int, column: Int) -> String {
        "\(columnLabel(column))\(row + 1)"
    }

    private static func columnLabel(_ zeroBasedIndex: Int) -> String {
        var value = zeroBasedIndex + 1
        var label = ""
        while value > 0 {
            value -= 1
            label = String(UnicodeScalar(65 + value % 26)!) + label
            value /= 26
        }
        return label
    }
}
