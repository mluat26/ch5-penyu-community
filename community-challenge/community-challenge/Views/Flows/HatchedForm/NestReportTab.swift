/// Read-only "Nest Report" screen — Info / Timeline / Temperature, reached
/// from a nest's dashboard entry. Distinct from `NestDetailSheet` (which is
/// the edit/inspect sheet), but shares its controller and several building
/// blocks so the two stay in sync on the underlying data.
///
/// The temperature chart is `NestTemperatureChart` from NestDetailSheet.swift,
/// shared rather than reimplemented so the two screens cannot drift on
/// gradients or thresholds. They feed it different bars: the sheet shows the
/// hours of one day, this screen shows a daily mean per day of the incubation,
/// which is the span a finished report is a record of.

import SwiftUI

/// The temperature chart's x axis: one slot per bar, laid out exactly as
/// `NestTemperatureChart` lays out its bars, so a label sits under the bar it
/// belongs to however many bars there are.
private struct NestTemperatureBarAxis: View {
    /// One entry per bar; nil leaves that slot unlabelled.
    let labels: [String?]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                // The label is an overlay, not the slot's content: a
                // `fixedSize` "90" is wider than a slot, and as content it
                // would claim that width and shove the labelled slots out of
                // line with the bars they belong to.
                Color.clear
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if let label {
                            Text(label)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(hex: "#8E8E93"))
                                .fixedSize()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

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

    let onBackToHatchery: () -> Void

    @State private var selectedTab: NestReportTab = .info

    // The sheet is always up (never dismissed by the user -- it's the page's
    // own layout, not an optional overlay), so this only ever flips true.
    @State private var isShowingReportSheet = true
    // Two stops: half the screen and full. Bound rather than fixed so both
    // the drag-to-expand gesture and the haptic below can see which one is
    // active.
    @State private var sheetDetent: PresentationDetent = .fraction(0.6)

    // The tally first, the nest second.
    //
    // refresh_nest_summary copies one onto the other, so they agree -- but only
    // after a round trip. The `nest` here is whatever snapshot the caller was
    // holding, and the flow arrives straight from recording a hatch, so its
    // copy still predates the save and every figure below reads nil. The
    // hatching record on the controller is reloaded as part of that save, so it
    // is the one that is current.
    private var hatchedCount: Int? { controller.hatching?.eggsHatched ?? nest.successEggsHatch }
    private var unhatchedCount: Int? { controller.hatching?.eggsUnhatched ?? nest.eggsUnhatched }
    private var rottenCount: Int? { controller.hatching?.eggsRotten ?? nest.failEggsHatch }

