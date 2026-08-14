import Foundation

/// The one composition root for dependencies.
///
/// Every repository is Supabase-backed. Readings will still be absent until a
/// sensor actually writes to `public.iotdata`, but that is now an empty table
/// rather than an in-memory stand-in. `hatchery` and `nest` additionally
/// require a per-device identity, since ownership is enforced at the database.
@MainActor
final class AppContainer {
    private let hatcheryRepository: SupabaseHatcheryRepository
    private let nestRepository: SupabaseNestRepository
    private let ioTDataRepository: SupabaseIoTDataRepository
    private let inspectionRepository: SupabaseInspectionRepository
    private let deviceRepository: SupabaseDeviceRepository
    private let hatchingRepository: SupabaseHatchingRepository
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
        self.ioTDataRepository = SupabaseIoTDataRepository(client: client)
        self.inspectionRepository = SupabaseInspectionRepository(client: client)
        self.deviceRepository = SupabaseDeviceRepository(client: client)
        self.hatchingRepository = SupabaseHatchingRepository(client: client)
        self.layoutService = HatcheryLayoutService(
            repository: layoutRepository,
            photoStore: photoStore
        )
    }

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
            hatcheryService: hatcheryService
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

    func makeHatchingService() -> HatchingService { hatchingService }
}
