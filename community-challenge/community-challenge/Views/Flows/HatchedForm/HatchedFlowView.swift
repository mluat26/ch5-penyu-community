import SwiftUI

/// The hatchling flow: details, review, confirmation, report.
///
/// No `NavigationStack` and no router. `NestRouter`'s own comments say modal
/// destinations get no route, and these are replacements rather than a back
/// stack -- the single backward edge is "Edit details", which returns to the
/// first step. A `Step` enum is the whole navigation model.
///
/// It is presented over the nest detail sheet, which is why every exit is a
/// closure: the sheet owns the cover and has to be the one to take it down.
struct HatchedFlowView: View {
    enum Step: Hashable {
        case details
        case review
        case recorded
        /// Reachable two ways: straight from a nest that already hatched, and
        /// from "View full report" after recording one.
        case report
    }

    /// Plain references, not `@Bindable`: this view never writes through a
    /// binding, it only reads and hands both down. The screens that do bind --
    /// the two form steps -- declare `@Bindable` themselves. `@Observable`
    /// tracks reads without it.
    let controller: HatchingController
    let detailController: NestDetailController
    let ordinal: Int
    let sectionLabel: String
    let hatcheryName: String
    /// Closes the flow, leaving the nest detail sheet up.
    let onClose: () -> Void
    /// A tally was written, so anything showing this nest is now out of date --
    /// the section list filters on it, and the dashboard counts it.
    let onSaved: () async -> Void
    /// Closes the flow *and* the sheet beneath it, landing on the hatchery.
    let onFinish: () -> Void

    @State private var step: Step

    init(
        controller: HatchingController,
        detailController: NestDetailController,
        ordinal: Int,
        sectionLabel: String,
        hatcheryName: String,
        startAt: Step,
        onClose: @escaping () -> Void,
        onSaved: @escaping () async -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.controller = controller
        self.detailController = detailController
        self.ordinal = ordinal
        self.sectionLabel = sectionLabel
        self.hatcheryName = hatcheryName
        self.onClose = onClose
        self.onSaved = onSaved
        self.onFinish = onFinish
        _step = State(initialValue: startAt)
    }

    var body: some View {
        switch step {
        case .details:
            HatchedForm1(
                controller: controller,
                onNext: { step = .review },
                onCancel: onClose
            )

        case .review:
            ReviewHatchlingsDetailsView(
                controller: controller,
                ordinal: ordinal,
                onSave: { Task { await save() } },
                onEdit: { step = .details },
                onCancel: onClose
            )

        case .recorded:
            HatchRecordedView(
                nestNumber: controller.nest.displayNumber(fallbackOrdinal: ordinal),
                successfulHatchCount: "\(controller.hatchedEggs)",
                hatchingDate: AppDateFormatting.longNestDraftDate(
                    AppDateFormatting.nestDraftDateString(controller.draft.hatchedOn)
                ),
                incubationDays: controller.incubationDays.map(String.init) ?? "—",
                averageTemperatureC: controller.temperatureStats?.avgC,
                initialEggCount: "\(controller.nest.numberOfEggs)",
                onViewFullReport: { step = .report },
                onBackToHatchery: onFinish
            )

        case .report:
            NestReportView(
                nest: controller.nest,
                ordinal: ordinal,
                sectionLabel: sectionLabel,
                controller: detailController,
                hatcheryName: hatcheryName,
                onBackToHatchery: onFinish
            )
        }
    }

    /// Saving is the only step that can fail, and the failure has to stay on
    /// the review screen: `controller.errorMessage` renders there, so a refused
    /// tally leaves the numbers on screen to be corrected rather than dropping
    /// the person somewhere they cannot fix it.
    private func save() async {
        guard let saved = await controller.save() else { return }

        await controller.loadTemperatureStats(hatchedOn: saved.hatchedOn)
        // Refreshes the sheet underneath, so its action has already become
        // "View report" by the time the flow is dismissed.
        await detailController.load()
        // And the screens behind that, which hold their own copies of the nest.
        await onSaved()

        step = .recorded
    }
}