    private var successRatePercent: Double? {
        if let hatching = controller.hatching {
            return hatching.hatchRate(clutchSize: nest.numberOfEggs).map { $0 * 100 }
        }
        return nest.hatchRate.map { $0 * 100 }
    }

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
                        value: nest.datePredictedHatch.map(formattedDate) ?? "—"
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
            // The default week cannot fill a chart that spans the incubation.
            // Padded because this runs before the hatching record is loaded, so
            // `incubationInterval` is still reading the *predicted* hatch date
            // and a clutch that emerged late would lose its last days.
            let incubation = incubationInterval
            await controller.load(
                readingWindow: DateInterval(
                    start: incubation.start.addingTimeInterval(-86_400),
                    end: incubation.end.addingTimeInterval(7 * 86_400)
                )
            )
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
                // ponytail: report generation is not built, so this renders
                // disabled rather than being hidden -- the design puts it on
                // all three tabs and its absence would read as a missing
                // feature. Give it an action when there is a report to make.
                AddNestPrimaryButton(
                    title: "Download full report",
                    action: {},
                    isDisabled: true
                )
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
                // Figma 248:6806 heads the list with a plain grey label, not
                // the bold black one the other sections use.
                Text("Inspection list")
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: "#8E8E93"))

                if inspectionDates.isEmpty {
                    Text("No inspections recorded yet")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "#8E8E93"))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(inspectionDates.enumerated()), id: \.offset) { index, date in
                            if index > 0 {
                                Divider()
                            }
                            HStack {
                                Text("#\(index + 1)")
                                    .font(.body)
                                    .foregroundStyle(.black)
                                Spacer()
                                Text(formattedOrdinal(date))
                                    .font(.body)
                                    .foregroundStyle(Color(hex: "#8E8E93"))
                            }
                            .padding(.vertical, 16)
                        }
                    }
                    .padding(.horizontal, 16)
                    // Same white-on-grey card the temperature stats use, so
                    // the two tabs cannot drift on corner radius.
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: - Temperature

    private var temperatureTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(chartRangeText)
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
                // ponytail: the drill-down screen this points at does not
                // exist yet, so the control is disabled rather than silently
                // doing nothing. The chart below already covers the whole
                // incubation; what is missing is the hour-by-hour view of a
                // day you tap.
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Text("View temperature over time")
                            .font(.footnote)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "#8E8E93").opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(true)
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    NestTemperatureChart(values: chartBars.map(\.meanC), scale: 1)
                        .frame(height: 173)
                    dayAxis
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("°C")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "#8E8E93"))
                    NestTemperatureDegreeAxis(scale: 1)
                }
            }

            HStack(spacing: 12) {
                temperatureStat(title: "Avg", value: averageTemperatureText, tint: .black)
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

    // MARK: - Temperature over the incubation

    /// The span the chart draws: laid to hatched, which is the period the
    /// report is a record of. Falls back to four weeks before the hatch when a
    /// nest has no collection date, so an incomplete record still draws.
    private var incubationInterval: DateInterval {
        let calendar = Calendar.current
        let end = controller.hatching?.hatchedOn ?? nest.datePredictedHatch ?? .now
        let start = nest.dateEggsLaid
            ?? calendar.date(byAdding: .day, value: -28, to: end)
            ?? end
        return DateInterval(start: min(start, end), end: max(start, end))
    }

    private var chartBars: [NestTemperatureBuckets.Bar] {
        NestTemperatureBuckets.bars(across: incubationInterval, readings: controller.readings)
    }

    /// Day-of-incubation labels, on the same elastic grid the bars use so a
    /// label sits under its own bar. Only every `axisStep` day is marked --
    /// ninety of them would be a grey smear.
    private var dayAxis: some View {
        let bars = chartBars
        let step = NestTemperatureBuckets.axisStep(dayCount: incubationDayCount)

        return VStack(spacing: 2) {
            NestTemperatureBarAxis(
                labels: bars.map { bar in
                    NestTemperatureBuckets.axisMark(for: bar, step: step).map(String.init)
                }
            )

            Text("Days since collection")
                .font(.caption2)
                .foregroundStyle(Color(hex: "#8E8E93"))
                .frame(maxWidth: .infinity)
        }
    }

    private var incubationDayCount: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: incubationInterval.start),
            to: calendar.startOfDay(for: incubationInterval.end)
        ).day ?? 0
        return max(days, 0) + 1
    }

    private var chartRangeText: String {
        let interval = incubationInterval
        guard interval.start < interval.end else { return formattedDate(interval.start) }
        return (interval.start..<interval.end).formatted(date: .abbreviated, time: .omitted)
    }

    /// The stats beside the chart cover the same span the chart does. The
    /// controller is loaded with exactly that window, so this is every reading
    /// it holds.
    private var dailyReadings: [IoTDataEntity] {
        controller.readings
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

    /// Measured against the hatch that actually happened, not the one that was
    /// predicted. A clutch emerging a week early or late is exactly the case
    /// this figure exists to record, and `datePredictedHatch` would report the
    /// guess instead. Falls back to the prediction only while still incubating,
    /// where there is no actual date yet and the estimate is the honest answer.
    private var incubationPeriodText: String {
        guard let laid = nest.dateEggsLaid else { return "—" }
        guard let hatch = controller.hatching?.hatchedOn ?? nest.datePredictedHatch else {
            return "—"
        }
        let days = Calendar.current.dateComponents([.day], from: laid, to: hatch).day ?? 0
        return "\(max(days, 0)) days"
    }

    /// Abbreviated ("Oct 16, 2026"), not a spelled-out month. The header row
    /// gives this a third of the width and a wide month blows the padding.
    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// The dates the Inspection list shows.
    ///
    /// Recorded inspections when there are any. When there are none -- which is
    /// every nest today, because nothing writes inspection rows yet -- it falls
    /// back to the single date entered in the Add Nest flow, so a hatched
    /// nest's report shows the visit that was planned rather than nothing at
    /// all.
    ///
    /// That date only survives hatching for nests hatched after 20260821030000;
    /// earlier ones had it overwritten with NULL and show the empty message.
    // ponytail: a stand-in for the real inspection list. Delete the fallback --
    // not the property -- once the inspection flow writes rows.
    private var inspectionDates: [Date] {
        guard controller.inspections.isEmpty else {
            return controller.inspections.map(\.inspectedOn)
        }
        return [nest.nextInspectionDate].compactMap { $0 }
    }

    private func formattedOrdinal(_ date: Date) -> String {
        AppDateFormatting.ordinalDate(date)
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

    /// A plausible incubation rather than an empty list: the Temperature tab
    /// draws one bar per day across this window, and with no readings the
    /// preview is a row of grey stubs that shows nothing about the layout.
    func fetchReadings(nestIDs: [UUID], in interval: DateInterval?) async throws -> [IoTDataEntity] {
        guard let interval, let nestID = nestIDs.first else { return [] }

        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: interval.start)
        let dayCount = calendar.dateComponents(
            [.day], from: interval.start, to: interval.end
        ).day ?? 0
        guard dayCount > 0 else { return [] }

        return (0...dayCount).flatMap { day -> [IoTDataEntity] in
            // Every ninth day is left empty so the preview also shows the grey
            // stub a day with a dead logger draws.
            guard day % 9 != 4,
                  let date = calendar.date(byAdding: .day, value: day, to: midnight)
            else { return [] }

            // Warmest in the middle of the incubation, cooler at either end.
            let progress = Double(day) / Double(dayCount)
            let dailyMean = 27.5 + 3.5 * sin(progress * .pi)

            return [0, 6, 12, 18].map { hour in
                IoTDataEntity(
                    id: UUID(),
                    nestID: nestID,
                    temperatureC: dailyMean + 1.5 * sin(Double(hour) / 24 * 2 * .pi),
                    timestamp: calendar.date(byAdding: .hour, value: hour, to: date) ?? date
                )
            }
        }
    }

    func temperatureStats(nestID: UUID, from: Date, to: Date) async throws -> NestTemperatureStats? {
        nil
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
        onBackToHatchery: { }
    )
}
