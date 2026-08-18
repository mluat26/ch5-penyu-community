import SwiftUI

/// Full-screen hatchery management for the backend-backed list of hatcheries.
/// It follows Figma node 129:1803 and its 122:3437/122:3333 detail states,
/// while cards intentionally render live dashboard values instead of the
/// static mock values in the file.
struct HatcheryManagementView: View {
    @Bindable var controller: HatcheryListController
    let onSelect: (HatcherySessionState) -> Void
    let onCreateNew: () -> Void
    let onRescan: (HatcheryEntity) -> Void
    let onRename: (HatcheryEntity) -> Void
    /// Drives the profile sheet this screen presents itself, so opening it
    /// does not have to bounce back through the dashboard first.
    var profileController: ProfileController?
    /// Profile actions that outlive this screen. Each one has to unwind the
    /// management cover before it can run, so they are handed upward rather
    /// than presented here: the invite screen is a full page, and signing out
    /// or deleting the account tears down the session this cover sits in.
    var onShowInvite: ((OrganizationInviteEntity) -> Void)?
    var onSignOut: (() -> Void)?
    var onDeleteAccount: (() async throws -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Both sheets share one modifier: SwiftUI keeps only the last `.sheet`
    /// attached to a view, so a second one would silently never present.
    @State private var presentedSheet: ManagementSheet?
    @State private var selectedHatcheryStartsEditing = false
    @State private var isShowingHatcheryMenu = false

    init(
        controller: HatcheryListController,
        onSelect: @escaping (HatcherySessionState) -> Void,
        onCreateNew: @escaping () -> Void,
        onRescan: @escaping (HatcheryEntity) -> Void = { _ in },
        onRename: @escaping (HatcheryEntity) -> Void = { _ in },
        profileController: ProfileController? = nil,
        onShowInvite: ((OrganizationInviteEntity) -> Void)? = nil,
        onSignOut: (() -> Void)? = nil,
        onDeleteAccount: (() async throws -> Void)? = nil
    ) {
        self.controller = controller
        self.onSelect = onSelect
        self.onCreateNew = onCreateNew
        self.onRescan = onRescan
        self.onRename = onRename
        self.profileController = profileController
        self.onShowInvite = onShowInvite
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
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

                if isShowingHatcheryMenu {
                    HatcheryQuickMenu(
                        controller: controller,
                        activeHatchery: nil,
                        selectedDestination: .management,
                        onSelect: onSelect,
                        onManagement: {},
                        onCreateNew: onCreateNew,
                        onDismiss: dismissHatcheryMenu
                    )
                    .transition(
                        .scale(scale: 0.94, anchor: .topLeading)
                            .combined(with: .opacity)
                    )
                    .zIndex(1)
                }
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
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .hatcheryDetail(let hatchery):
                HatcheryManagementDetailSheet(
                    hatchery: hatchery,
                    controller: controller,
                    onRescan: onRescan,
                    onRename: onRename,
                    startsEditing: selectedHatcheryStartsEditing
                )
                // SwiftUI adds the iPhone 17's 34pt bottom safe-area inset to a
                // fixed detent. 679pt of content therefore produces the Figma
                // reference's 713pt visible sheet.
                .presentationDetents([.height(679)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .presentationSizing(.page)

            case .profile(let profileController):
                ProfileSheetView(
                    controller: profileController,
                    onClose: { presentedSheet = nil },
                    onSignOut: {
                        presentedSheet = nil
                        onSignOut?()
                    },
                    onShowInvite: { invite in
                        presentedSheet = nil
                        onShowInvite?(invite)
                    },
                    onDeleteAccount: {
                        try await onDeleteAccount?()
                        presentedSheet = nil
                    }
                )
                .presentationDetents([.height(ProfileSheetView.Layout.detentHeight)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .presentationSizing(.page)
            }
        }
    }

    private func managementBackdrop(scale: CGFloat) -> some View {
        HatcheryWarmBackdrop(scale: scale)
    }

    private func managementCanvas(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("HatcheryManagementHero")
                .resizable()
                .scaledToFill()
                .frame(width: 284 * scale, height: 158 * scale)
                .clipped()
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

            HatcheryPrimaryButton(
                title: "Add new hatchery",
                scale: scale,
                action: onCreateNew
            )
            .frame(width: 370 * scale, height: 55 * scale)
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

            HatcheryToolbarAccessories(
                scale: scale,
                onProfile: profileController.map { controller in
                    { presentedSheet = .profile(controller) }
                }
            )
        }
        .frame(width: 386 * scale, height: 48 * scale)
    }

    /// Figma's Popup Button stays visually in the header. Its touch target is
    /// a separate top-level SwiftUI Button so every part of “Management”
    /// responds reliably on physical devices.
    private func managementMenuTapTarget(scale: CGFloat) -> some View {
        Button(action: presentHatcheryMenu) {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 176 * scale, height: 56 * scale)
        .contentShape(Rectangle())
        .offset(x: 16 * scale, y: 83 * scale)
        .accessibilityIdentifier("management-menu")
        .accessibilityLabel("Open hatchery menu")
        .accessibilityHint("Shows hatchery options")
    }

    private func presentHatcheryMenu() {
        setHatcheryMenuPresented(true)
    }

    private func dismissHatcheryMenu() {
        setHatcheryMenuPresented(false)
    }

    private func setHatcheryMenuPresented(_ isPresented: Bool) {
        withAnimation(menuAnimation) {
            isShowingHatcheryMenu = isPresented
        }
    }

    private var menuAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.12)
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

        return ZStack(alignment: .topTrailing) {
            Button { presentDetails(for: hatchery) } label: {
                VStack(spacing: 20 * scale) {
                    HStack(spacing: 12 * scale) {
                        Text(hatchery.name)
                            .font(.system(size: 17 * scale, weight: .semibold))
                            .tracking(-0.43 * scale)
                            .foregroundStyle(Color.appNeutralBlack)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Color.clear
                            .frame(width: 32 * scale, height: 32 * scale)
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
            }
            .buttonStyle(.plain)
            .disabled(controller.openingHatcheryID != nil)
            .accessibilityLabel("\(hatchery.name) details")
            .accessibilityHint("Shows hatchery details")

            Button { presentDetails(for: hatchery, startsEditing: true) } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 17 * scale, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44 * scale, height: 44 * scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(controller.openingHatcheryID != nil)
            .padding(.trailing, 10 * scale)
            .padding(.top, 5 * scale)
            .accessibilityLabel("Edit \(hatchery.name)")
        }
        .frame(width: 370 * scale, height: 106 * scale)
    }

    private func presentDetails(
        for hatchery: HatcheryEntity,
        startsEditing: Bool = false
    ) {
        selectedHatcheryStartsEditing = startsEditing
        presentedSheet = .hatcheryDetail(hatchery)
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

/// Figma node 94:1440 is a frosted 250 × 241pt menu. It intentionally uses
/// SwiftUI Buttons instead of a system popover: the design stays pixel-stable
/// and the presentation is owned by ContentView rather than a UIKit host view.
struct HatcheryQuickMenu: View {
    enum SelectedDestination: Equatable {
        case hatchery(UUID)
        case management
    }

    @Bindable var controller: HatcheryListController
    let activeHatchery: HatcheryEntity?
    let selectedDestination: SelectedDestination
    let onSelect: (HatcherySessionState) -> Void
    let onManagement: () -> Void
    let onCreateNew: () -> Void
    let onDismiss: () -> Void

    private let referenceCanvasWidth: CGFloat = 402
    private let menuWidth: CGFloat = 250
    /// The hatchery list grows as hatcheries are added, so the menu sizes to
    /// its content rather than to Figma's three-hatchery height. Past this cap
    /// the list scrolls, which keeps Management and Add hatchery reachable
    /// instead of pushing them off the bottom.
    private let maxHatcheryListHeight: CGFloat = 264
    @State private var hatcheryListHeight: CGFloat = 0

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
        guard let activeHatchery else { return controller.hatcheries }

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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(displayedHatcheries) { hatchery in
                        hatcheryRow(hatchery)
                    }

                    ForEach(unavailableHatcheryNames, id: \.self) { name in
                        unavailableRow(name)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    hatcheryListHeight = height
                }
            }
            // Sizes to the rows until they would overflow, then scrolls.
            .frame(height: min(max(hatcheryListHeight, 44), maxHatcheryListHeight))
            .scrollBounceBehavior(.basedOnSize)

            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 7)

            actionRow(
                title: "Management",
                systemImage: "list.bullet.below.rectangle",
                isSelected: selectedDestination == .management
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
        // Height follows the content; only the width is fixed.
        .frame(width: width)
        // Node 94:1440 uses Apple's "Liquid Glass Regular Medium" surface.
        // `glassEffect` owns the system border, blur, and shadow together;
        // combining it with a Material/hand-drawn border double-renders glass.
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .accessibilityElement(children: .contain)
    }

    private func hatcheryRow(_ hatchery: HatcheryEntity) -> some View {
        let isActive = selectedDestination == .hatchery(hatchery.id)

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
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark" : systemImage)
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

/// Management's Figma detail/edit sheet pair:
/// The sheets this screen can show, as one value, so they can share a single
/// `.sheet` modifier.
private enum ManagementSheet: Identifiable {
    case hatcheryDetail(HatcheryEntity)
    case profile(ProfileController)

    var id: String {
        switch self {
        case .hatcheryDetail(let hatchery): hatchery.id.uuidString
        case .profile: "profile"
        }
    }
}

/// 122:3437 is the read-only hatchery detail, and 122:3333 is its edit state.
/// Both modes live in one native sheet so the edit transition keeps the same
/// presentation, drag affordance, and underlying Management context.
private struct HatcheryManagementDetailSheet: View {
    let hatchery: HatcheryEntity
    let controller: HatcheryListController
    let onRescan: (HatcheryEntity) -> Void
    let onRename: (HatcheryEntity) -> Void
    let startsEditing: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isEditing: Bool

    init(
        hatchery: HatcheryEntity,
        controller: HatcheryListController,
        onRescan: @escaping (HatcheryEntity) -> Void,
        onRename: @escaping (HatcheryEntity) -> Void,
        startsEditing: Bool
    ) {
        self.hatchery = hatchery
        self.controller = controller
        self.onRescan = onRescan
        self.onRename = onRename
        self.startsEditing = startsEditing
        _name = State(initialValue: hatchery.name)
        _isEditing = State(initialValue: startsEditing)
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = min(358, max(0, geometry.size.width - 44))

            ZStack(alignment: .top) {
                Color(hex: "#F2F2F7")
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    sheetHeader(contentWidth: contentWidth)

                    if isEditing {
                        editingContent(contentWidth: contentWidth)
                            .padding(.top, 10)
                    } else {
                        informationSection(
                            contentWidth: contentWidth,
                            isEditing: false
                        )
                        .padding(.top, 10)
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.top, 14)
            }
        }
        .preferredColorScheme(.light)
    }

    private func sheetHeader(contentWidth: CGFloat) -> some View {
        ZStack {
            Text(hatchery.name)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                sheetToolbarButton(
                    systemName: "xmark",
                    isProminent: false,
                    action: dismiss.callAsFunction
                )
                .accessibilityLabel("Close")

                Spacer(minLength: 0)

                if isEditing {
                    sheetToolbarButton(
                        systemName: "checkmark",
                        isProminent: true,
                        action: saveEdits
                    )
                    .disabled(!canSave || isSaving)
                    .accessibilityLabel(isSaving ? "Saving hatchery" : "Save hatchery")
                } else {
                    sheetToolbarButton(
                        systemName: "pencil",
                        isProminent: false,
                        action: { isEditing = true }
                    )
                    .accessibilityLabel("Edit " + hatchery.name)
                }
            }
        }
        .frame(width: contentWidth, height: 44)
    }

    private func sheetToolbarButton(
        systemName: String,
        isProminent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isProminent && isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 20, weight: .regular))
                }
            }
            .foregroundStyle(isProminent ? Color.white : Color.black)
            .frame(width: 44, height: 44)
            .background(isProminent ? Color.blue : Color.white, in: Circle())
            .overlay {
                if !isProminent {
                    Circle().stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func editingContent(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            rescanAction(contentWidth: contentWidth)

            informationSection(contentWidth: contentWidth, isEditing: true)
                .padding(.top, 24)

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.appRed)
                    .padding(.top, 12)
            }
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private func rescanAction(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Re-scanning")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.appNeutralGray2)

            Button {
                beginRescan()
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

    private func informationSection(
        contentWidth: CGFloat,
        isEditing: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Information")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.black)

            Text("Hatch detail information")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.black.opacity(0.5))
                .padding(.top, 2)

            detailInformationCard(
                contentWidth: contentWidth,
                isEditing: isEditing
            )
                .padding(.top, 16)
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private func detailInformationCard(
        contentWidth: CGFloat,
        isEditing: Bool
    ) -> some View {
        return VStack(spacing: 0) {
            detailRow(title: "Hatchery name") {
                if isEditing {
                    TextField("Hatchery name", text: $name)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.blue)
                        .tint(Color.blue)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .frame(maxWidth: 190)
                        .accessibilityLabel("Hatchery name")
                } else {
                    detailValue(hatchery.name)
                }
            }
            detailSeparator

            detailRow(title: "Area") {
                detailValue("\(formattedArea) m²")
            }
            detailSeparator

            detailRow(title: "Section") {
                detailValue(String(hatchery.sectionCount))
            }
            detailSeparator

            detailRow(title: "Date created") {
                detailValue(formattedCreatedDate)
            }
            detailSeparator

            detailRow(title: "Demension") {
                if isEditing {
                    Button(action: beginRescan) {
                        Text(editableDimension)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color.blue)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit dimensions")
                    .accessibilityHint("Starts re-scanning to update the hatchery area")
                } else {
                    detailValue(formattedDimension)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(width: contentWidth, height: 340)
        .background(.white, in: RoundedRectangle(cornerRadius: 26))
    }

    private func detailRow<Content: View>(
        title: String,
        @ViewBuilder value: () -> Content
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(.black)

            Spacer(minLength: 8)

            value()
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 17, weight: .regular))
        .frame(height: 67.2)
    }

    private var detailSeparator: some View {
        Rectangle()
            .fill(Color(hex: "#E5E5EA"))
            .frame(height: 1)
    }

    private func detailValue(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(Color(hex: "#8E8E93"))
            .lineLimit(1)
    }

    private var formattedArea: String {
        let area = hatchery.shape == .circle
            ? .pi * hatchery.widthM * hatchery.widthM
            : hatchery.areaM2
        guard area.rounded() != area else { return String(Int(area)) }
        return fixedDecimal(area)
    }

    private var formattedDimension: String {
        "W \(fixedDecimal(hatchery.widthM)) x H \(fixedDecimal(hatchery.lengthM))m"
    }

    private var editableDimension: String {
        "\(compactDecimal(hatchery.widthM))m x \(compactDecimal(hatchery.lengthM))m"
    }

    private var formattedCreatedDate: String {
        guard let createdAt = hatchery.createdAt else { return "—" }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = calendar.component(.day, from: createdAt)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = .current
        formatter.dateFormat = "MMMM, yyyy"
        return "\(day)\(ordinalSuffix(for: day)) \(formatter.string(from: createdAt))"
    }

    private func fixedDecimal(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func compactDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func ordinalSuffix(for day: Int) -> String {
        switch day % 100 {
        case 11, 12, 13:
            return "th"
        default:
            switch day % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSaving: Bool {
        controller.updatingHatcheryID == hatchery.id
    }

    private func saveEdits() {
        guard canSave, !isSaving else { return }

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
    }

    private func beginRescan() {
        dismiss()
        DispatchQueue.main.async {
            onRescan(hatchery)
        }
    }
}

#Preview("Management · Figma reference", traits: .fixedLayout(width: 402, height: 874)) {
    HatcheryManagementView(
        controller: AppContainer().makeHatcheryListController(),
        onSelect: { _ in },
        onCreateNew: {}
    )
}
