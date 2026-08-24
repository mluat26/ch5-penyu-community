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

    /// The photo's drawn size inside the fixed container: its own aspect
    /// ratio, fitted, never cropped and never stretched. Centred by the
    /// enclosing `ZStack`, so leftover space is even on both sides.
    ///
    /// `rectification` crops the corrected photo to the sand region's bounding
    /// box, so its shape is whatever was dragged. `scaledToFill` used to crop
    /// the sand back off to cover the container while the cell grid still
    /// spanned the whole thing, and the sections stopped landing on the sand
    /// they came from. The grid is sized to this rect too, so the two cannot
    /// disagree. Space left over shows the container's own sage fill, which was
    /// always painted behind the photo.
    private func photoFit(in box: CGSize) -> CGSize {
        let size = hatchery.rectifiedPhoto.size
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else {
            return box
        }
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
    private var columns: [String] { hatchery.grid.columnLabels }
    private var rows: [String] { hatchery.grid.rowLabels }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = min(geometry.size.width, 402)
            let contentWidth = min(max(screenWidth - 32, 0), 370)
            let gridWidth = max(contentWidth - 21, 0)
            // A fixed container, deliberately. The photo is fitted and
            // centred inside it, so a small or oddly shaped sand area changes
            // nothing below: the overview cards and the Add-nest button stay
            // exactly where they were. Deriving the container from the photo
            // made the whole screen shift every time a scan shape differed.
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
                hatcheryName: hatchery.hatchery.name,
                onNestDeleted: {
                    presentedSection = nil
                    await controller.load()
                },
                onNestChanged: {
                    await controller.load()
                    // The sheet holds a copy of its section, so reloading the
                    // dashboard alone would leave the list underneath showing
                    // the nest exactly as it was. Re-read the same section from
                    // the refreshed dashboard instead of dismissing.
                    if let refreshed = controller.dashboard?
                        .section(row: section.row, column: section.column) {
                        presentedSection = refreshed
                    }
                },
                onReturnToHatchery: { presentedSection = nil }
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
        let photo = photoFit(in: CGSize(width: width, height: height))

        return VStack(spacing: 10) {
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
                .frame(width: 9, height: photo.height, alignment: .top)

                ZStack {
                    // Transparent, not sage. The container is fixed so the
                    // layout below never moves, which means a photo that does
                    // not share its shape leaves space above and below --
                    // filling that space drew a slab around the photo. Clear
                    // lets the page backdrop through, so only the photo reads
                    // as content.
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.clear)

                    Image(uiImage: hatchery.rectifiedPhoto)
                        .resizable()
                        .scaledToFit()
                        .frame(width: photo.width, height: photo.height)
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
                                        // Off-sand cells show the photo rather
                                        // than a grey tile: there is no section
                                        // there to select, place a nest in, or
                                        // report on, so drawing one only hides
                                        // the sand that decided it.
                                        //
                                        // Still laid out, never omitted. The
                                        // lattice slot *is* the tie to the
                                        // photo underneath -- dropping a cell
                                        // from the stack reflows every cell
                                        // after it and slides the whole grid
                                        // out of register.
                                        Color.clear
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                    }
                    .frame(
                        width: max(0, photo.width - 16),
                        height: max(0, photo.height - 16)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .frame(width: width + 21, height: height, alignment: .leading)
        }
        .frame(width: width + 21, alignment: .leading)
        // Centres the photo rather than the block. The 21 pt row-label gutter
        // is inside this frame, so centring the frame alone would leave the
        // photo half a gutter right of centre -- which is what it looked like.
        // Layout is otherwise untouched: same widths, same spacing, same rows.
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(x: -Self.rowLabelGutter / 2)
    }

    /// Width reserved to the left of the grid for the row labels.
    private static let rowLabelGutter: CGFloat = 21

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

/// Which nests the section list shows.
///
/// "Hatched" reads `NestEntity.hasHatched` -- the nest carries a tally --
/// rather than `isComplete`, which is also true for a nest an inspection closed
/// without one. No extra query either way; this is data the dashboard already
/// holds.
private enum NestHatchFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unhatched = "Unhatched"
    case hatched = "Hatched"

    var id: String { rawValue }

    func matches(_ nest: NestEntity) -> Bool {
        switch self {
        case .all: true
        case .hatched: nest.hasHatched
        case .unhatched: !nest.hasHatched
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: "No nests in this section"
        case .hatched: "No hatched nests in this section"
        case .unhatched: "No nests still incubating here"
        }
    }
}

