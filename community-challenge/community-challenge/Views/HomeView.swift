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
    
    @State private var presentedScope: NestListScope?
    @State private var presentedFilter: NestHatchFilter = .all
    
    /// Hatcheries whose coach mask was dismissed in this session. `UserDefaults`
    /// is not observable, so this set is what re-renders the grid after the tap;
    /// the defaults key is what survives a relaunch.
    ///
    @State private var coachDismissed: Set<UUID> = []
    
    private var coachMaskKey: String {
        "coach.tapSection.\(hatchery.hatchery.id.uuidString)"
    }
    
    /// Derived per render rather than latched in `onAppear`: switching hatchery
    /// reuses this view, so a stored flag would answer for the previous one.
    private var showCoachMask: Bool {
        !coachDismissed.contains(hatchery.hatchery.id)
        && !UserDefaults.standard.bool(forKey: coachMaskKey)
    }
    
    
    private var hatchery: HatcherySessionState { controller.sessionState }

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
                    // Figma puts this at y=786 on an 874pt canvas -- anchored
                    // near the bottom with the slack above it, not pinned a
                    // fixed gap under the cards. `minLength` keeps a sensible
                    // separation on a short screen, where the slack runs out.
                    Spacer(minLength: 24)

                    HatcheryPrimaryButton(title: "Add new nest", action: onAddNest)
                        .disabled(!hatchery.hasBeenScanned)
                        .opacity(hatchery.hasBeenScanned ? 1 : 0.3)
                        .frame(width: contentWidth, height: 55)
                        .padding(.bottom, 33)
                        .padding(.leading, 16)
                }
                .frame(width: screenWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                
                hatcherySelectorTapTarget(screenWidth: screenWidth)
            }
            .frame(width: screenWidth, height: geometry.size.height, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .sheet(item: $presentedScope) { scope in
            SectionOverviewSheet(
                style: scope.style,
                scope: scope,
                filter: $presentedFilter,
                container: container,
                hatcheryName: hatchery.hatchery.name,
                onNestDeleted: {
                    presentedScope = nil
                    await controller.load()
                },
                onNestChanged: {
                    await controller.load()
                    // The sheet holds a copy of its scope, so reloading the
                    // dashboard alone would leave the list underneath showing
                    // the nest exactly as it was. Rebuild the same scope from
                    // the refreshed dashboard instead of dismissing.
                    if let refreshed = rescope(scope) {
                        presentedScope = refreshed
                    }
                },
                onReturnToHatchery: { presentedScope = nil }
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
        // Drawn on every active cell now, so it has to fit the smallest one.
        // A nine-column grid gives roughly 19pt cells; the design's fixed 35pt
        // circle overflowed them and each row fused into one white bar.
        // Measured against the container, which the photo now fills exactly.
        let badgeDiameter = min(35, min(
            (width - 16 - 2 * CGFloat(columns.count - 1)) / CGFloat(max(columns.count, 1)),
            (height - 16 - 2 * CGFloat(rows.count - 1)) / CGFloat(max(rows.count, 1))
        ) - 6)
        
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
                // Both label runs measure the photo, not the container it is
                // fitted into. The container is deliberately fixed while the
                // photo is centred inside it, so labels spanning the container
                // name columns the photo never draws -- which is what pushed A
                // and I past the ends of the grid. The 8pt inset is the
                // lattice's own, so the cells divide identically.
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
                .padding(.vertical, 8)
                .frame(width: 9, height: height, alignment: .top)

                ZStack {
                    // Transparent, not sage. The container is fixed so the
                    // layout below never moves, which means a photo that does
                    // not share its shape leaves space above and below --
                    // filling that space drew a slab around the photo. Clear
                    // lets the page backdrop through, so only the photo reads
                    // as content.
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.clear)

                    // Figma 286:4832 covers the 349 x 279 card edge to edge and
                    // clips it to the card's radius, so the photo fills rather
                    // than stretches: no bars, and no squashing when the scan
                    // is a different shape to the card.
                    //
                    // The cost is the crop. A scan far from 349:279 loses its
                    // outer edge, and the cell grid still spans the whole card,
                    // so the outermost cells cover sand that was cropped away.
                    // Everything inside stays aligned, which is where the nests
                    // are -- but a very wide hatchery is the case to watch.
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
                                    let isSelected = controller.selectedSectionID == sectionID
                                    let nestCount = controller.dashboard?.section(row: row, column: column)?.nestCount ?? 0
                                    
                                    if section?.isActive == true {
                                        Button {
                                            controller.selectSection(id: sectionID)
                                        } label: {
                                            Color(hex: "#003C22")
                                                .opacity(isSelected ? 0.70 : 0.30)
                                                .overlay {
                                                    // Below about 12pt the circle is
                                                    // unreadable anyway, so a very dense
                                                    // grid shows the tint alone.
                                                    if badgeDiameter >= 12 {
                                                        nestCountBadge(
                                                            count: nestCount,
                                                            isSelected: isSelected,
                                                            diameter: badgeDiameter
                                                        )
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .contentShape(Rectangle())
                                        .accessibilityLabel("Section \(sectionID), \(nestCount) nests")
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
                    .padding(8)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    if showCoachMask {
                        coachMask(size: CGSize(width: width, height: height))
                    }
                }
                // The photo fills the container, so this is simply the
                // container plus the label gutter. Height stays
                // the container's: that is what keeps the overview cards and
                // the Add-nest button from moving when a scan's shape differs.
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
            // The whole row opens the list, not just the chevron -- scoped to
            // the selected section, or the whole hatchery when there is none.
            Button { openNestList(filter: .all) } label: {
                overviewHeaderRow
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                overviewCard(
                    title: "Avg. temperature",
                    value: temperatureText(
                        selectedSection?.averageTemperatureC
                        ?? controller.overview?.averageTemperatureC
                    ),
                    unit: "°C",
                    valueColor: Color(hex: "#0C7C4D")
                )
                overviewCard(
                    title: "Hatching soon",
                    value: "\(scopeNests.filter(\.nest.isHatchingSoon).count)",
                    action: { openNestList(filter: .hatchingSoon) }
                )
                overviewCard(
                    title: "Inspection",
                    value: "\(scopeNests.filter { $0.nest.isDueForInspection() }.count)",
                    action: { openNestList(filter: .inspection) }
                )
            }
            .frame(height: 104)
            .padding(.top, 15)

            alertSection
                .padding(.top, 15)
        }
        .frame(width: width, alignment: .top)
        .padding(.horizontal, 16)
    }
    
    /// One overview card. `action` nil means the card is inert and draws no
    /// chevron -- the only thing separating the temperature card from the two
    /// that open the nest list.
    private func overviewCard(
        title: String,
        value: String,
        unit: String = "",
        valueColor: Color = .black,
        action: (() -> Void)? = nil
    ) -> some View {
        let card = VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .opacity(0.8)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 0)
                
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundStyle(Color(hex: "#0C7C4D"))
                        .accessibilityHidden(true)
                }
            }
            
            Spacer(minLength: 0)
            
            HStack(alignment: .top, spacing: 0) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .tracking(0.38)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.top, 2)
                }
            }
            .foregroundStyle(valueColor)
        }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(cardBackground)
        
        return Group {
            if let action {
                Button(action: action) { card }
                    .buttonStyle(.plain)
                    .contentShape(RoundedRectangle(cornerRadius: 24))
            } else {
                card
            }
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.white)
            .shadow(color: .black.opacity(0.05), radius: 10)
    }
    
    private var selectedSection: HatcherySectionDashboard? { controller.selectedSection }
    
    /// What the overview cards count: the selected section, or the whole
    /// hatchery when nothing is selected.
    private var scopeNests: [NestDashboardItem] {
        selectedSection?.nests ?? controller.dashboard?.allNests ?? []
    }
    
    /// The scope the overview is currently describing.
    private var currentScope: NestListScope? {
        if let selectedSection { return NestListScope(section: selectedSection) }
        return controller.dashboard.map(NestListScope.init(dashboard:))
    }
    
    /// The style travels inside `presentedScope`, never beside it.
    ///
    /// A sibling `@State` read from inside the `.sheet` closure returns the
    /// value captured in that closure's copy of the view -- the one from before
    /// this tap -- so an alert opened a sheet still carrying the previous
    /// style. `AppRootView` documents the same trap on its rescan cover.
    private func openNestList(
        filter: NestHatchFilter,
        style: SectionOverviewSheet.Style = .full
    ) {
        guard let currentScope else { return }
        presentedFilter = filter
        presentedScope = currentScope.presented(as: style)
    }
    
    /// The same scope rebuilt from the freshly loaded dashboard.
    private func rescope(_ scope: NestListScope) -> NestListScope? {
        guard let dashboard = controller.dashboard else { return nil }
        guard let sectionID = scope.sectionID else {
            return NestListScope(dashboard: dashboard)
        }
        return dashboard.sections.first { $0.id == sectionID }
            .map(NestListScope.init(section:))
    }
    
    private func gridSection(row: Int, column: Int) -> HatcherySection? {
        hatchery.grid.sections.first { $0.row == row && $0.column == column }
    }
    
    private func clearInactiveSelection() {
        controller.clearInactiveSelection()
        // Only a section scope can go stale; the hatchery-wide list survives
        // a section being deselected or dropped from the grid.
        if controller.selectedSection == nil, presentedScope?.sectionID != nil {
            presentedScope = nil
        }
    }
    
    
    /// Every nest in scope that is warning about its temperature, with the
    /// section and position needed to name it.
    ///
    /// Ordinals count within the nest's own section and before any filtering,
    /// which is the same rule `NestEntity.displayNumber` and the list sheet
    /// follow -- a nest must not answer to a different number depending on
    /// which screen is asking.
    private var alertingNests: [(
        sectionID: String,
        ordinal: Int,
        item: NestDashboardItem,
        alert: NestDashboardItem.TemperatureAlert
    )] {
        let sections = selectedSection.map { [$0] } ?? controller.dashboard?.sections ?? []

        return sections.flatMap { section in
            section.nests.enumerated().compactMap { offset, item in
                item.temperatureAlert.map {
                    (section.id, offset + 1, item, $0)
                }
            }
        }
    }

    /// Figma 288:5352 stacks both bars when both apply, and 288:4983 shows the
    /// calm bar when neither does -- so there is always exactly one answer on
    /// screen rather than an empty space that could mean either.
    @ViewBuilder
    private var alertSection: some View {
        let alerting = alertingNests
        let outOfRange = alerting.filter { $0.alert == .outOfRange }
        let noData = alerting.filter { $0.alert == .noData }

        VStack(spacing: 10) {
            if outOfRange.isEmpty, noData.isEmpty {
                calmBar
            } else {
                if !outOfRange.isEmpty {
                    alertBar(
                        tint: Color(hex: "#FF3B30"),
                        title: "Temperature out of range",
                        caption: countCaption(
                            outOfRange.count,
                            ending: "with a temperature warning"
                        )
                    )
                }

                if !noData.isEmpty {
                    alertBar(
                        tint: Color(hex: "#FF9500"),
                        title: "No temperature data",
                        caption: countCaption(
                            noData.count,
                            ending: "with no temperature"
                        )
                    )
                }
            }
        }
    }

    private var calmBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(hex: "#2E7D5B"))
                .accessibilityHidden(true)

            Text("No temperature alerts")
                .font(.subheadline)
                .fontWeight(.semibold)
                .opacity(0.8)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(height: 55)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(hex: "#2E7D5B").opacity(0.1),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    /// Names one nest rather than a count alone: "3 nests" tells a ranger there
    /// is a problem, "B1 - Nest #04 - 34.0" tells them where to walk.
    /// "There is 1 nest ..." / "There are 3 nests ...", so the whole sentence
    /// agrees rather than only the noun.
    private func countCaption(_ count: Int, ending: String) -> String {
        let subject = count == 1 ? "is 1 nest" : "are \(count) nests"
        return "There \(subject) \(ending)"
    }

    private func alertBar(
        tint: Color,
        title: String,
        caption: String
    ) -> some View {
        Button {
            openNestList(filter: .all, style: .listOnly)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.black.opacity(0.8))

                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#757575"))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Text("View list")
                        .font(.footnote)
                        .fontWeight(.semibold)

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color(hex: "#0C7C4D"))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 24))
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
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
            
            // Drawn whatever the selection: with no section chosen the row
            // opens the hatchery-wide list, so there is always somewhere to go.
            // The words carry the affordance -- a lone chevron on a row of
            // plain text did not read as a destination.
            HStack(spacing: 4) {
                Text("View list")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Image(systemName: "chevron.right")
                    .font(.body)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color(hex: "#0C7C4D"))
            .frame(height: 44, alignment: .trailing)
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
    
    /// Unselected badges sit back into the photo; the selected one comes
    /// forward to solid white. Every cell carries one now, so at full opacity
    /// the grid read as a sheet of white dots with nothing to choose between.
    private func nestCountBadge(count: Int, isSelected: Bool, diameter: CGFloat) -> some View {
        Text("\(count)")
            .font(.system(size: max(9, diameter * 0.42), weight: .bold))
            .foregroundStyle(.black.opacity(isSelected ? 1 : 0.6))
            .minimumScaleFactor(0.5)
            .frame(width: diameter, height: diameter)
            .background(Color.white.opacity(isSelected ? 1 : 0.4), in: Circle())
            .padding(diameter * 0.1)
            .background(Color.white.opacity(isSelected ? 0.24 : 0), in: Circle())
            .accessibilityHidden(true)
    }
    
    /// First visit to a hatchery, the grid is masked until it is tapped once.
    /// The tap only lifts the mask -- deliberately not also selecting the cell
    /// underneath, so the prompt teaches the gesture instead of spending it.
    ///
    // ponytail: UserDefaults, not a profile column -- a coach mark is per
    // device, and syncing it costs a column and a round trip for a one-off hint.
    
    private func coachMask(size : CGSize) -> some View {
        Button {UserDefaults.standard.set(true, forKey: coachMaskKey)
            coachDismissed.insert(hatchery.hatchery.id)
        } label : {
            ZStack {
                Color.black.opacity(0.55)
                
                VStack (spacing : 8)
                {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 28))
                    Text("Tap a section")
                        .font(.headline)
                }
                .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Tap a section to see its nests")
        .accessibilityHint("Hides this prompt")
    }
    private func temperatureText(_ temperature: Double?) -> String {
        guard let temperature else { return "—" }
        return String(format: "%.1f", temperature)
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
    // Short labels deliberately: five segments share 371pt, and the full
    // words truncate to ellipses at that width.
    case hatchingSoon = "Soon"
    case inspection = "Inspect"
    
    var id: String { rawValue }
    
    func matches(_ nest: NestEntity) -> Bool {
        switch self {
        case .all: true
        case .hatched: nest.hasHatched
        case .unhatched: !nest.hasHatched
        case .hatchingSoon: nest.isHatchingSoon
        case .inspection: nest.isDueForInspection()
        }
    }
    
    var emptyMessage: String {
        switch self {
        case .all: "No nests here"
        case .hatched: "No hatched nests here"
        case .unhatched: "No nests still incubating here"
        case .hatchingSoon: "No nests hatching in the next 3 days"
        case .inspection: "No nests due for inspection"
        }
    }
}

