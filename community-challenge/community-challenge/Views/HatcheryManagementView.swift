import SwiftUI

/// Full-screen hatchery management for the backend-backed list of hatcheries.
/// It follows Figma nodes 94:1514 and 94:1614, while its cards intentionally
/// render live dashboard values instead of the static mock values in the file.
struct HatcheryManagementView: View {
    @Bindable var controller: HatcheryListController
    let activeHatcheryID: UUID?
    let onSelect: (HatcherySessionState) -> Void
    let onCreateNew: () -> Void
    let onRescan: (HatcheryEntity) -> Void
    let onRename: (HatcheryEntity) -> Void
    let onDismiss: () -> Void

    @State private var editingHatchery: HatcheryEntity?

    init(
        controller: HatcheryListController,
        activeHatcheryID: UUID? = nil,
        onSelect: @escaping (HatcherySessionState) -> Void,
        onCreateNew: @escaping () -> Void,
        onRescan: @escaping (HatcheryEntity) -> Void = { _ in },
        onRename: @escaping (HatcheryEntity) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self.activeHatcheryID = activeHatcheryID
        self.onSelect = onSelect
        self.onCreateNew = onCreateNew
        self.onRescan = onRescan
        self.onRename = onRename
        self.onDismiss = onDismiss
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, geometry.size.width / 402)
            let canvasWidth = 402 * scale
            let canvasX = geometry.size.width > canvasWidth
                ? (geometry.size.width - canvasWidth) / 2
                : 0