private struct SectionOverviewSheet: View {
    let section: HatcherySectionDashboard
    let container: AppContainer
    let hatcheryName: String
    let onNestDeleted: () async -> Void
    let onNestChanged: () async -> Void
    let onReturnToHatchery: () -> Void

    @State private var selectedNest: NestDetailSelection?
    @State private var filter: NestHatchFilter = .all

    /// Ordinals are assigned before filtering, never after.
    ///
    /// Numbering a filtered array renumbers every nest in it, so the same nest
    /// would answer to a different number depending on which filter happened to
    /// be selected -- the exact failure `NestEntity.displayNumber` exists to
    /// prevent. Position in the unfiltered section is the identity.
    private var rows: [(ordinal: Int, item: NestDashboardItem)] {
        section.nests.enumerated()
            .map { (ordinal: $0.offset + 1, item: $0.element) }
            .filter { filter.matches($0.item.nest) }
    }

    var body: some View {
        SheetChrome(title: "Section \(section.id)") { sheetWidth in
            summary
                .frame(width: 370, height: 85, alignment: .top)
                .offset(x: (sheetWidth - 370) / 2, y: 71)

            filterPicker
                .frame(width: 371)
                .offset(x: ceil((sheetWidth - 371) / 2), y: 167)

            nestList
                .offset(x: ceil((sheetWidth - 371) / 2), y: 207)
        }
        .sheet(item: $selectedNest) { selection in
            NestDetailSheet(
                item: selection.item,
                ordinal: selection.ordinal,
                sectionLabel: section.id,
                controller: container.makeNestDetailController(nestID: selection.item.id),
                makeHatchingController: { container.makeHatchingController(nest: $0) },
                hatcheryName: hatcheryName,
                onClose: { selectedNest = nil },
                onDelete: {
                    Task {
                        try? await container.makeNestService().deleteNest(id: selection.item.id)
                        selectedNest = nil
                        await onNestDeleted()
                    }
                },
                onNestChanged: onNestChanged,
                // Dismissing this sheet alone would only fall back to the
                // section list, which is itself a sheet over the hatchery. The
                // host closes the section instead, and this one goes with it.
                onReturnToHatchery: onReturnToHatchery
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
        // Figma 199:3473 makes the list 371x508 at y=167 in the 713pt sheet:
        // four 118pt cards with 12pt gutters, so four fit without scrolling.
        //
        // It used to render `section.nests.prefix(4)` into exactly four 116pt
        // rows with no scroll view, so a section's fifth nest was counted in
        // the header above and then had nowhere to appear -- which reads as the
        // nest never having been saved.
        // Figma 166:2957 draws each nest as its own white card on the grouped
        // background, rather than divider-separated rows inside one card.
        ScrollView {
            VStack(spacing: 12) {
                if rows.isEmpty {
                    // An empty list with no explanation reads as a failed load,
                    // which is the same reasoning that removed the old
                    // `prefix(4)` truncation above.
                    Text(filter.emptyMessage)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(rows, id: \.item.id) { row in
                        Button {
                            selectedNest = NestDetailSelection(item: row.item, ordinal: row.ordinal)
                        } label: {
                            nestRow(row.item, ordinal: row.ordinal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        // Four or fewer nests fill the list exactly, so leave those sections
        // feeling fixed rather than springy.
        .scrollBounceBehavior(.basedOnSize)
        // 40pt shorter than before: the picker above took that space.
        .frame(width: 371, height: 468)
    }

    private var filterPicker: some View {
        Picker("Show", selection: $filter) {
            ForEach(NestHatchFilter.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
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

                // A logger with no battery reading needs servicing rather than
                // opening, so Figma swaps the chevron for a wrench. The
                // battery pill itself is not on the card.
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

// The fixture this preview uses only exists in DEBUG, and a #Preview body still
// compiles in Release -- without this guard the archive fails to build.
#if DEBUG
#Preview("Hatchery Overview", traits: .fixedLayout(width: 402, height: 874)) {
    let container = AppContainer()

    HomeView(
        controller: container.makeHatcheryController(sessionState: .previewSample),
        container: container,
        onAddNest: { },
        onOpenHatcheryMenu: { }
    )
}
#endif