/// What the nest list is showing: one section, or the whole hatchery.
///
/// Both open the same sheet. The list is built from `sections` rather than a
/// flat nest array so ordinals stay section-relative -- a nest keeps the number
/// it has in its own section however the list was opened.
private struct NestListScope: Identifiable, Hashable {
    /// How the sheet should draw this scope. Carried here rather than in a
    /// sibling `@State` so the `.sheet` closure cannot read a stale one.
    var style: SectionOverviewSheet.Style = .full
    /// Nil for the whole hatchery.
    let sectionID: String?
    let title: String
    let averageTemperatureC: Double?
    let nestCount: Int
    let totalEggs: Int
    let sections: [HatcherySectionDashboard]
    
    /// The style is part of the identity. Without it, reopening the same
    /// scope in the other style hands `.sheet(item:)` an unchanged id and it
    /// keeps the sheet it already has.
    var id: String {
        let scope = sectionID ?? "hatchery"
        return style == .full ? scope : "\(scope)-list"
    }

    /// The same scope, drawn the given way.
    func presented(as style: SectionOverviewSheet.Style) -> NestListScope {
        var copy = self
        copy.style = style
        return copy
    }
    
    init(section: HatcherySectionDashboard) {
        sectionID = section.id
        title = "Section \(section.id)"
        averageTemperatureC = section.averageTemperatureC
        nestCount = section.nestCount
        totalEggs = section.totalEggs
        sections = [section]
    }
    