            ZStack(alignment: .topLeading) {
                managementBackdrop(scale: scale)

                managementCanvas(scale: scale)
                    .frame(width: canvasWidth, height: 874 * scale, alignment: .topLeading)
                    .clipped()
                    .offset(x: canvasX)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .task { await controller.loadManagement() }
        .sheet(item: $editingHatchery) { hatchery in
            HatcheryManagementEditorSheet(
                hatchery: hatchery,
                controller: controller,
                onRescan: onRescan,
                onRename: onRename
            )
            .presentationDetents([.height(713)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(34)
            .presentationSizing(.page)
        }
    }

    private func managementBackdrop(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.white

            Circle()
                .fill(Color(hex: "#FEF6ED"))
                .frame(width: 621 * scale, height: 621 * scale)
                .blur(radius: 50 * scale)
                .offset(x: -110 * scale, y: -378 * scale)
        }
        .allowsHitTesting(false)
    }

    private func managementCanvas(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("HatcheryManagementHero")
                .resizable()
                .scaledToFit()
                .frame(width: 284 * scale, height: 158 * scale)
                .offset(x: 195 * scale, y: 115 * scale)
                .accessibilityHidden(true)

            managementHeader(scale: scale)
                .offset(x: 16 * scale, y: 87 * scale)

            Text("Hatchery\nmanagement")
                .font(.system(size: 28 * scale, weight: .bold))
                .tracking(0.38 * scale)
                .foregroundStyle(.black)
                .frame(width: 188 * scale, height: 68 * scale, alignment: .leading)
                .offset(x: 16 * scale, y: 160 * scale)

            cards(scale: scale)
                .offset(x: 16 * scale, y: 259 * scale)

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(Color.appRed)
                    .multilineTextAlignment(.center)
                    .frame(width: 370 * scale)
                    .offset(x: 16 * scale, y: 748 * scale)
            }

            Button(action: onCreateNew) {
                Text("Add new hatchery")
                    .font(.system(size: 17 * scale, weight: .semibold))
                    .foregroundStyle(Color(hex: "#FAF8F4"))
                    .frame(width: 370 * scale, height: 55 * scale)
                    .background(Color.appGreenPrimary, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .offset(x: 16 * scale, y: 795 * scale)
            .accessibilityHint("Creates a new hatchery")

            managementMenuTapTarget(scale: scale)
        }
    }

    private func managementHeader(scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4 * scale) {
                Text("Management")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12 * scale, weight: .semibold))
            }
            .font(.system(size: 17 * scale, weight: .semibold))
            .foregroundStyle(Color(hex: "#0C7C4D"))
            .frame(width: 132 * scale, height: 44 * scale, alignment: .leading)
            .accessibilityHidden(true)

            Spacer(minLength: 0)

            HStack(spacing: 12 * scale) {
                toolbarIcon(systemName: "bell", label: "Notifications", scale: scale)
                toolbarIcon(systemName: "person", label: "Profile", scale: scale)
            }
            .frame(width: 156 * scale, height: 48 * scale)
        }
        .frame(width: 386 * scale, height: 48 * scale)
    }

    /// Figma's Popup Button stays visually in the header. Its touch target is
    /// a separate top-level SwiftUI Button so every part of “Management”
    /// responds reliably on physical devices.
    private func managementMenuTapTarget(scale: CGFloat) -> some View {
        Button(action: onDismiss) {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 176 * scale, height: 56 * scale)
        .contentShape(Rectangle())
        .offset(x: 16 * scale, y: 83 * scale)
        .accessibilityIdentifier("management-menu")
        .accessibilityLabel("Close management")
        .accessibilityHint("Returns to the hatchery overview")
    }

    private func toolbarIcon(
        systemName: String,
        label: String,
        scale: CGFloat
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20 * scale, weight: .regular))
            .foregroundStyle(.black)
            .frame(width: 48 * scale, height: 48 * scale)
            .glassEffect(.regular, in: .circle)
            .accessibilityLabel(label)
    }

    private func cards(scale: CGFloat) -> some View {
        let summaries = controller.managementSummaries.isEmpty
            ? controller.hatcheries.map {
                HatcheryManagementSummary(hatchery: $0, overview: nil)
            }
            : controller.managementSummaries

        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 11 * scale) {
                ForEach(summaries) { summary in
                    managementCard(summary, scale: scale)
                }
            }
            .padding(.bottom, 1)
        }
        .frame(width: 370 * scale, height: 458 * scale, alignment: .top)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func managementCard(
        _ summary: HatcheryManagementSummary,
        scale: CGFloat
    ) -> some View {
        let hatchery = summary.hatchery
        let isOpening = controller.openingHatcheryID == hatchery.id

        return VStack(spacing: 20 * scale) {
            HStack(spacing: 12 * scale) {
                Text(hatchery.name)
                    .font(.system(size: 17 * scale, weight: .semibold))
                    .tracking(-0.43 * scale)
                    .foregroundStyle(Color.appNeutralBlack)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button { editingHatchery = hatchery } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 17 * scale, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 32 * scale, height: 32 * scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(hatchery.name)")
            }
            .frame(height: 22 * scale)

            HStack(spacing: 12 * scale) {
                temperaturePill(summary.overview?.averageTemperatureC, scale: scale)
                dimensionPill(hatchery, scale: scale)

                Spacer(minLength: 0)

                HStack(alignment: .lastTextBaseline, spacing: 2 * scale) {
                    Text((summary.overview?.totalEggs ?? 0).formatted(.number.grouping(.never)))
                        .font(.system(size: 17 * scale, weight: .semibold))
                        .tracking(-0.43 * scale)
                        .foregroundStyle(.black)
                    Text("eggs")
                        .font(.system(size: 12 * scale, weight: .regular))
                        .foregroundStyle(Color(hex: "#8E8E93"))
                }
                .lineLimit(1)
            }
            .frame(height: 30 * scale)
        }
        .padding(16 * scale)
        .frame(width: 370 * scale, height: 106 * scale, alignment: .top)
        .background(.white, in: RoundedRectangle(cornerRadius: 24 * scale))
        .overlay {
            RoundedRectangle(cornerRadius: 24 * scale)
                .stroke(Color(hex: "#F2F2F7"), lineWidth: 1)
        }
        .overlay {
            if isOpening {
                RoundedRectangle(cornerRadius: 24 * scale)
                    .fill(.white.opacity(0.72))
                    .overlay {
                        ProgressView("Opening hatchery…")
                            .tint(Color.appGreenPrimary)
                            .foregroundStyle(Color.appGreenPrimary)
                    }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 24 * scale))
        .onTapGesture {
            // The active hatchery is already rendered behind this management
            // screen. Do not wait for its photo/layout to download again just
            // to return to the same session.
            guard hatchery.id != activeHatcheryID else {
                onDismiss()
                return
            }

            Task { @MainActor in
                guard let session = await controller.session(for: hatchery) else { return }
                onSelect(session)
            }
        }
        .disabled(controller.openingHatcheryID != nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            hatchery.id == activeHatcheryID
                ? "Current hatchery. Double tap to open it."
                : "Double tap to open this hatchery."
        )
    }

    private func temperaturePill(_ value: Double?, scale: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 13 * scale, weight: .semibold))
            Text(value.map { String(format: "%.1f°C", $0) } ?? "No data")
                .font(.system(size: 12 * scale, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(width: 86 * scale, height: 30 * scale)
        .background(Color(hex: "#34C759"), in: Capsule())
    }

    private func dimensionPill(
        _ hatchery: HatcheryEntity,
        scale: CGFloat
    ) -> some View {
        let isCircle = hatchery.shape == .circle
        let value: String = isCircle
            ? "R \(dimension(hatchery.widthM))m"
            : "\(dimension(hatchery.widthM)) x \(dimension(hatchery.lengthM)) m"

        return HStack(spacing: 6 * scale) {
            Image(systemName: isCircle ? "circle" : "rectangle")
                .font(.system(size: 13 * scale, weight: .regular))
            Text(value)
                .font(.system(size: 12 * scale, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.black)
        .frame(width: (isCircle ? 87 : 112) * scale, height: 30 * scale)
        .background(Color.black.opacity(0.04), in: Capsule())
    }

    private func dimension(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// The visual label for Figma's Popup Button at node 94:1374.
///
/// Interaction is intentionally attached to HomeView's header so the complete
/// selector area uses one stable touch route on both device and simulator.
struct HatcherySelectorLabel: View {
    let hatcheryName: String

    var body: some View {
        HStack(spacing: 4) {
            Text(hatcheryName)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Image(systemName: "chevron.up.chevron.down")
                .font(.title3)
        }
        .foregroundStyle(Color.appGreenPrimary)
        .frame(width: 148, height: 48, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// Figma node 94:1440 is a frosted 250 × 241pt menu. It intentionally uses
/// SwiftUI Buttons instead of a system popover: the design stays pixel-stable
/// and the presentation is owned by ContentView rather than a UIKit host view.
struct HatcheryQuickMenu: View {
    @Bindable var controller: HatcheryListController
    let activeHatchery: HatcheryEntity
    let onSelect: (HatcherySessionState) -> Void
    let onManagement: () -> Void
    let onCreateNew: () -> Void
    let onDismiss: () -> Void

    private let referenceCanvasWidth: CGFloat = 402
    private let menuWidth: CGFloat = 250
    private let menuHeight: CGFloat = 241

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = min(geometry.size.width, referenceCanvasWidth)
            let canvasOrigin = max((geometry.size.width - canvasWidth) / 2, 0)
            let availableMenuWidth = min(menuWidth, max(geometry.size.width - 30, 0))

            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                menu(width: availableMenuWidth)
                    .padding(.leading, canvasOrigin + 15)
                    .padding(.top, 82)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("hatchery-popup-menu")
    }

    private var displayedHatcheries: [HatcheryEntity] {
        let remainingHatcheries = controller.hatcheries.filter {
            $0.id != activeHatchery.id
        }
        return [activeHatchery] + remainingHatcheries
    }

    private var unavailableHatcheryNames: [String] {
        guard displayedHatcheries.count < 3 else { return [] }

        let existingNames = Set(
            displayedHatcheries.map {
                $0.name.replacingOccurrences(of: "_", with: " ")
            }
        )
        let availableNames: [String] = ["Hatch 02", "Hatch 03"]
            .filter { !existingNames.contains($0) }
        return Array(availableNames.prefix(3 - displayedHatcheries.count))
    }

    private func menu(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(displayedHatcheries) { hatchery in
                hatcheryRow(hatchery)
            }

            ForEach(unavailableHatcheryNames, id: \.self) { name in
                unavailableRow(name)
            }

            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 7)

            actionRow(
                title: "Management",
                systemImage: "list.bullet.below.rectangle"
            ) {
                onDismiss()
                onManagement()
            }

            actionRow(title: "Add hatchery", systemImage: "plus.circle") {
                onDismiss()
                onCreateNew()
            }
        }
        .padding(.vertical, 4)
        .frame(width: width, height: menuHeight)
        // Node 94:1440 uses Apple's "Liquid Glass Regular Medium" surface.
        // `glassEffect` owns the system border, blur, and shadow together;
        // combining it with a Material/hand-drawn border double-renders glass.
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .accessibilityElement(children: .contain)
    }

    private func hatcheryRow(_ hatchery: HatcheryEntity) -> some View {
        let isActive = hatchery.id == activeHatchery.id

        return Button {
            onDismiss()
            guard !isActive else { return }

            Task { @MainActor in
                guard let session = await controller.session(for: hatchery) else { return }
                onSelect(session)
            }
        } label: {
            HStack(spacing: 10) {
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 22, height: 22)
                }

                Text(hatchery.name)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(controller.openingHatcheryID != nil)
        .accessibilityIdentifier("hatchery-menu-row-\(hatchery.id.uuidString)")
    }

    private func unavailableRow(_ name: String) -> some View {
        Text(name)
            .font(.body)
            .foregroundStyle(.primary.opacity(0.25))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 20)
            .accessibilityLabel("\(name), unavailable")
    }

    private func actionRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .frame(width: 24, height: 24)

                Text(title)

                Spacer(minLength: 0)
            }
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 43, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The bottom sheet from Figma node 94:1614. Its default state is deliberately
/// sparse and pixel-matched; tapping the blue pencil reveals the backend-bound
/// rename controls without mixing an editing state into the reference frame.
private struct HatcheryManagementEditorSheet: View {
    let hatchery: HatcheryEntity
    let controller: HatcheryListController
    let onRescan: (HatcheryEntity) -> Void
    let onRename: (HatcheryEntity) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isRenaming = false
    @FocusState private var isNameFocused: Bool

    init(
        hatchery: HatcheryEntity,
        controller: HatcheryListController,
        onRescan: @escaping (HatcheryEntity) -> Void,
        onRename: @escaping (HatcheryEntity) -> Void
    ) {
        self.hatchery = hatchery
        self.controller = controller
        self.onRescan = onRescan
        self.onRename = onRename
        _name = State(initialValue: hatchery.name)
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = min(358, max(0, geometry.size.width - 44))

            ZStack(alignment: .top) {
                Color.white
                    .ignoresSafeArea()

                sheetHeader(contentWidth: contentWidth)
                    .padding(.top, 14)

                if isRenaming {
                    renameForm(contentWidth: contentWidth)
                        .padding(.top, 82)
                } else {
                    rescanAction(contentWidth: contentWidth)
                        .padding(.top, 80)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func sheetHeader(contentWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer(minLength: 0)

            Text(hatchery.name)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            Button {
                isRenaming.toggle()
                isNameFocused = isRenaming
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.blue, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRenaming ? "Cancel rename" : "Rename \(hatchery.name)")
        }
        .frame(width: contentWidth, height: 44)
    }

    private func rescanAction(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Re-scanning")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.appNeutralGray2)

            Button {
                dismiss()
                DispatchQueue.main.async {
                    onRescan(hatchery)
                }
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "move.3d")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(Color.appGreenPrimary)
                        .frame(width: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan your hatchery")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color.appNeutralGray2)
                        Text("Tap to rescan the area or adjust.")
                            .font(.system(size: 13, weight: .regular))
                            .tracking(-0.08)
                            .foregroundStyle(Color(hex: "#AEAEB2"))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color(hex: "#8E8E93"))
                }
                .padding(.horizontal, 24)
                .frame(width: contentWidth, height: 77)
                .background(Color(hex: "#E0E0E0").opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts a new scan for this hatchery")
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private func renameForm(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hatchery name")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.appNeutralGray2)

            TextField("Hatchery name", text: $name)
                .font(.system(size: 20, weight: .semibold))
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(Color(hex: "#F1F1F1"), in: RoundedRectangle(cornerRadius: 16))
                .focused($isNameFocused)

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appRed)
            }

            Button {
                Task {
                    guard let updated = await controller.update(
                        hatchery: hatchery,
                        name: name
                    ) else {
                        return
                    }
                    onRename(updated)
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if controller.updatingHatcheryID == hatchery.id {
                        ProgressView()
                            .tint(Color(hex: "#FAF8F4"))
                    }
                    Text(controller.updatingHatcheryID == hatchery.id ? "Saving…" : "Save")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "#FAF8F4"))
                .frame(width: contentWidth, height: 55)
                .background(Color.appGreenPrimary, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(
                name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || controller.updatingHatcheryID != nil
            )
        }
        .frame(width: contentWidth, alignment: .leading)
    }
}

#Preview("Management · Figma reference", traits: .fixedLayout(width: 402, height: 874)) {
    HatcheryManagementView(
        controller: AppContainer().makeHatcheryListController(),
        onSelect: { _ in },
        onCreateNew: {}
    )
}
