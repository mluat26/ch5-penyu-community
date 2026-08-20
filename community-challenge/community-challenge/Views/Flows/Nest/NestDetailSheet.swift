import SwiftUI

/// Figma 199:3729 (read) and 199:3595 (edit). One screen in two states, not
/// two destinations.
///
/// Laid out against Figma's 390pt sheet frame by coordinate, taken from node
/// geometry rather than a screenshot — the row heights (68 tall / 52 regular),
/// section header (28pt title + 20pt subtitle), and chart bar pitch all come
/// from there.
struct NestDetailSheet: View {
    let item: NestDashboardItem
    let ordinal: Int
    let sectionLabel: String
    @Bindable var controller: NestDetailController
    /// Just the one thing this sheet needs from the composition root, rather
    /// than the root itself: the measurement harness has no AppContainer and
    /// should not have to build a Supabase client to lay out a sheet.
    let makeHatchingController: (NestEntity) -> HatchingController
    let hatcheryName: String
    let onClose: () -> Void
    let onDelete: () -> Void

    enum Layout {
        static let sheetWidth: CGFloat = 390
        /// 801pt of visible sheet less the 34pt bottom safe area iOS adds.
        static let detentHeight: CGFloat = 767
        /// The "Tall" Row variant, which every section but the read-mode
        /// inspection list uses.
        static let rowHeight: CGFloat = 68
        /// The "Regular" Row variant — Figma 199:3855, read mode only.
        static let compactRowHeight: CGFloat = 52
        static let sectionInset: CGFloat = 16
        static let sectionWidth: CGFloat = 358
    }

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var isConfirmingDelete = false
    /// Figma 199:3729 (read) vs 199:3595 (edit). The frames differ in more
    /// than styling: editing turns every detail value into a date-picker pill,
    /// grows the inspection rows to the tall variant, and is the only place
    /// Delete nest appears.
    @State private var isEditing = false
    /// Holds the nest after a save so the rows show the new values without
    /// refetching the section behind this sheet.
    @State private var editedNest: NestEntity?
    /// Every full-screen destination this sheet owns, in one enum.
    ///
    /// SwiftUI honours a single `.fullScreenCover` per view -- a second
    /// modifier silently loses -- so the map and the hatchling flow have to
    /// share one, the same way ContentView funnels its sheets through
    /// `HomeSheet`.
    private enum Cover: Identifiable {
        case locationMap
        /// Carries the controller rather than leaving the builder to read it
        /// out of `@State`.
        ///
        /// It used to be an `if let` over a separate `@State` property, set in
        /// the same button action that set this one. The cover's content
        /// closure captures the view before that second write lands, so it read
        /// nil, the ViewBuilder produced an EmptyView, and the flow presented
        /// as a blank white screen. A presented value that carries its own
        /// dependency cannot get out of step with it.
        case hatchFlow(HatchedFlowView.Step, HatchingController)

        var id: String {
            switch self {
            case .locationMap: "locationMap"
            case let .hatchFlow(step, _): "hatchFlow-\(step)"
            }
        }
    }

    @State private var presentedCover: Cover?
    /// Built on demand: it needs the nest, and a nest that is never hatched
    /// should never pay for one.
    @State private var hatchingController: HatchingController?

