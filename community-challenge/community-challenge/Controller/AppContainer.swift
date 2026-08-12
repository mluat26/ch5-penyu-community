import Foundation

/// The one composition root for dependencies. Supabase repositories will later
/// replace the in-memory implementations here without changing UI code.
@MainActor
final class AppContainer {
    private let hatcheryRepository = InMemoryHatcheryRepository()
    private let nestRepository = InMemoryNestRepository()
    private let telemetryRepository = InMemoryTelemetryRepository()

    private lazy var hatcheryService = HatcheryService(
        hatcheryRepository: hatcheryRepository,
        nestRepository: nestRepository,
        telemetryRepository: telemetryRepository
    )

    private lazy var nestService = NestService(repository: nestRepository)

    private lazy var demoDataSeeder: any HatcheryDemoDataSeeding =
        DemoHatcheryDataSeeder(
            nestRepository: nestRepository,
            telemetryRepository: telemetryRepository
        )

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
}
