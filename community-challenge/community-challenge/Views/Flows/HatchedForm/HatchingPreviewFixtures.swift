import Foundation

/// Shared scaffolding for the hatchling-flow previews.
///
/// Built on the real in-memory repositories rather than bespoke stubs, so a
/// preview exercises the same validation and clutch arithmetic the app does --
/// including the `hatching_within_clutch` mirror, which is the rule most worth
/// seeing while laying out these screens.
enum HatchingPreviewFixtures {
    static func nest(
        numberOfEggs: Int = 225,
        collectedDaysAgo: Int = 56
    ) -> NestEntity {
        let calendar = Calendar.current
        let collected = calendar.date(byAdding: .day, value: -collectedDaysAgo, to: .now)

        return NestEntity(
            id: UUID(),
            hatcheryID: UUID(),
            founderID: nil,
            numberOfEggs: numberOfEggs,
            dateEggsLaid: collected,
            datePredictedHatch: .now,
            bucketID: "2145",
            nestNumber: "055",
            latitude: -8.72752,
            longitude: 115.16701,
            locationAddress: "Jalan Kartika Plaza No. 5, Kabupaten Badung",
            successEggsHatch: nil,
            failEggsHatch: nil,
            eggsUnhatched: nil,
            placementRow: 0,
            placementColumn: 0,
            nextInspectionDate: nil,
            createdAt: collected
        )
    }

    @MainActor
    static func controller(for nest: NestEntity = HatchingPreviewFixtures.nest()) -> HatchingController {
        let nestRepository = InMemoryNestRepository(seed: [nest])
        let controller = HatchingController(
            nest: nest,
            hatchingService: HatchingService(
                repository: InMemoryHatchingRepository(nestRepository: nestRepository),
                nestRepository: nestRepository
            ),
            ioTDataRepository: InMemoryIoTDataRepository()
        )
        controller.draft.rottenEggs = "90"
        controller.draft.unhatchedEggs = "12"
        return controller
    }
}