    private var nest: NestEntity { editedNest ?? item.nest }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, geometry.size.width / Layout.sheetWidth)

            ZStack(alignment: .topLeading) {
                Color(uiColor: .systemGroupedBackground)

                ScrollView {
                    content(scale: scale)
                        .frame(width: Layout.sheetWidth * scale, alignment: .topLeading)
                        // Clears the floating Hatched bar, which both modes
                        // now show.
                        .padding(.bottom, 96 * scale)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .top, spacing: 0) {
                    toolbar(scale: scale)
                        .padding(.top, 16 * scale)
                        .background(Color(uiColor: .systemGroupedBackground))
                }

                // Shown in both modes. It was read-only while it did nothing;
                // now it is the only way into the hatchling flow, and hiding it
                // behind edit mode would make a recorded hatch unreachable for
                // anyone who happened to be editing.
                hatchedBar(scale: scale)
                    .frame(width: geometry.size.width, alignment: .center)
                    .offset(y: geometry.size.height - 96 * scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .task {
            await controller.load()
            await controller.loadDataLogger(founderID: nest.founderID)
        }
        // One cover for both modes: reading opens the same map locked down to
        // a preview, editing opens it as the picker the add-nest flow uses.
        // Presenting from inside this sheet is the pattern already in use, so
        // nothing has to wait on another screen's dismissal.
        .fullScreenCover(item: $presentedCover) { cover in
            switch cover {
            case .locationMap:
                NestLocationPickerView(
                    initialLatitude: isEditing ? controller.draftLatitude : nest.latitude,
                    initialLongitude: isEditing ? controller.draftLongitude : nest.longitude,
                    initialAddress: isEditing
                        ? (controller.draftLocation.isEmpty ? nil : controller.draftLocation)
                        : nest.locationAddress,
                    isReadOnly: !isEditing,
                    onCancel: { presentedCover = nil },
                    onSave: { latitude, longitude, address in
                        controller.draftLatitude = latitude
                        controller.draftLongitude = longitude
                        controller.draftLocation = address ?? ""
                        presentedCover = nil
                    }
                )

            case let .hatchFlow(step, flowController):
                HatchedFlowView(
                    controller: flowController,
                    detailController: controller,
                    ordinal: ordinal,
                    sectionLabel: sectionLabel,
                    hatcheryName: hatcheryName,
                    startAt: step,
                    onClose: { presentedCover = nil },
                    onFinish: {
                        presentedCover = nil
                        // The sheet cannot be dismissed while its own cover is
                        // still on screen, so the close waits a tick for the
                        // cover to come down.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            onClose()
                        }
                    }
                )
            }
        }
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

    // MARK: - Toolbar (166:3251 — 44pt buttons at x16 / x330, title x177/y13)

    private func toolbar(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17 * scale, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44 * scale, height: 44 * scale)
                    .background(Color(hex: "#E9E9EB"), in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 16 * scale)
            .accessibilityLabel("Close")

            // Centred full-width rather than pinned to Figma's text-node
            // width, which truncates a longer nest number.
            Text("Nest-\(nest.displayNumber(fallbackOrdinal: ordinal))")
                .font(.system(size: 17 * scale, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: Layout.sheetWidth * scale, height: 22 * scale)
                .offset(y: 13 * scale)

            Button {
                if isEditing {
                    Task {
                        if let saved = await controller.save(nest) {
                            editedNest = saved
                            isEditing = false
                        }
                    }
                } else {
                    controller.beginEditing(nest)
                    isEditing = true
                }
            } label: {
                // Only the edit-mode confirm is the prominent button variant
                // (199:3599); the pencil matches the close button (199:3733).
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .font(.system(size: 17 * scale, weight: .semibold))
                    .foregroundStyle(isEditing ? .white : .black)
                    .frame(width: 44 * scale, height: 44 * scale)
                    .background(
                        isEditing ? Color.accentColor : Color(hex: "#E9E9EB"),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(controller.isSaving)
            .offset(x: 330 * scale)
            .accessibilityLabel(isEditing ? "Save nest" : "Edit nest")
        }
        .frame(width: Layout.sheetWidth * scale, height: 54 * scale, alignment: .topLeading)
    }

    // MARK: - Content (199:3737 / 199:3603 — sections at fixed y offsets)

    /// Both frames put every section at the same y; only the tail differs, so
    /// the read frame is 1573 tall (199:3737) and the edit frame 1707 with the
    /// taller inspection rows and the Delete nest button (199:3603).
    private func content(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            heroAndStats(scale: scale)
                .offset(x: 16 * scale)

            weekAndChart(scale: scale)
                .offset(x: 10 * scale, y: 273.09 * scale)

            informationSection(scale: scale)
                .offset(x: 16 * scale, y: 619.09 * scale)

            timelineSection(scale: scale)
                .offset(x: 16 * scale, y: 983.09 * scale)

            inspectionSection(scale: scale)
                .offset(x: 16 * scale, y: 1321.09 * scale)

            if isEditing {
                deleteButton(scale: scale)
                    .offset(x: 16 * scale, y: 1617.09 * scale)
            }
        }
        .frame(
            width: Layout.sheetWidth * scale,
            height: (isEditing ? 1707 : 1573) * scale,
            alignment: .topLeading
        )
    }

    /// 199:3738 — image 294 × 164 centred at x32, then a 85pt stat row.
    private func heroAndStats(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("NestImage")
                .resizable()
                .scaledToFill()
                .frame(width: 294 * scale, height: 164.09 * scale)
                .clipped()
                .offset(x: 32 * scale)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                statColumn(
                    title: "Average temperature",
                    value: temperatureText,
                    unit: "°C",
                    tint: Color(hex: "#0C7C4D"),
                    weight: .bold,
                    width: 157,
                    scale: scale
                )
                Spacer(minLength: 0)
                statColumn(
                    title: "Eggs",
                    value: "\(nest.numberOfEggs)",
                    unit: nil,
                    tint: .black,
                    weight: .semibold,
                    width: 88.5,
                    scale: scale
                )
                Spacer(minLength: 0)
                statColumn(
                    title: "Sections",
                    value: sectionLabel,
                    unit: nil,
                    tint: .black,
                    weight: .semibold,
                    width: 88.5,
                    scale: scale
                )
            }
            .frame(width: Layout.sectionWidth * scale, height: 85 * scale)
            .background(.white, in: RoundedRectangle(cornerRadius: 26 * scale))
            .offset(y: 164.09 * scale)
        }
        .frame(width: Layout.sectionWidth * scale, height: 249.09 * scale, alignment: .topLeading)
    }

    private var temperatureText: String {
        let value = controller.latestTemperatureC ?? item.latestTemperatureC
        return value.map { String(format: "%.1f", $0) } ?? "--"
    }

    /// Label at y16 (16pt tall), value at y44 (25pt tall) — 199:3742 / 199:3744.
    /// The temperature is Bold; Eggs and Sections are Semibold (199:3750).
    private func statColumn(
        title: String,
        value: String,
        unit: String?,
        tint: Color,
        weight: Font.Weight,
        width: CGFloat,
        scale: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Text(title)
                .font(.system(size: 12 * scale, weight: .regular))
                .foregroundStyle(Color(hex: "#8E8E93").opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(width: (width - 32) * scale, height: 16 * scale)
                .offset(x: 16 * scale, y: 16 * scale)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value)
                    .font(.system(size: 20 * scale, weight: weight))
                if let unit {
                    Text(unit)
                        .font(.system(size: 12 * scale, weight: weight))
                }
            }
            .foregroundStyle(tint)
            .frame(width: (width - 32) * scale, height: 25 * scale)
            .offset(x: 16 * scale, y: 44 * scale)
        }
        .frame(width: width * scale, height: 85 * scale, alignment: .topLeading)
    }

    // MARK: - Week strip + chart (166:3270)

    /// Seven days ending today, so the strip always includes the present
    /// rather than running into dates with no readings.
    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private func weekAndChart(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            weekStrip(scale: scale)

            temperatureNow(scale: scale)
                .offset(y: 64 * scale)

            chart(scale: scale)
                .offset(y: 121 * scale)

            hourAxis(scale: scale)
                .offset(y: 306 * scale)
        }
        .frame(width: 370 * scale, height: 322 * scale, alignment: .topLeading)
    }

    /// Two pitches, not one: the 38pt weekday labels sit 54.333pt apart
    /// (199:3760) while the 30pt day circles sit 55.667pt apart (199:3768),
    /// because each row spreads its own item width across the same 364pt.
    private func weekStrip(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)

                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .frame(width: 38 * scale, height: 18 * scale)
                    .offset(x: 54.333_333 * CGFloat(index) * scale, y: 1 * scale)

                Button {
                    selectedDay = day
                } label: {
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 17 * scale, weight: .regular))
                        .foregroundStyle(isSelected ? Color(hex: "#F2F2F7") : .black)
                        .frame(width: 30 * scale, height: 30 * scale)
                        .background {
                            if isSelected { Circle().fill(Color(hex: "#999999")) }
                        }
                }
                .buttonStyle(.plain)
                .offset(x: 55.666_664 * CGFloat(index) * scale, y: 27 * scale)
            }
        }
        .frame(width: 364 * scale, height: 64 * scale, alignment: .topLeading)
    }

    private func temperatureNow(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text("Temperature now")
                .font(.system(size: 12 * scale, weight: .regular))
                .foregroundStyle(Color(hex: "#8E8E93").opacity(0.8))
                .frame(width: 348 * scale, height: 16 * scale, alignment: .leading)
                .offset(x: 8 * scale)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(NestTemperature.text(controller.latestTemperatureC))
                    .font(.system(size: 20 * scale, weight: .bold))
                Text("°C")
                    .font(.system(size: 12 * scale, weight: .bold))
            }
            .foregroundStyle(Color(hex: "#D9538E"))
            .frame(height: 25 * scale, alignment: .leading)
            .offset(x: 8 * scale, y: 20 * scale)
        }
        .frame(width: 364 * scale, height: 45 * scale, alignment: .topLeading)
    }

    /// 199:3788 — 24 bars 8.458pt wide on a 14.458pt pitch, 173pt tall, with
    /// the 18–33° axis column at x349.
    private func chart(scale: CGFloat) -> some View {
        let readings = controller.readings(on: selectedDay)

        return ZStack(alignment: .topLeading) {
            NestTemperatureChart(readings: readings, scale: scale)
                .frame(width: 341 * scale, height: 173 * scale, alignment: .bottomLeading)

            // 199:3814 — 12pt bold on a 21pt × 152pt column at x349, evenly
            // spaced. `fixedSize` keeps the degree sign from clipping.
            VStack(spacing: 0) {
                ForEach([33, 30, 27, 24, 21, 18], id: \.self) { degrees in
                    Text("\(degrees)°")
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(Color(hex: "#8E8E93"))
                        .fixedSize()
                        .frame(height: 16 * scale)

                    if degrees != 18 { Spacer(minLength: 0) }
                }
            }
            .frame(width: 21 * scale, height: 152 * scale)
            .offset(x: 349 * scale)
        }
        .frame(width: 370 * scale, height: 173 * scale, alignment: .topLeading)
    }

    /// 199:3821 — 12pt bold. The design carries a fifth label at x326 but
    /// leaves it at zero opacity, so the axis stops at 18.
    private func hourAxis(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([(0.0, "0"), (78.75, "6"), (157.5, "12"), (241.25, "18")], id: \.0) { x, label in
                Text(label)
                    .font(.system(size: 12 * scale, weight: .bold))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .frame(height: 16 * scale)
                    .offset(x: x * scale)
            }
        }
        .frame(width: 341 * scale, height: 16 * scale, alignment: .topLeading)
    }

    // MARK: - Grouped sections (199:3827 / 3836 / 3850)

    private func informationSection(scale: CGFloat) -> some View {
        detailSection(title: "Information", subtitle: "Nest detail information", scale: scale) {
            infoRow(title: "Bucket ID", value: nest.bucketID ?? "—", scale: scale)
            rowSeparator(scale: scale)
            // Shown in both modes: it is read-only either way, and who logged
            // the nest is reference information worth having while reading the
            // record, not only while changing it.
            infoRow(
                title: "Data logger",
                value: controller.dataLoggerName ?? "—",
                scale: scale
            )
            rowSeparator(scale: scale)
            dateRow(
                title: "Collection date",
                stored: nest.dateEggsLaid,
                draft: $controller.draftCollectionDate,
                scale: scale
            )
            rowSeparator(scale: scale)
            locationRow(scale: scale)
        }
    }

    private func timelineSection(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Timeline", subtitle: "Hatching timeline", scale: scale)

            HStack(spacing: 10 * scale) {
                timelineStat(title: "Duration", value: durationText, scale: scale)
                timelineStat(title: "Prediction", value: predictionText, scale: scale)
            }
            .frame(width: Layout.sectionWidth * scale, height: 94 * scale)
            .padding(.top, 16 * scale)

            VStack(spacing: 0) {
                dateRow(
                    title: "Inspection date",
                    stored: nest.nextInspectionDate,
                    draft: $controller.draftInspectionDate,
                    scale: scale
                )
                rowSeparator(scale: scale)
                dateRow(
                    title: "Prediction",
                    subtitle: "Hatching date",
                    stored: nest.datePredictedHatch,
                    draft: $controller.draftPredictedHatch,
                    scale: scale
                )
            }
            .frame(width: Layout.sectionWidth * scale)
            .background(.white, in: RoundedRectangle(cornerRadius: 26 * scale))
            .padding(.top, 16 * scale)
        }
        .frame(width: Layout.sectionWidth * scale, alignment: .topLeading)
    }

    /// The one section whose rows change height between the frames: 52pt
    /// plain rows while reading (199:3855), 68pt while editing (199:3721).
    private func inspectionSection(scale: CGFloat) -> some View {
        let height = isEditing ? Layout.rowHeight : Layout.compactRowHeight

        return detailSection(title: "Inspection list", subtitle: "Hatching timeline", scale: scale) {
            if controller.inspections.isEmpty {
                Text("No inspections recorded yet")
                    .font(.system(size: 15 * scale, weight: .regular))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .frame(width: Layout.sectionWidth * scale, height: height * scale, alignment: .leading)
                    .padding(.leading, 16 * scale)
            } else {
                ForEach(Array(controller.inspections.enumerated()), id: \.element.id) { index, inspection in
                    if index > 0 { rowSeparator(scale: scale) }

                    infoRow(
                        title: "#\(index + 1)",
                        value: formatted(inspection.inspectedOn),
                        isBadge: isEditing,
                        height: height,
                        scale: scale
                    )
                }
            }
        }
    }

    /// 199:3725 — a 358 × 55 button, corner 26, Accents/Red.
    private func deleteButton(scale: CGFloat) -> some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            Text("Delete nest")
                .font(.system(size: 17 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Layout.sectionWidth * scale, height: 55 * scale)
                .background(Color(hex: "#FF383C"), in: RoundedRectangle(cornerRadius: 26 * scale))
        }
        .buttonStyle(.plain)
    }

    /// The floating action, full width like the other section cards.
    ///
    /// One button, two jobs, because a nest has only one final tally: before
    /// there is one it records the hatch, afterwards it opens the report. The
    /// database refuses a second tally outright, so offering "Hatched" again
    /// would be offering something that cannot happen.
    private func hatchedBar(scale: CGFloat) -> some View {
        Button {
            // Reused across openings so a half-filled form survives closing the
            // flow, but passed along explicitly so the cover never has to look
            // it up.
            let flowController = hatchingController ?? makeHatchingController(nest)
            hatchingController = flowController
            presentedCover = .hatchFlow(
                controller.hatching == nil ? .details : .report,
                flowController
            )
        } label: {
            Text(controller.hatching == nil ? "Hatched" : "View report")
                .font(.system(size: 17 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Layout.sectionWidth * scale, height: 55 * scale)
                .background(Color.appGreenPrimary, in: RoundedRectangle(cornerRadius: 26 * scale))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Building blocks

    /// The Row component's Separator (I199:3832;5534:22504): a 1pt hairline
    /// inset 16pt at both ends. Figma puts one at the top of every row; the
    /// first would land on the card's own edge, so it is drawn between rows.
    private func rowSeparator(scale: CGFloat) -> some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(width: (Layout.sectionWidth - 32) * scale, height: 1)
            .frame(width: Layout.sectionWidth * scale)
    }

    private func detailSection<Content: View>(
        title: String,
        subtitle: String,
        scale: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: title, subtitle: subtitle, scale: scale)

            VStack(spacing: 0) { content() }
                .frame(width: Layout.sectionWidth * scale)
                .background(.white, in: RoundedRectangle(cornerRadius: 26 * scale))
                .padding(.top, 16 * scale)
        }
        .frame(width: Layout.sectionWidth * scale, alignment: .topLeading)
    }

    /// 199:3828 — 28pt title with a 20pt subtitle 32pt below its top.
    private func sectionHeader(title: String, subtitle: String, scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text(title)
                .font(.system(size: 22 * scale, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: Layout.sectionWidth * scale, height: 28 * scale, alignment: .leading)

            Text(subtitle)
                .font(.system(size: 15 * scale, weight: .regular))
                .foregroundStyle(.black.opacity(0.5))
                .frame(width: Layout.sectionWidth * scale, height: 20 * scale, alignment: .leading)
                .offset(y: 32 * scale)
        }
        .frame(width: Layout.sectionWidth * scale, height: 52 * scale, alignment: .topLeading)
    }

    private func infoRow(
        title: String,
        subtitle: String? = nil,
        value: String,
        isBadge: Bool = false,
        showsChevron: Bool = false,
        height: CGFloat = Layout.rowHeight,
        scale: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1 * scale) {
                Text(title)
                    .font(.system(size: 17 * scale, weight: .regular))
                    .foregroundStyle(.black)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12 * scale, weight: .regular))
                        .foregroundStyle(Color(hex: "#8E8E93"))
                }
            }

            Spacer(minLength: 12 * scale)

            Text(value)
                .font(.system(size: 15 * scale, weight: isBadge ? .semibold : .regular))
                .foregroundStyle(isBadge ? .black : Color(hex: "#8E8E93"))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, isBadge ? 12 * scale : 0)
                .padding(.vertical, isBadge ? 6 * scale : 0)
                .background {
                    if isBadge {
                        RoundedRectangle(cornerRadius: 10 * scale).fill(Color(hex: "#F1F1F1"))
                    }
                }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .padding(.leading, 8 * scale)
            }
        }
        .padding(.horizontal, 16 * scale)
        .frame(width: Layout.sectionWidth * scale, height: height * scale)
        .accessibilityElement(children: .combine)
    }

    /// Reads as plain detail text (199:3834 is a Default row) and edits as a
    /// wheel-free compact picker — the edit frame marks the same rows
    /// "Picker - Date" (199:3700), which is what `.compact` renders.
    private func dateRow(
        title: String,
        subtitle: String? = nil,
        stored: Date?,
        draft: Binding<Date>,
        scale: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1 * scale) {
                Text(title)
                    .font(.system(size: 17 * scale, weight: .regular))
                    .foregroundStyle(.black)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12 * scale, weight: .regular))
                        .foregroundStyle(Color(hex: "#8E8E93"))
                }
            }

            Spacer(minLength: 12 * scale)

            if isEditing {
                DatePicker("", selection: draft, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            } else {
                Text(stored.map(formatted) ?? "—")
                    .font(.system(size: 15 * scale, weight: .regular))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16 * scale)
        .frame(width: Layout.sectionWidth * scale, height: Layout.rowHeight * scale)
    }

    /// 199:3835 / 199:3701 draw this row identically in both frames: grey
    /// detail text and a drill-in chevron. Only the destination changes —
    /// editing opens the map picker, reading opens the same map as a preview.
    private func locationRow(scale: CGFloat) -> some View {
        let address = isEditing
            ? (controller.draftLocation.isEmpty ? "Set location" : controller.draftLocation)
            : (nest.locationAddress ?? "—")

        return Button {
            presentedCover = .locationMap
        } label: {
            HStack(spacing: 0) {
                Text("Location")
                    .font(.system(size: 17 * scale, weight: .regular))
                    .foregroundStyle(.black)

                Spacer(minLength: 12 * scale)

                Text(address)
                    .font(.system(size: 15 * scale, weight: .regular))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .padding(.leading, 8 * scale)
            }
            .padding(.horizontal, 16 * scale)
            .frame(width: Layout.sectionWidth * scale, height: Layout.rowHeight * scale)
        }
        .buttonStyle(.plain)
        // Nothing to preview when the nest was recorded without a pin.
        .disabled(!isEditing && (nest.latitude == nil || nest.longitude == nil))
    }

    /// 199:3841 — 174 × 94 card, label at y17, value at y43, on Gray 6 with a
    /// hairline border rather than the white the other cards use.
    private func timelineStat(title: String, value: String, scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text(title)
                .font(.system(size: 15 * scale, weight: .semibold))
                .foregroundStyle(Color(hex: "#2A2A2A"))
                .frame(width: 174 * scale, height: 20 * scale)
                .offset(y: 17 * scale)

            Text(value)
                .font(.system(size: 28 * scale, weight: .bold))
                .foregroundStyle(Color(hex: "#4A4A4A"))
                .frame(width: 174 * scale, height: 34 * scale)
                .offset(y: 43 * scale)
        }
        .frame(width: 174 * scale, height: 94 * scale, alignment: .topLeading)
        .background(Color(hex: "#F1F1F1"), in: RoundedRectangle(cornerRadius: 24 * scale))
        .overlay {
            RoundedRectangle(cornerRadius: 24 * scale)
                .strokeBorder(Color(hex: "#EBEBEB"), lineWidth: 1)
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
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
}