    init(dashboard: HatcheryDashboard) {
        sectionID = nil
        title = dashboard.hatchery.name
        averageTemperatureC = dashboard.overview.averageTemperatureC
        nestCount = dashboard.overview.nestCount
        totalEggs = dashboard.overview.totalEggs
        sections = dashboard.sections
    }
}

private struct SectionOverviewSheet: View {
    /// How much of the sheet is drawn, and what a row shows on its right.
    ///
    /// `.listOnly` is what the two temperature alerts open. Arriving from a
    /// warning, the summary restates numbers the warning already made the
    /// point of, and the filter is not the axis you came to browse -- so the
    /// list gets that space, and rows carry the nest's section, because an
    /// alert spans every section and the section is where to walk.
    ///
    /// Everything else opens `.full`: you chose a scope deliberately, so the
    /// summary describes it and the filter narrows it.
    var style: SectionOverviewSheet.Style = .full

    enum Style {
        case full
        case listOnly
    }

    let scope: NestListScope
    /// Owned by the host so a card can open this sheet already filtered. Held
    /// as `@State` here, the initial value would have to be assigned after the
    /// first render, and the list would flash unfiltered on the way in.
    @Binding var filter: NestHatchFilter
    let container: AppContainer
    let hatcheryName: String
    let onNestDeleted: () async -> Void
    let onNestChanged: () async -> Void
    let onReturnToHatchery: () -> Void
    @State private var selectedNest: NestDetailSelection?
    
