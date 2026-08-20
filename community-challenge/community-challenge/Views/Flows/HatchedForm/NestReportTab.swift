/// Read-only "Nest Report" screen — Info / Timeline / Temperature, reached
/// from a nest's dashboard entry. Distinct from `NestDetailSheet` (which is
/// the edit/inspect sheet), but shares its controller and several building
/// blocks so the two stay in sync on the underlying data.
///
/// NOTE: `NestTemperatureChart` and the axis/threshold helpers it uses live
/// in NestDetailSheet.swift marked `private`. Drop the `private` there to
/// reuse it here — duplicating the gradient/threshold logic would drift.

import SwiftUI

private enum NestReportTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case timeline = "Timeline"
    case temperature = "Temperature"
    var id: String { rawValue }
}

struct NestReportView: View {
    let nest: NestEntity
    let ordinal: Int
    let sectionLabel: String
    @Bindable var controller: NestDetailController

    // Info tab
    let hatcheryName: String

    let onViewTemperatureOverTime: () -> Void
    let onDownloadFullReport: () -> Void
    let onBackToHatchery: () -> Void

    @State private var selectedTab: NestReportTab = .info
    @State private var selectedChartDay = Calendar.current.startOfDay(for: .now)

    // The sheet is always up (never dismissed by the user -- it's the page's
    // own layout, not an optional overlay), so this only ever flips true.
    @State private var isShowingReportSheet = true
    // Two stops: half the screen and full. Bound rather than fixed so both
    // the drag-to-expand gesture and the haptic below can see which one is
    // active.
    @State private var sheetDetent: PresentationDetent = .fraction(0.6)

    // NestEntity already carries these -- no separate params needed.
    private var hatchedCount: Int? { nest.successEggsHatch }
    private var unhatchedCount: Int? { nest.eggsUnhatched }
    private var rottenCount: Int? { nest.failEggsHatch }
    private var successRatePercent: Double? { nest.hatchRate.map { $0 * 100 } }