/// Figma 199:3789. The bars are not individually tinted: one continuous
/// gradient spans the whole plot and every bar samples it at its own height,
/// which is why a tall bar reaches purple while a short one stays green.
///
/// This is a heat map over the 18–33°C axis, deliberately distinct from the
/// discrete `NestTemperature.Band` colours used by the pills — the pills
/// answer "is this nest healthy", the chart shows the shape of the day.
struct NestTemperatureChart: View {
    let readings: [IoTDataEntity]
    let scale: CGFloat

    /// 199:3789 draws 24 bars — one per hour of the day.
    private static let barCount = 24
    private static let barWidth: CGFloat = 8.458_333
    private static let pitch: CGFloat = 14.458_333
    private static let fullHeight: CGFloat = 173
    private static let stubHeight: CGFloat = 7.75
    private static let axisRange: ClosedRange<Double> = 18...33

    /// Bottom to top, matching the axis labels 18° through 33°. The stops are
    /// 199:3799's fill (the one bar that spans the full plot) read upwards:
    /// purple 0%, red 13.553%, yellow 49.412%, green 100.68% top-down.
    private static let heatGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 50 / 255, green: 200 / 255, blue: 89 / 255), location: 0),
            .init(color: Color(red: 254 / 255, green: 201 / 255, blue: 1 / 255), location: 0.505_88),
            .init(color: Color(red: 246 / 255, green: 73 / 255, blue: 70 / 255), location: 0.864_47),
            .init(color: Color(red: 119 / 255, green: 62 / 255, blue: 141 / 255), location: 1),
        ],
        startPoint: .bottom,
        endPoint: .top
    )

    /// One slot per bar across the day, so a partial day leaves stubs at the
    /// end rather than stretching a few readings across the whole axis.
    private var slots: [Double?] {
        var buckets = [Double?](repeating: nil, count: Self.barCount)
        let calendar = Calendar.current

        for reading in readings {
            let temperature = reading.temperatureC
            let hour = calendar.component(.hour, from: reading.timestamp)
            let minute = calendar.component(.minute, from: reading.timestamp)
            let fraction = (Double(hour) + Double(minute) / 60) / 24
            let index = min(Self.barCount - 1, max(0, Int(fraction * Double(Self.barCount))))
            buckets[index] = temperature
        }
        return buckets
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // The infobook's acceptable band, behind the bars so a reading can
            // be read against the limits rather than guessed at.
            thresholdLine(at: NestTemperature.maximumAcceptableC)
            thresholdLine(at: NestTemperature.minimumAcceptableC)

            // Empty hours are flat grey stubs, drawn separately because they
            // must not take the heat gradient.
            barShapes(filled: false)
                .foregroundStyle(.black.opacity(0.1))

            // One gradient for the whole plot, revealed only where bars are.
            Self.heatGradient
                .frame(height: Self.fullHeight * scale)
                .mask(alignment: .bottomLeading) { barShapes(filled: true) }
        }
        .frame(height: Self.fullHeight * scale, alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Temperature through the day")
        .accessibilityValue(accessibilityValue)
    }

    private func barShapes(filled: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, temperature in
                if (temperature != nil) == filled {
                    Capsule()
                        .frame(width: Self.barWidth * scale, height: height(for: temperature) * scale)
                        .offset(x: Self.pitch * CGFloat(index) * scale)
                }
            }
        }
        .frame(height: Self.fullHeight * scale, alignment: .bottomLeading)
    }

    private func height(for temperature: Double?) -> CGFloat {
        guard let temperature else { return Self.stubHeight }
        let span = Self.axisRange.upperBound - Self.axisRange.lowerBound
        let fraction = min(max((temperature - Self.axisRange.lowerBound) / span, 0), 1)
        return max(Self.stubHeight, fraction * Self.fullHeight)
    }

    /// Positioned on the same 18–33°C axis the design labels.
    @ViewBuilder
    private func thresholdLine(at temperatureC: Double) -> some View {
        let span = Self.axisRange.upperBound - Self.axisRange.lowerBound
        let fraction = (temperatureC - Self.axisRange.lowerBound) / span

        if (0...1).contains(fraction) {
            Rectangle()
                .fill(.black.opacity(0.08))
                .frame(height: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: -fraction * Self.fullHeight * scale)
        }
    }

    private var accessibilityValue: String {
        let values = readings.map(\.temperatureC)
        guard let low = values.min(), let high = values.max() else { return "No readings" }
        return String(format: "From %.1f to %.1f degrees", low, high)
    }
}