    /// Ordinals are assigned before filtering, never after, and always within
    /// the nest's own section.
    ///
    /// Numbering a filtered array renumbers every nest in it, so the same nest
    /// would answer to a different number depending on which filter happened to
    /// be selected -- the exact failure `NestEntity.displayNumber` exists to
    /// prevent. Numbering the flattened hatchery list would do the same thing
    /// across sections. Position in the unfiltered section is the identity.
    private var rows: [(sectionID: String, ordinal: Int, item: NestDashboardItem)] {
        scope.sections.flatMap { section in
            section.nests.enumerated().map {
                (sectionID: section.id, ordinal: $0.offset + 1, item: $0.element)
            }
        }
        .filter { filter.matches($0.item.nest) }
    }
    
    var body: some View {
        // Nothing on this sheet is editable -- the nests are opened, not
        // changed here -- so the chrome's pencil is turned off.
        SheetChrome(title: scope.title, showsEditButton: false) { sheetWidth in
            if style == .full {
                summary
                    .frame(width: 370, height: 85, alignment: .top)
                    .offset(x: (sheetWidth - 370) / 2, y: 71)

                filterPicker
                    .frame(width: 371)
                    .offset(x: ceil((sheetWidth - 371) / 2), y: 167)
            }

            nestList
                .offset(
                    x: ceil((sheetWidth - 371) / 2),
                    y: style == .full ? 207 : 71
                )
        }
        .sheet(item: $selectedNest) { selection in
            NestDetailSheet(
                item: selection.item,
                ordinal: selection.ordinal,
                // From the row, not the sheet: a hatchery-wide list spans every
                // section, so the sheet has no single label to hand over.
                sectionLabel: selection.sectionID,
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
                value: temperatureText(scope.averageTemperatureC),
                unit: "°C",
                valueColor: Color(hex: "#0C7C4D"),
                alignment: .leading
            )
            .frame(width: 151, height: 85, alignment: .topLeading)
            
            sheetSummaryValue(title: "Nests", value: String(scope.nestCount))
                .frame(width: 97.5, height: 85, alignment: .top)
            
            sheetSummaryValue(title: "Eggs", value: groupedNumber(scope.totalEggs))
                .frame(width: 97.5, height: 85, alignment: .top)
        }
        .frame(width: 370, height: 85, alignment: .top)
    }

