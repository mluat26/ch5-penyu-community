import Foundation

protocol IoTDataRepository: Sendable {
    func fetch(id: UUID) async throws -> IoTDataEntity
    func fetchAll(nestID: UUID) async throws -> [IoTDataEntity]
    func fetchReadings(
        nestIDs: [UUID],
        in interval: DateInterval?
    ) async throws -> [IoTDataEntity]

    /// Average, highest and lowest temperature for one nest over `[from, to)`.
    ///
    /// Half-open on purpose, matching the SQL: `between` would count a reading
    /// landing exactly on midnight in both the day that ends and the one that
    /// begins.
    ///
    /// Returns nil when the nest is not visible to the caller -- the RPC is
    /// `security invoker`, so another organization's nest yields no rows at
    /// all. A non-nil value whose fields are all nil means the opposite: the
    /// nest is readable and the window is simply empty.
    func temperatureStats(
        nestID: UUID,
        from: Date,
        to: Date
    ) async throws -> NestTemperatureStats?
}
