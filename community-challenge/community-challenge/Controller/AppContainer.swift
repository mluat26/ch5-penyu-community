import Foundation

/// The one composition root for dependencies.
///
/// `hatchery` and `nest` are backed by Supabase; telemetry is still in memory
/// because `public.iotdata` has no read policy and no ingestion path yet, so
/// nests carry no temperature until a sensor writes one.
@MainActor
final class AppContainer {
    private let hatcheryRepository: SupabaseHatcheryRepository
    private let nestRepository: SupabaseNestRepository
    private let telemetryRepository = InMemoryTelemetryRepository()
    private let inspectionRepository: SupabaseInspectionRepository
    private let deviceRepository: SupabaseDeviceRepository
    private let layoutService: HatcheryLayoutService

    init() {
        let client = SupabaseConfig.client
        let identity = SupabaseAuthenticationService(client: client)

        let hatcheryRepository = SupabaseHatcheryRepository(
            client: client,
            identity: identity
        )
        let nestRepository = SupabaseNestRepository(
            client: client,
            identity: identity
        )
        let layoutRepository = SupabaseHatcheryLayoutRepository(
            client: client,
            identity: identity
        )
        let photoStore = SupabaseHatcheryPhotoStore(
            client: client,
            identity: identity
        )
        self.hatcheryRepository = hatcheryRepository
        self.nestRepository = nestRepository
        self.inspectionRepository = SupabaseInspectionRepository(client: client)
        self.deviceRepository = SupabaseDeviceRepository(client: client)
        self.layoutService = HatcheryLayoutService(
            repository: layoutRepository,
            photoStore: photoStore
        )
    }

    private lazy var hatcheryService = HatcheryService(
        hatcheryRepository: hatcheryRepository,
        nestRepository: nestRepository,
        telemetryRepository: telemetryRepository
    )

    private lazy var nestService = NestService(repository: nestRepository)

    private lazy var inspectionService = InspectionService(repository: inspectionRepository)

    private lazy var deviceService = DeviceService(repository: deviceRepository)

    /// `DemoHatcheryDataSeeder` seeded the 312-nest prototype dashboard into the
    /// in-memory repositories. It cannot seed Supabase-backed ones, so a
    /// hatchery now starts genuinely empty and fills up as nests are added.
    private let demoDataSeeder: (any HatcheryDemoDataSeeding)? = nil

    func makeHatcherySetupController(
        editingHatchery: HatcheryEntity? = nil
    ) -> HatcherySetupController {
        HatcherySetupController(
            hatcheryService: hatcheryService,
            layoutService: layoutService,
            existingHatchery: editingHatchery
        )
    }

    func makeHatcheryController(
        sessionState: HatcherySessionState
    ) -> HatcheryController {
        HatcheryController(
            sessionState: sessionState,
            hatcheryService: hatcheryService,
            demoDataSeeder: demoDataSeeder
        )
    }

    func makeNestController(hatcheryID: UUID) -> NestController {
        NestController(hatcheryID: hatcheryID, nestService: nestService)
    }

    func makeHatcheryListController() -> HatcheryListController {
        HatcheryListController(
            hatcheryService: hatcheryService,
            layoutService: layoutService
        )
    }

    // No UI consumes these yet; they are the composition points for the
    // inspection and device screens when those are built.
    func makeInspectionService() -> InspectionService { inspectionService }

    func makeDeviceService() -> DeviceService { deviceService }
}
