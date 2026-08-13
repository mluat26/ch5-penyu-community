import Foundation

/// The one composition root for dependencies.
///
/// `hatchery` and `nest` are backed by Supabase; telemetry is still in memory
/// because `public.iotdata` has no read policy and no ingestion path yet, so
/// nests carry no temperature until a sensor writes one.
@MainActor
final class AppContainer {
    private let hatcheryRepository = SupabaseHatcheryRepository(client: SupabaseConfig.client)
    private let nestRepository = SupabaseNestRepository(client: SupabaseConfig.client)
    private let telemetryRepository = InMemoryTelemetryRepository()

    private lazy var hatcheryService = HatcheryService(
        hatcheryRepository: hatcheryRepository,
        nestRepository: nestRepository,
        telemetryRepository: telemetryRepository
    )

    private lazy var nestService = NestService(repository: nestRepository)

    /// `DemoHatcheryDataSeeder` seeded the 312-nest prototype dashboard into the
    /// in-memory repositories. It cannot seed Supabase-backed ones, so a
    /// hatchery now starts genuinely empty and fills up as nests are added.
    private let demoDataSeeder: (any HatcheryDemoDataSeeding)? = nil

    func makeHatcherySetupController() -> HatcherySetupController {
        HatcherySetupController(hatcheryService: hatcheryService)
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
        HatcheryListController(hatcheryService: hatcheryService)
    }
}
