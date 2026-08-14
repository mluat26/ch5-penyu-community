import Foundation

/// The one composition root for dependencies.
///
/// Every repository is Supabase-backed. Readings will still be absent until a
/// sensor actually writes to `public.iotdata`, but that is now an empty table
/// rather than an in-memory stand-in.
@MainActor
final class AppContainer {
    private let hatcheryRepository = SupabaseHatcheryRepository(client: SupabaseConfig.client)
    private let nestRepository = SupabaseNestRepository(client: SupabaseConfig.client)
    private let ioTDataRepository = SupabaseIoTDataRepository(client: SupabaseConfig.client)
    private let inspectionRepository = SupabaseInspectionRepository(client: SupabaseConfig.client)
    private let deviceRepository = SupabaseDeviceRepository(client: SupabaseConfig.client)
    private let hatchingRepository = SupabaseHatchingRepository(client: SupabaseConfig.client)

    private lazy var hatcheryService = HatcheryService(
        hatcheryRepository: hatcheryRepository,
        nestRepository: nestRepository,
        ioTDataRepository: ioTDataRepository
    )

    private lazy var nestService = NestService(repository: nestRepository)

    private lazy var inspectionService = InspectionService(repository: inspectionRepository)

    private lazy var deviceService = DeviceService(repository: deviceRepository)

    private lazy var hatchingService = HatchingService(
        repository: hatchingRepository,
        nestRepository: nestRepository
    )

    /// Establishes the session every write depends on. The composition root
    /// owns this so no view has to reach for the Supabase SDK directly.
    func prepareSession() async throws {
        try await SupabaseConfig.ensureSignedIn()
    }

    func makeHatcherySetupController() -> HatcherySetupController {
        HatcherySetupController(hatcheryService: hatcheryService)
    }

    func makeHatcheryController(
        sessionState: HatcherySessionState
    ) -> HatcheryController {
        HatcheryController(
            sessionState: sessionState,
            hatcheryService: hatcheryService
        )
    }

    func makeNestController(hatcheryID: UUID) -> NestController {
        NestController(hatcheryID: hatcheryID, nestService: nestService)
    }

    func makeHatcheryListController() -> HatcheryListController {
        HatcheryListController(hatcheryService: hatcheryService)
    }

    // No UI consumes these yet; they are the composition points for the
    // inspection and device screens when those are built.
    func makeInspectionService() -> InspectionService { inspectionService }

    func makeDeviceService() -> DeviceService { deviceService }

    func makeHatchingService() -> HatchingService { hatchingService }
}