    var body: some View {
        ZStack(alignment: .top) {
            AddNestFlowBackground()

            VStack(alignment: .leading, spacing: 16) {
                Text("Nest #\(nest.displayNumber(fallbackOrdinal: ordinal))")
                    .font(.largeTitle).bold()
                    .foregroundStyle(Color.appGreenPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                // Row 1 -- identical shape to the Preview screen's detail
                // row, so it's the same component, not a lookalike.
                AddNestPreviewDetailRow(items: [
                    .init(
                        systemImage: "tray",
                        label: "Eggs total",
                        value: "\(nest.numberOfEggs)"
                    ),
                    .init(
                        systemImage: "calendar",
                        label: "Incubation period",
                        value: incubationPeriodText
                    ),
                    .init(
                        systemImage: "viewfinder",
                        label: "Hatch date",
                        value: nest.datePredictedHatch.map(formattedLong) ?? "—"
                    ),
                ])

                NestReportOutcomeRow(
                    hatched: hatchedCount,
                    unhatched: unhatchedCount,
                    rotten: rottenCount,
                    successRatePercent: successRatePercent
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
        .task {
            await controller.load()
            await controller.loadDataLogger(founderID: nest.founderID)
        }
 
        
        
        .sheet(isPresented: $isShowingReportSheet) {
            reportSheetContent
                .presentationDetents([.fraction(0.6), .large], selection: $sheetDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.6)))
                .interactiveDismissDisabled()
                // Fires once per crossing between the two stops -- not on
                // every drag frame -- because it's keyed to `sheetDetent`
                // itself rather than a continuous drag value.
                .sensoryFeedback(.impact(weight: .medium), trigger: sheetDetent)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    // MARK: - Sheet content (segmented control + tab card + actions)

    private var reportSheetContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("", selection: $selectedTab) {
                        ForEach(NestReportTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)

                    reportCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 12) {
                AddNestPrimaryButton(title: "Download full report", action: onDownloadFullReport)
                AddNestPrimaryButton(
                    title: "Back to Hatchery",
                    action: onBackToHatchery,
                    isSecondary: true
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color.white)
    }

    // MARK: - Card body per tab

    @ViewBuilder
    private var reportCard: some View {
        VStack(spacing: 0) {
            switch selectedTab {
            case .info: infoTabContent
            case .timeline: timelineTabContent
            case .temperature: temperatureTabContent
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#E0E0E0").opacity(0.29), in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Info

    private var infoTabContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                labeledValue(title: "Hatchery Name", value: hatcheryName)
                labeledValue(title: "Section", value: sectionLabel)
                labeledValue(title: "Bucket ID", value: nest.bucketID ?? "—")
            }

            if let latitude = nest.latitude, let longitude = nest.longitude {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nest was found")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#8E8E93").opacity(0.8))

                    AddNestFoundLocationCard(
                        latitude: latitude,
                        longitude: longitude,
                        address: nest.locationAddress
                    )
                }
            }
        }
    }

    private func labeledValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93"))
            Text(value)
                .font(.headline)
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Timeline

    private var timelineTabContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            NestIncubationProgressRow(
                startDate: nest.dateEggsLaid,
                endDate: nest.datePredictedHatch,
                incubationPeriodText: incubationPeriodText
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Inspection list")
                    .font(.subheadline).bold()
                    .foregroundStyle(.black)

                if controller.inspections.isEmpty {
                    Text("No inspections recorded yet")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "#8E8E93"))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(controller.inspections.enumerated()), id: \.element.id) { index, inspection in
                            if index > 0 {
                                Divider()
                            }
                            HStack {
                                Text("#\(index + 1)")
                                    .font(.body)
                                    .foregroundStyle(.black)
                                Spacer()
                                Text(formattedOrdinal(inspection.inspectedOn))
                                    .font(.body)
                                    .foregroundStyle(Color(hex: "#8E8E93"))
                            }
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Temperature

    private var temperatureTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(formattedLong(selectedChartDay))
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "#8E8E93"))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(NestTemperature.text(controller.latestTemperatureC))
                            .font(.system(size: 34, weight: .bold))
                        Text("°C")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundStyle(Color(hex: "#D9538E"))
                }
                Spacer()
                Button(action: onViewTemperatureOverTime) {
                    HStack(spacing: 4) {
                        Text("View temperature over time")
                            .font(.footnote)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "#8E8E93"))
                }
                .buttonStyle(.plain)
            }

            // Requires `NestTemperatureChart` to be non-`private` in
            // NestDetailSheet.swift.
            NestTemperatureChart(
                readings: controller.readings(on: selectedChartDay),
                scale: 1
            )
            .frame(height: 173)

            HStack(spacing: 12) {
                temperatureStat(title: "Avg (daily)", value: averageTemperatureText, tint: .black)
                temperatureStat(title: "Highest", value: highestTemperatureText, tint: Color(hex: "#FF383C"))
                temperatureStat(title: "Lowest", value: lowestTemperatureText, tint: Color(hex: "#4DA3FF"))
            }
        }
    }

    private func temperatureStat(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93"))
            Text(value)
                .font(.headline)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var dailyReadings: [IoTDataEntity] {
        controller.readings(on: selectedChartDay)
    }

    private var averageTemperatureText: String {
        let values = dailyReadings.map(\.temperatureC)
        guard !values.isEmpty else { return "—°C" }
        return String(format: "%.0f°C", values.reduce(0, +) / Double(values.count))
    }

    private var highestTemperatureText: String {
        dailyReadings.map(\.temperatureC).max().map { String(format: "%.0f°C", $0) } ?? "—°C"
    }

    private var lowestTemperatureText: String {
        dailyReadings.map(\.temperatureC).min().map { String(format: "%.0f°C", $0) } ?? "—°C"
    }

    // MARK: - Shared formatting

    private var incubationPeriodText: String {
        guard let laid = nest.dateEggsLaid, let hatch = nest.datePredictedHatch else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: laid, to: hatch).day ?? 0
        return "\(max(days, 0)) days"
    }

    private func formattedLong(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    /// "20th June, 2026" -- matches `AppDateFormatting.longNestDraftDate`'s
    /// reading style for a `Date` rather than the draft's `String` form.
    private func formattedOrdinal(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let suffix: String
        switch (day % 10, day % 100) {
        case (1, let hundred) where hundred != 11: suffix = "st"
        case (2, let hundred) where hundred != 12: suffix = "nd"
        case (3, let hundred) where hundred != 13: suffix = "rd"
        default: suffix = "th"
        }
        let rest = date.formatted(.dateTime.month(.wide).year())
        return "\(day)\(suffix) \(rest)"
    }
}

/// New -- the 4-column colored outcome row (Hatched / Unhatched / Rotten /
/// Success rate). Flat, no card, matching the report's own spacing rather
/// than `AddNestPreviewDetailRow`'s icon-topped layout.
private struct NestReportOutcomeRow: View {
    let hatched: Int?
    let unhatched: Int?
    let rotten: Int?
    let successRatePercent: Double?

    var body: some View {
        HStack(spacing: 0) {
            stat(value: hatched.map(String.init) ?? "—", label: "Hatched", tint: .black)
            stat(value: unhatched.map(String.init) ?? "—", label: "Unhatched", tint: Color(hex: "#FF9500"))
            stat(value: rotten.map(String.init) ?? "—", label: "Rotten", tint: Color(hex: "#FF383C"))
            stat(
                value: successRatePercent.map { String(format: "%.1f%%", $0) } ?? "—",
                label: "Success rate",
                tint: Color.appGreenPrimary
            )
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "#E0E0E0").opacity(0.29))
        )
    }

    private func stat(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3).bold()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93"))
        }
        .frame(maxWidth: .infinity)
    }
}

    private func stat(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3).bold()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93"))
        }
        .frame(maxWidth: .infinity)
    }