    private var filterPicker: some View {
        Picker("Show", selection: $filter) {
            ForEach(NestHatchFilter.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
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
                            selectedNest = NestDetailSelection(
                                item: row.item,
                                ordinal: row.ordinal,
                                sectionID: row.sectionID
                            )
                        } label: {
                            nestRow(row.item, ordinal: row.ordinal, sectionID: row.sectionID)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        // Four or fewer nests fill the list exactly, so leave those sections
        // feeling fixed rather than springy.
        .scrollBounceBehavior(.basedOnSize)
        // `.listOnly` starts where the summary would have, so it reclaims the
        // 136pt the summary and the filter picker occupy in `.full`.
        .frame(width: 371, height: style == .full ? 468 : 604)
    }
    
    
    private func nestRow(
        _ item: NestDashboardItem,
        ordinal: Int,
        sectionID: String
    ) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("Nest #\(item.nest.displayNumber(fallbackOrdinal: ordinal))")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "#2B2B2B"))
                
                Spacer(minLength: 0)
                
                if style == .listOnly {
                    // What the battery pill occupies in the full sheet. An
                    // alert list spans every section, so the section is what
                    // tells a ranger where to walk -- a charge percentage does
                    // not.
                    Text(sectionID)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "#0C7C4D"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Color(hex: "#0C7C4D").opacity(0.1),
                            in: Capsule()
                        )

                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color(hex: "#8E8E93"))
                        .accessibilityHidden(true)
                } else {
                    // A logger with no battery reading needs servicing rather
                    // than opening, so Figma swaps the chevron for a wrench.
                    Image(systemName: item.batteryLevel == nil
                          ? "wrench.and.screwdriver"
                          : "chevron.right")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color(hex: "#8E8E93"))
                        .accessibilityHidden(true)
                }
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
        let sectionID: String
        
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
