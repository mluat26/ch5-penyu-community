import SwiftUI

/// Figma 166:3082 (top) and 166:3244 (scrolled). One screen: the second frame
/// is the first one scrolled down, not a separate destination.
struct NestDetailSheet: View {
    let item: NestDashboardItem
    let ordinal: Int
    let sectionLabel: String
    @Bindable var controller: NestDetailController
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var isConfirmingDelete = false

    private var nest: NestEntity { item.nest }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    batteryPill
                    heroImage
                    summaryCard
                    weekStrip
                    temperatureChart
                    informationSection
                    timelineSection
                    inspectionSection
                    deleteButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Nest-\(nest.displayNumber(fallbackOrdinal: ordinal))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {} label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Edit nest")
                }
            }
            .safeAreaInset(edge: .bottom) { hatchedBar }
        }
        .task { await controller.load() }
        .confirmationDialog(
            "Delete this nest?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete nest", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the nest and its inspection history. It cannot be undone.")
        }
    }

    private var batteryPill: some View {
        NestStatusPill.battery(level: item.batteryLevel)
    }

    private var heroImage: some View {
        Image("NestImage")
            .resizable()
            .scaledToFit()
            .frame(height: 168)
            .accessibilityHidden(true)
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryColumn(
                title: "Average temperature",
                value: controller.latestTemperatureC.map { String(format: "%.1f", $0) }
                    ?? item.latestTemperatureC.map { String(format: "%.1f", $0) } ?? "--",
                unit: "°C",
                tint: Color(hex: "#0C7C4D")
            )
            summaryColumn(title: "Eggs", value: "\(nest.numberOfEggs)", unit: nil, tint: .black)
            summaryColumn(title: "Sections", value: sectionLabel, unit: nil, tint: .black)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private func summaryColumn(
        title: String,
        value: String,
        unit: String?,
        tint: Color
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(hex: "#8E8E93"))
                .multilineTextAlignment(.center)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint)
                if let unit {
                    Text(unit)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Seven days ending today, so the strip always includes the present
    /// rather than running into dates with no readings.
    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)

                Button {
                    selectedDay = day
                } label: {
                    VStack(spacing: 8) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color(hex: "#8E8E93"))

                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(isSelected ? .white : .black)
                            .frame(width: 30, height: 30)
                            .background {
                                if isSelected {
                                    Circle().fill(Color(hex: "#8E8E93"))
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var temperatureChart: some View {
        let readings = controller.readings(on: selectedDay)

        return VStack(alignment: .leading, spacing: 4) {
            Text("Temperature now")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "#8E8E93"))

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(controller.latestTemperatureC.map { String(format: "%.1f", $0) } ?? "--")
                    .font(.system(size: 22, weight: .bold))
                Text("°C")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Color(hex: "#E5399B"))

            if readings.isEmpty {
                // A nest with no logger, or a day before it was deployed. Say
                // so rather than drawing an empty axis that looks broken.
                Text("No readings for this day")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                NestTemperatureChart(readings: readings)
                    .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var informationSection: some View {
        detailSection(title: "Information", subtitle: "Nest detail information") {
            InfoRow(title: "Bucket ID", value: nest.bucketID ?? "—")
            Divider().padding(.leading, 16)
            InfoRow(title: "Data logger", value: "—")
            Divider().padding(.leading, 16)
            InfoRow(
                title: "Collection date",
                value: nest.dateEggsLaid?.formatted(.dateTime.day().month(.wide).year()) ?? "—",
                isBadge: true
            )
            Divider().padding(.leading, 16)
            InfoRow(title: "Location", value: nest.locationAddress ?? "—", showsChevron: true)
        }
    }

    private var timelineSection: some View {
        detailSection(title: "Timeline", subtitle: "Hatching timeline") {
            HStack(spacing: 12) {
                timelineStat(title: "Duration", value: durationText)
                timelineStat(title: "Prediction", value: predictionText)
            }
            .padding(16)

            Divider().padding(.leading, 16)
            InfoRow(
                title: "Inspection date",
                value: nest.nextInspectionDate?.formatted(.dateTime.day().month(.wide).year()) ?? "—",
                isBadge: true
            )
            Divider().padding(.leading, 16)
            InfoRow(
                title: "Prediction",
                subtitle: "Hatching date",
                value: nest.datePredictedHatch?.formatted(.dateTime.day().month(.wide).year()) ?? "—",
                isBadge: true
            )
        }
    }

    /// Days since the eggs were laid — how long this nest has been incubating.
    private var durationText: String {
        guard let laid = nest.dateEggsLaid else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: laid, to: .now).day ?? 0
        return "\(max(days, 0)) days"
    }

    private var predictionText: String {
        guard let days = nest.daysUntilHatch else { return "—" }
        if days <= 0 { return "Due" }
        return days == 1 ? "1 day" : "\(days) days"
    }

    private func timelineStat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "#8E8E93"))
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(hex: "#F1F1F1"), in: RoundedRectangle(cornerRadius: 16))
    }

    private var inspectionSection: some View {
        detailSection(title: "Inspection list", subtitle: "Hatching timeline") {
            if controller.inspections.isEmpty {
                Text("No inspections recorded yet")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ForEach(Array(controller.inspections.enumerated()), id: \.element.id) { index, inspection in
                    if index > 0 { Divider().padding(.leading, 16) }
                    InfoRow(
                        title: "#\(index + 1)",
                        value: inspection.inspectedOn.formatted(.dateTime.day().month(.wide).year()),
                        isBadge: true
                    )
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            Text("Delete nest")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(hex: "#FF383C"), in: RoundedRectangle(cornerRadius: 26))
        }
        .buttonStyle(.plain)
    }

    private var hatchedBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.black)
                .frame(width: 50, height: 50)
                .background(.white, in: Circle())
                .accessibilityLabel("Notes")

            Text("Hatched")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 55)
                .background(Color.appGreenPrimary, in: RoundedRectangle(cornerRadius: 26))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func detailSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#8E8E93"))
            }

            VStack(spacing: 0) { content() }
                .background(.white, in: RoundedRectangle(cornerRadius: 24))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InfoRow: View {
    let title: String
    var subtitle: String?
    let value: String
    var isBadge = false
    var showsChevron = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.black)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: "#8E8E93"))
                }
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 15, weight: isBadge ? .semibold : .regular))
                .foregroundStyle(isBadge ? .black : Color(hex: "#8E8E93"))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, isBadge ? 12 : 0)
                .padding(.vertical, isBadge ? 6 : 0)
                .background {
                    if isBadge {
                        RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#F1F1F1"))
                    }
                }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// The gradient bar chart from Figma 166:3082. Bars run cool-to-warm by
/// temperature rather than by position, so a hot reading is obvious wherever
/// it falls in the day.
private struct NestTemperatureChart: View {
    let readings: [IoTDataEntity]

    private var temperatures: [Double] { readings.compactMap(\.temperatureC) }

    private var range: ClosedRange<Double> {
        guard let low = temperatures.min(), let high = temperatures.max() else {
            return 18...33
        }
        // A flat day would otherwise divide by zero and draw nothing.
        return low == high ? (low - 1)...(high + 1) : low...high
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(temperatures.enumerated()), id: \.offset) { _, temperature in
                let span = range.upperBound - range.lowerBound
                let fraction = (temperature - range.lowerBound) / span

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#7BD143"), tint(for: fraction)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: max(12, fraction * 160))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Temperature through the day")
        .accessibilityValue(
            temperatures.isEmpty
                ? "No readings"
                : String(
                    format: "From %.1f to %.1f degrees",
                    temperatures.min() ?? 0,
                    temperatures.max() ?? 0
                )
        )
    }

    private func tint(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.34: Color(hex: "#C8D93A")
        case ..<0.67: Color(hex: "#F5A623")
        default: Color(hex: "#A24BD1")
        }
    }
}