/// New -- the dashed-line "collection ⟶ incubation ⟶ hatching" progress row
/// on the Timeline tab.
private struct NestIncubationProgressRow: View {
    let startDate: Date?
    let endDate: Date?
    let incubationPeriodText: String

    var body: some View {
        VStack(spacing: 8) {
            Text("Incubation period \(incubationPeriodText)")
                .font(.footnote)
                .foregroundStyle(Color(hex: "#8E8E93"))

            HStack {
                Circle()
                    .fill(Color.appGreenPrimary)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(Color(hex: "#8E8E93").opacity(0.3))
                    .frame(height: 1)
                Circle()
                    .stroke(Color.appGreenPrimary, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
            }

            HStack {
                labeledDate(title: "Egg collection", date: startDate)
                Spacer()
                labeledDate(title: "Hatching", date: endDate, alignment: .trailing)
            }
        }
    }

    private func labeledDate(title: String, date: Date?, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93"))
            Text(date.map { $0.formatted(.dateTime.day().month(.wide).year()) } ?? "—")
                .font(.subheadline).bold()
                .foregroundStyle(.black)
        }
    }
}

// MARK: - Preview
//
// `NestEntity`, `NestDetailController`, `InspectionService`, and
// `IoTDataRepository` are now the real ones. Still a guess:
//   - `InspectionRepository`'s exact protocol requirement (inferred from how
//     `InspectionService` calls it: `fetchAll(nestID:)`, `create(_:)`,
//     `update(id:_:)`)
//   - `InspectionEntity`'s fields (inferred from `RecordInspectionInput`'s
//     shape, since its definition wasn't shared)
// If either doesn't match, swap in the real types -- `NestReportView` itself
// doesn't depend on getting this preview fixture right.

private struct NestReportPreviewIoTDataRepository: IoTDataRepository {
    func fetch(id: UUID) async throws -> IoTDataEntity {
        throw NestReportPreviewError.notImplemented
    }

    func fetchAll(nestID: UUID) async throws -> [IoTDataEntity] {
        []
    }

    func fetchReadings(nestIDs: [UUID], in interval: DateInterval?) async throws -> [IoTDataEntity] {
        []
    }
}

private struct NestReportPreviewInspectionRepository: InspectionRepository {
    func fetchAll(nestID: UUID) async throws -> [InspectionEntity] {
        []
    }

    func create(_ input: RecordInspectionInput) async throws -> InspectionEntity {
        throw NestReportPreviewError.notImplemented
    }

    func update(id: UUID, _ input: CorrectInspectionInput) async throws -> InspectionEntity {
        throw NestReportPreviewError.notImplemented
    }
}

private enum NestReportPreviewError: Error {
    case notImplemented
}

@MainActor
private enum NestReportPreviewFixtures {
    static func nest() -> NestEntity {
        NestEntity(
            id: UUID(),
            hatcheryID: UUID(),
            founderID: UUID(),
            numberOfEggs: 124,
            dateEggsLaid: DateComponents(calendar: .current, year: 2026, month: 1, day: 1).date,
            datePredictedHatch: DateComponents(calendar: .current, year: 2026, month: 4, day: 1).date,
            bucketID: "2145",
            nestNumber: "051",
            latitude: -8.727_52,
            longitude: 115.167_01,
            locationAddress: "Jalan Kartika Plaza No. 5, Kabupaten Badung",
            successEggsHatch: 50,
            failEggsHatch: 90,
            eggsUnhatched: 12,
            nextInspectionDate: DateComponents(calendar: .current, year: 2026, month: 6, day: 20).date
        )
    }

    static func controller(for nest: NestEntity) -> NestDetailController {
        NestDetailController(
            nestID: nest.id,
            ioTDataRepository: NestReportPreviewIoTDataRepository(),
            inspectionService: InspectionService(repository: NestReportPreviewInspectionRepository())
        )
    }
}

#Preview("Nest report", traits: .fixedLayout(width: 402, height: 874)) {
    let nest = NestReportPreviewFixtures.nest()
    NestReportView(
        nest: nest,
        ordinal: 51,
        sectionLabel: "B1",
        controller: NestReportPreviewFixtures.controller(for: nest),
        hatcheryName: "Hatchery_01",
        onViewTemperatureOverTime: { },
        onDownloadFullReport: { },
        onBackToHatchery: { }
    )
}
