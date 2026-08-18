//
//  HomeScreen.swift
//  community-challenge
//
//  Created by Nguyen Minh Luat on 10/8/26.
//

import SwiftUI

struct HomeView: View {
    @Bindable var controller: HatcheryController
    let container: AppContainer
    let onAddNest: () -> Void
    let onOpenHatcheryMenu: () -> Void
    var onOpenProfile: (() -> Void)?
    /// Opens the scan flow for this hatchery. Supplied where the empty state
    /// is reachable; the prompt is inert without it.
    var onScanHatchery: (() -> Void)?

    @State private var presentedSection: HatcherySectionDashboard?

    private var hatchery: HatcherySessionState { controller.sessionState }
    private var columns: [String] { hatchery.grid.columnLabels }
    private var rows: [String] { hatchery.grid.rowLabels }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = min(geometry.size.width, 402)
            let contentWidth = min(max(screenWidth - 32, 0), 370)
            let gridWidth = max(contentWidth - 21, 0)
            let gridHeight = gridWidth * 279 / 349

            ZStack(alignment: .topLeading) {
                HatcheryWarmBackdrop()

                VStack(alignment: .leading, spacing: 0) {
                    header(screenWidth: screenWidth)
                        .padding(.top, 87)
                        // The scanned grid below draws outside its own bounds
                        // (`scaledToFill` on the photo), and a sibling drawn
                        // later still takes the touches there. Without this the
                        // profile button is unpressable on any hatchery that
                        // has a scan, while looking perfectly normal.
                        .zIndex(1)

                    if hatchery.hasBeenScanned {
                        hatcheryGrid(width: gridWidth, height: gridHeight)
                            .padding(.top, 25)
                    } else {
                        // Figma 175:3792. A skipped scan still has a valid
                        // grid, so without this the dashboard draws a blank
                        // rectangle that reads as a loading failure.
                        HatcheryScanPrompt(onScan: { onScanHatchery?() })
                            .padding(.top, 25)
                            .padding(.leading, 16)
                    }

                    overview(width: contentWidth)
                        .padding(.top, 25)

                    // Placing a nest needs a mapped grid to place it on, so
                    // the design dims this to 30% until the scan exists.
                    HatcheryPrimaryButton(title: "Add new nest", action: onAddNest)
                    .disabled(!hatchery.hasBeenScanned)
                    .opacity(hatchery.hasBeenScanned ? 1 : 0.3)
                    .frame(width: contentWidth, height: 55)
                    .padding(.top, 36)
                    .padding(.leading, 16)
                }
                .frame(width: screenWidth, alignment: .leading)

                hatcherySelectorTapTarget(screenWidth: screenWidth)
            }
            .frame(width: screenWidth, height: geometry.size.height, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .sheet(item: $presentedSection) { section in
            SectionOverviewSheet(
                section: section,
                container: container,
                onNestDeleted: {
                    presentedSection = nil
                    await controller.load()
                }
            )
                .presentationDetents([.height(707)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .presentationSizing(.page)
        }
        .task { await controller.load() }
        .onAppear(perform: clearInactiveSelection)
        .onChange(of: hatchery.grid) { _, _ in
            clearInactiveSelection()
        }
    }

    private func header(screenWidth: CGFloat) -> some View {
        let headerWidth = max(screenWidth - 16, 0)
        let selectorTapWidth = min(176, max(headerWidth - 156, 0))

        return HStack(spacing: 0) {
            HatcherySelectorLabel(hatcheryName: hatchery.hatchery.name)
                .frame(width: selectorTapWidth, height: 48, alignment: .leading)

            Spacer(minLength: 0)

            HatcheryToolbarAccessories(onProfile: onOpenProfile)
        }
        .frame(width: headerWidth, height: 48)
        .padding(.leading, 16)
    }

    /// Kept as a top-level sibling of the dashboard rather than nested inside
    /// the title artwork. On physical devices this gives the selector one
    /// straightforward native Button hit-test path across its full target.
    private func hatcherySelectorTapTarget(screenWidth: CGFloat) -> some View {
        let headerWidth = max(screenWidth - 16, 0)
        let tapWidth = min(176, max(headerWidth - 156, 0))

        return Button(action: onOpenHatcheryMenu) {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: tapWidth, height: 56)
        .contentShape(Rectangle())
        .accessibilityIdentifier("hatchery-menu")
        .accessibilityLabel("Switch hatchery")
        .accessibilityHint("Opens the hatchery menu")
        .padding(.leading, 16)
        .padding(.top, 83)
    }

    private func hatcheryGrid(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 21)

                HStack(spacing: 2) {
                    ForEach(columns, id: \.self) { column in
                        Text(column)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.black.opacity(0.5))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: width)
            }
            .frame(width: width + 21, height: 16, alignment: .leading)

            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.self) { row in
                        Text(row)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.black.opacity(0.5))
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 9, height: height, alignment: .top)

                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(hex: "#BFCABD"))

                    Image(uiImage: hatchery.rectifiedPhoto)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                        .accessibilityLabel("Photo of \(hatchery.hatchery.name)")

                    VStack(spacing: 2) {
                        ForEach(rows.indices, id: \.self) { row in
                            HStack(spacing: 2) {
                                ForEach(columns.indices, id: \.self) { column in
                                    let sectionID = "\(columns[column])\(rows[row])"
                                    let section = gridSection(row: row, column: column)

                                    if section?.isActive == true {
                                        Button {
                                            controller.selectSection(id: sectionID)
                                        } label: {
                                            Color(hex: "#003C22")
                                                .opacity(controller.selectedSectionID == sectionID ? 0.70 : 0.30)
                                                .overlay {
                                                    if controller.selectedSectionID == sectionID {
                                                        sectionBadge(sectionID)
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .contentShape(Rectangle())
                                        .accessibilityLabel("Section \(sectionID)")
                                    } else {
                                        Color.black
                                            .opacity(0.14)
                                            .overlay {
                                                Rectangle()
                                                    .stroke(.white.opacity(0.18), lineWidth: 1)
                                            }
                                            .accessibilityElement(children: .ignore)
                                            .accessibilityLabel("Section \(sectionID), outside the marked sand area")
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .frame(width: width + 21, height: height, alignment: .leading)
        }
        .frame(width: width + 21, alignment: .leading)
        .padding(.leading, 16)
    }

    private func overview(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            // The whole row opens the section, not just the chevron. With no
            // section chosen there is nothing to open, so it stays inert text.
            if let section = selectedSection {
                Button { presentedSection = section } label: {
                    overviewHeaderRow
                }
                .buttonStyle(.plain)
            } else {
                overviewHeaderRow
            }

            VStack(spacing: 12) {
                temperatureCard(value: temperatureText(
                    selectedSection?.averageTemperatureC
                        ?? controller.overview?.averageTemperatureC
                ))

                HStack(spacing: 12) {
                    statCard(
                        title: "Nests",
                        value: (selectedSection?.nestCount
                            ?? controller.overview?.nestCount)
                            .map(String.init) ?? "--"
                    )
                    statCard(
                        title: "Eggs",
                        value: (selectedSection?.totalEggs
                            ?? controller.overview?.totalEggs)
                            .map(groupedNumber) ?? "--"
                    )
                }
                .frame(height: 85)
            }
            .padding(.top, 24)
        }
        .frame(width: width, height: 269, alignment: .top)
        .padding(.horizontal, 16)
    }

    private func temperatureCard(value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Average temperature")
                    .font(.caption)
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .opacity(0.8)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(Color(hex: "#0C7C4D"))
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 0) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .tracking(0.38)

                Text("°C")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.top, 2)
            }
            .foregroundStyle(Color(hex: "#0C7C4D"))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 104, alignment: .topLeading)
        .background(cardBackground)
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93"))
                .opacity(0.8)

            Spacer(minLength: 0)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .tracking(-0.45)
                .foregroundStyle(.black)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.white)
            .shadow(color: .black.opacity(0.05), radius: 10)
    }

    private var selectedSection: HatcherySectionDashboard? { controller.selectedSection }

    private func gridSection(row: Int, column: Int) -> HatcherySection? {
        hatchery.grid.sections.first { $0.row == row && $0.column == column }
    }

    private func clearInactiveSelection() {
        controller.clearInactiveSelection()
        if controller.selectedSection == nil {
            presentedSection = nil
        }
    }

    /// `.plain` hit-tests rendered content, and most of this row is the gap
    /// between the text and the chevron -- `.contentShape` makes that gap part
    /// of the target rather than a dead strip down the middle.
    private var overviewHeaderRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                overviewKicker
                    .font(.footnote)
                    .tracking(-0.08)
                    .lineLimit(1)

                Text("Check the status of the hatchery")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .tracking(-0.43)
                    .foregroundStyle(Color(hex: "#575757"))
            }

            Spacer(minLength: 0)

            if selectedSection != nil {
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(Color(hex: "#0C7C4D"))
                    .accessibilityHidden(true)
                    .frame(width: 44, height: 44, alignment: .trailing)
            }
        }
        .frame(height: 44)
        .contentShape(Rectangle())
    }

    private var overviewKicker: Text {
        guard let selectedSection else {
            return Text("HATCHERY OVERVIEW")
                .foregroundColor(Color(hex: "#757575"))
        }

        let sectionName = Text("SECTION \(selectedSection.id)")
            .fontWeight(.bold)
            .foregroundColor(Color(hex: "#0C7C4D"))

        return Text("HATCHERY \(sectionName) OVERVIEW")
            .foregroundColor(Color(hex: "#757575"))
    }

    private func sectionBadge(_ sectionID: String) -> some View {
        Text(sectionID)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.black)
            .frame(width: 35, height: 36)
            .background(.white, in: Capsule())
            .padding(4)
            .background(.white.opacity(0.24), in: Capsule())
            .accessibilityHidden(true)
    }

    private func temperatureText(_ temperature: Double?) -> String {
        guard let temperature else { return "—" }
        return String(format: "%.1f", temperature)
    }

    private func groupedNumber(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

private struct SectionOverviewSheet: View {
    let section: HatcherySectionDashboard
    let container: AppContainer
    let onNestDeleted: () async -> Void

    @State private var selectedNest: NestDetailSelection?

    var body: some View {
        SheetChrome(title: "Section \(section.id)") { sheetWidth in
            summary
                .frame(width: 370, height: 85, alignment: .top)
                .offset(x: (sheetWidth - 370) / 2, y: 71)

            nestList
                .offset(x: ceil((sheetWidth - 371) / 2), y: 167)
        }
        .sheet(item: $selectedNest) { selection in
            NestDetailSheet(
                item: selection.item,
                ordinal: selection.ordinal,
                sectionLabel: section.id,
                controller: container.makeNestDetailController(nestID: selection.item.id),
                onClose: { selectedNest = nil },
                onDelete: {
                    Task {
                        try? await container.makeNestService().deleteNest(id: selection.item.id)
                        selectedNest = nil
                        await onNestDeleted()
                    }
                }
            )
            // Figma 166:3244 draws the same 801pt sheet frame as the profile.
            .presentationDetents([.height(NestDetailSheet.Layout.detentHeight)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(34)
            .presentationSizing(.page)
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            sheetSummaryValue(
                title: "Average temperature",
                value: temperatureText(section.averageTemperatureC),
                unit: "°C",
                valueColor: Color(hex: "#0C7C4D"),
                alignment: .leading
            )
            .frame(width: 151, height: 85, alignment: .topLeading)

            sheetSummaryValue(title: "Nests", value: String(section.nestCount))
                .frame(width: 97.5, height: 85, alignment: .top)

            sheetSummaryValue(title: "Eggs", value: groupedNumber(section.totalEggs))
                .frame(width: 97.5, height: 85, alignment: .top)
        }
        .frame(width: 370, height: 85, alignment: .top)
    }

    private var nestList: some View {
        // The card stays 464pt because the sheet is a fixed 707 and this list
        // starts 167 down; what changed is that its contents scroll.
        //
        // It used to render `section.nests.prefix(4)` into exactly four 116pt
        // rows with no scroll view, so a section's fifth nest was counted in
        // the header above and then had nowhere to appear -- which reads as the
        // nest never having been saved.
        // Figma 166:2957 draws each nest as its own white card on the grouped
        // background, rather than divider-separated rows inside one card.
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Array(section.nests.enumerated()), id: \.element.id) { index, nest in
                    Button {
                        selectedNest = NestDetailSelection(item: nest, ordinal: index + 1)
                    } label: {
                        nestRow(nest, ordinal: index + 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        // Four or fewer nests fill the card exactly, so leave those sections
        // feeling fixed rather than springy.
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 371, height: 464)
    }

    private func nestRow(
        _ item: NestDashboardItem,
        ordinal: Int
    ) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("Nest #\(item.nest.displayNumber(fallbackOrdinal: ordinal))")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "#2B2B2B"))

                Spacer(minLength: 0)

                NestStatusPill.battery(level: item.batteryLevel)

                // A logger with no battery reading needs servicing rather than
                // opening, so Figma swaps the chevron for a wrench.
                Image(systemName: item.batteryLevel == nil ? "wrench.and.screwdriver" : "chevron.right")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .accessibilityHidden(true)
            }
            .frame(height: 36)

            HStack(spacing: 12) {
                NestStatusPill.temperature(item.latestTemperatureC)
                NestStatusPill.hatchCountdown(days: item.nest.daysUntilHatch)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(item.nest.numberOfEggs)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                    Text(" eggs")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: "#8E8E93"))
                }
            }
            .frame(height: 30)
        }
        .padding(16)
        .frame(width: 371, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func temperatureText(_ temperature: Double?) -> String {
        guard let temperature else { return "—" }
        return String(format: "%.1f", temperature)
    }

    private func groupedNumber(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private func hatchCountdown(for nest: NestEntity) -> String {
        guard let days = nest.daysUntilHatch else { return "Hatch date pending" }
        return days <= 0 ? "Hatching now" : "Hatch in \(days) days"
    }

    private func temperaturePresentation(for temperature: Double?) -> TemperaturePresentation {
        // Band and colour come from `NestTemperature` so this chip agrees
        // with the nest cards and the detail chart. Only the chip width is
        // decided here, since it depends on the rendered string.
        let band = NestTemperature.Band(temperatureC: temperature)
        return TemperaturePresentation(
            text: NestTemperature.textWithUnit(temperature),
            systemName: band == .noData ? "thermometer.medium" : band.systemImage,
            tint: band.tint,
            chipWidth: temperature == nil ? 76 : 85
        )
    }

    private struct TemperaturePresentation {
        let text: String
        let systemName: String
        let tint: Color
        let chipWidth: CGFloat
    }

    private struct NestDetailSelection: Identifiable {
        let item: NestDashboardItem
        let ordinal: Int

        var id: UUID { item.id }
    }

}

#Preview("Hatchery Overview", traits: .fixedLayout(width: 402, height: 874)) {
    let container = AppContainer()

    HomeView(
        controller: container.makeHatcheryController(sessionState: .previewSample),
        container: container,
        onAddNest: { },
        onOpenHatcheryMenu: { }
    )
}
