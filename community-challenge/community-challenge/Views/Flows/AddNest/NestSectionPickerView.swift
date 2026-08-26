import SwiftUI
import UIKit

/// The map-selection destination of the add-nest flow. Keeping it separate
/// from the identity, egg-details, preview, and success screens makes the
/// navigation flow easier to follow without changing its UI or state model.
struct NestSectionPickerView: View {
    @Bindable var controller: NestController
    let grid: HatcheryGrid
    let mapImage: UIImage
    let usesMockMapCrop: Bool
    let dashboard: HatcheryDashboard?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var pendingSection: String

    init(
        controller: NestController,
        grid: HatcheryGrid,
        mapImage: UIImage,
        usesMockMapCrop: Bool,
        dashboard: HatcheryDashboard?,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.controller = controller
        self.grid = grid
        self.mapImage = mapImage
        self.usesMockMapCrop = usesMockMapCrop
        self.dashboard = dashboard
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _pendingSection = State(initialValue: controller.draft.section)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Presented as a sheet over the form, so it carries its own bar
            // rather than a navigation bar: the choice is confirmed or
            // abandoned here and does not become a step in the flow's history.
            sheetBar

            ScrollView {
                VStack(spacing: 10) {
                    infoCard

                    NestSectionMapView(
                        image: mapImage,
                        usesMockCrop: usesMockMapCrop,
                        grid: grid,
                        selectedSectionID: pendingSection,
                        onSelect: { section in
                            guard section.isActive else { return }
                            pendingSection = section.id
                        }
                    )

                    selectionSummary
                }
                .padding(.horizontal, 10)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .background(.white)
        .preferredColorScheme(.light)
    }

    private var sheetBar: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appNeutralBlack)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel section selection")

            Spacer()

            Text("Select the section")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.appNeutralBlack)

            Spacer()

            Button(action: confirmSelection) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(
                        pendingSection.isEmpty
                            ? Color.appNeutralGray3
                            : Color.appGreenPrimary
                    )
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(pendingSection.isEmpty)
            .accessibilityLabel("Confirm section selection")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white)
    }

    private var infoCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "info.circle")
                .font(.system(size: 28))
                .foregroundStyle(Color.appGreenPrimary)

            VStack(alignment: .leading, spacing: 0) {
                Text("Place it on the map")
                    .font(.body)
                    .foregroundStyle(Color.appNeutralGray2)

                Text("Choose the grid where this nest will be registered.")
                    .font(.footnote)
                    .foregroundStyle(Color(hex: "#AEAEB2"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: 370, minHeight: 78, alignment: .leading)
        .background(Color.appGreenPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private var selectionSummary: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "graph.3d")
                    .font(.system(size: 42))
                    .foregroundStyle(Color.appGreenPrimary)
                    .frame(width: 62, height: 59)

                Text(selectedMapSection.map { "Section \($0.id)" } ?? "Choose a section")
                    .font(.headline)
                    .foregroundStyle(.black)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .frame(width: 370, height: 59)
            .clipped()

            Color.clear
                .frame(width: 350, height: 0)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 1)
                        .offset(y: -1)
                }

            HStack(spacing: 10) {
                selectionMetric(
                    title: "Average temperature",
                    value: temperatureText,
                    unit: temperatureText == "—" ? nil : "°C",
                    color: Color(hex: "#0C7C4D"),
                    valueWeight: .bold,
                    width: 177
                )

                selectionMetric(
                    title: "Registered nests",
                    value: selectedSectionDashboard.map { String($0.nestCount) } ?? "—",
                    unit: nil,
                    color: .black,
                    valueWeight: .semibold,
                    width: 168
                )

                Spacer(minLength: 0)
            }
            .frame(width: 370, height: 85, alignment: .leading)
        }
        .frame(width: 370)
    }

    private func selectionMetric(
        title: String,
        value: String,
        unit: String?,
        color: Color,
        valueWeight: Font.Weight,
        width: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93"))
                .opacity(0.8)
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: 16, alignment: .top)

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 0) {
                Text(value)
                    .font(.system(size: 20, weight: valueWeight))

                if let unit {
                    Text(unit)
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: 25, alignment: .top)
        }
        .padding(16)
        .frame(width: width, height: 85)
        .background(Color.clear, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 10)
    }

    private var selectedMapSection: HatcherySection? {
        grid.sections.first { $0.id == pendingSection }
    }

    private var selectedSectionDashboard: HatcherySectionDashboard? {
        guard let selectedMapSection else { return nil }
        return dashboard?.section(row: selectedMapSection.row, column: selectedMapSection.column)
    }

    private var temperatureText: String {
        guard let temperature = selectedSectionDashboard?.averageTemperatureC else { return "—" }
        return temperature.formatted(.number.precision(.fractionLength(1)))
    }

    private func confirmSelection() {
        guard let selection = selectedMapSection, selection.isActive else { return }
        controller.draft.section = selection.id
        controller.draft.sectionRow = selection.row
        controller.draft.sectionColumn = selection.column
        onConfirm()
    }
}

private struct NestSectionMapView: View {


    let image: UIImage
    let usesMockCrop: Bool
    let grid: HatcheryGrid
    let selectedSectionID: String
    let onSelect: (HatcherySection) -> Void

    private var rows: Int { max(grid.rows, 1) }
    private var columns: Int { max(grid.columns, 1) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Color.clear
                    .frame(width: 9, height: 16)

                HStack(spacing: 2) {
                    ForEach(0..<columns, id: \.self) { column in
                        Text(column < grid.columnLabels.count
                             ? grid.columnLabels[column]
                             : HatcheryGrid.columnLabel(column))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.black.opacity(0.5))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        Text(row < grid.rowLabels.count ? grid.rowLabels[row] : "\(row + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.black.opacity(0.5))
                            .frame(maxWidth: .infinity)

                        if row < rows - 1 {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 40)
                .frame(width: 9, height: 279)

                GeometryReader { geometry in
                    ZStack {
                        // Stretched to the box, so the cell grid below fills
                        // the identical rect and a tapped cell is always the
                        // sand under it.
                        HatcherySetupImage(
                            image: image,
                            usesMockCrop: usesMockCrop,
                            contentMode: .stretch
                        )

                        VStack(spacing: 2) {
                            ForEach(0..<rows, id: \.self) { row in
                                HStack(spacing: 2) {
                                    ForEach(0..<columns, id: \.self) { column in
                                        sectionCell(row: row, column: column)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .frame(height: 279)
            }
        }
        .frame(maxWidth: 370)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hatchery grid, \(columns) columns and \(rows) rows")
    }

    @ViewBuilder
    private func sectionCell(row: Int, column: Int) -> some View {
        if let section = grid.sections.first(where: { $0.row == row && $0.column == column }) {
            Button {
                onSelect(section)
            } label: {
                ZStack {
                    sectionColor(for: section)

                    if section.id == selectedSectionID {
                        Text(section.id)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.black)
                            .frame(width: 35, height: 35)
                            .background(.white, in: Circle())
                            .padding(4)
                            .background(.white.opacity(0.24), in: Circle())
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!section.isActive)
            .accessibilityLabel("Section \(section.id)")
            .accessibilityValue(section.id == selectedSectionID ? "Selected" : "")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.black.opacity(0.12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sectionColor(for section: HatcherySection) -> Color {
        guard section.isActive else { return .black.opacity(0.14) }
        return Color(hex: "#003C22").opacity(section.id == selectedSectionID ? 0.7 : 0.3)
    }
}
