import SwiftUI

/// Figma 200:4184 (read), 200:4241 (edit), 200:4269 (edit, role menu open) and
/// 200:4212 (the members list drilled into from the read state).
///
/// One screen with two flags rather than four: the profile frames differ only
/// in whether values are editable, which toolbar action shows, whether the
/// Members list row is present, and whether the destructive row reads Sign out
/// or Delete Account. The members list reuses the same sheet chrome, so it is
/// a state here rather than a second presentation — SwiftUI keeps only the
/// last `.sheet` attached to a view, and both call sites already spend theirs.
///
/// Laid out against Figma's sheet frame (390 × 801 at x6/y73) rather than
/// system list chrome, because the design places every element by coordinate.
/// The sheet itself stays a real `.sheet` so drag-to-dismiss still works —
/// `presentationSizing(.page)` produces exactly the 6pt inset Figma draws.
struct ProfileSheetView: View {
    @Bindable var controller: ProfileController
    let onClose: () -> Void
    let onSignOut: () -> Void
    /// Hands the issued code up so the invite screen can be presented as a
    /// full page rather than pushed inside this sheet.
    let onShowInvite: (OrganizationInviteEntity) -> Void
    /// Deletes the account and everything it owns. Throws so the database's
    /// own refusal — an organization with other members — reaches the person.
    let onDeleteAccount: () async throws -> Void
    /// Set only by the Figma measurement harness, so the edit frames
    /// (200:4241 / 200:4269) can be rendered directly.
    var startsEditing = false
    /// Likewise for the members list frame (200:4212).
    var startsShowingMembers = false

    /// Figma's sheet frame. Every offset below is relative to it.
    enum Layout {
        static let sheetWidth: CGFloat = 390
        /// Figma puts the sheet's top edge at y=73 on an 874pt screen.
        ///
        /// iOS 26 floats a sheet 8pt above the bottom rather than adding a
        /// safe-area inset, so the top lands at `874 - 8 - height`, and the
        /// presented height runs ~2pt over the detent. Measured on device:
        /// a detent of 791 puts the top at 73.
        static let detentHeight: CGFloat = 791
        static let contentInset: CGFloat = 14
        static let contentWidth: CGFloat = 362
        static let rowHeight: CGFloat = 52
        static let bodyTop: CGFloat = 86
        /// Section title (28) plus Figma's 16pt gap to the table below it.
        static let tableTop: CGFloat = 44
    }

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    /// Figma 200:4212 — drilled into from the read state's Members list row.
    @State private var isShowingMembers = false

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, geometry.size.width / Layout.sheetWidth)

            ZStack(alignment: .topLeading) {
                Color(uiColor: .systemGroupedBackground)

                // Every offset below is a Figma coordinate inside the 390pt
                // sheet, so they are laid out in a block of exactly that width
                // and the block is centred. iOS presents the sheet full width
                // (402pt measured), which left the design pinned to the
                // leading edge with all 40pt of slack on the right.
                ZStack(alignment: .topLeading) {
                    toolbar(scale: scale)
                        .offset(y: 16 * scale)

                    Group {
                        if isShowingMembers {
                            membersBody(scale: scale, availableHeight: geometry.size.height)
                        } else {
                            body(scale: scale)
                        }
                    }
                    .offset(x: Layout.contentInset * scale, y: Layout.bodyTop * scale)
                }
                .frame(width: Layout.sheetWidth * scale, alignment: .topLeading)
                .frame(width: geometry.size.width, alignment: .center)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .task {
            isEditing = startsEditing
            isShowingMembers = startsShowingMembers
            await controller.load()
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your hatcheries, their nests, and your organization. It cannot be undone.")
        }
    }

    // MARK: - Toolbar (Figma 200:4194 — 44pt buttons at x16 / x330, title at y13)

    private func toolbar(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Button {
                if isShowingMembers {
                    isShowingMembers = false
                } else if isEditing {
                    controller.discardEdits()
                    isEditing = false
                } else {
                    onClose()
                }
            } label: {
                // Figma draws an xmark here on 200:4212 too, but that frame is
                // reached by drilling in, so an xmark would leave no way back
                // short of dismissing the whole sheet. Same 44pt circle at the
                // same x; only the glyph differs.
                Image(systemName: isShowingMembers ? "chevron.left" : "xmark")
                    .font(.system(size: 17 * scale, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44 * scale, height: 44 * scale)
                    .background(Color(hex: "#E9E9EB"), in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 16 * scale)
            .accessibilityLabel(leadingButtonLabel)

            // Figma's title node is 36pt wide because that is what "Profile"
            // measures there; constraining to it truncates under SwiftUI's
            // metrics. Centre a full-width label at the same y instead.
            Text(isShowingMembers ? "Members list" : "Profile")
                .font(.system(size: 17 * scale, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: Layout.sheetWidth * scale, height: 22 * scale)
                .offset(y: 13 * scale)

            // 200:4212 draws a prominent pencil here, but nothing on the
            // members list is editable by this app: `ProfileUpdateDTO` carries
            // no `role`, and the database has no function for changing another
            // member's. Rather than ship a button that cannot do anything, the
            // members list has no trailing action.
            if !isShowingMembers {
                Button {
                    if isEditing {
                        Task {
                            await controller.save()
                            if controller.errorMessage == nil { isEditing = false }
                        }
                    } else {
                        isEditing = true
                    }
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                        .font(.system(size: 17 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44 * scale, height: 44 * scale)
                        .background(Color.accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(controller.isSaving)
                .offset(x: 330 * scale)
                .accessibilityLabel(isEditing ? "Save profile" : "Edit profile")
            }
        }
        .frame(width: Layout.sheetWidth * scale, height: 54 * scale, alignment: .topLeading)
    }

    private var leadingButtonLabel: String {
        if isShowingMembers { return "Back to profile" }
        return isEditing ? "Discard changes" : "Close"
    }

    // MARK: - Body (Figma 200:4197 — sections at y0 / y172, destructive below)

    /// Figma 200:4210 puts the Sign out table at y448 because the read state's
    /// Organization table carries four rows (208pt); 200:4267 puts Delete
    /// Account at y396 because the edit state drops the Members list row and
    /// the table is 156pt. One row's difference, so one offset.
    private var destructiveTableTop: CGFloat { isEditing ? 396 : 448 }

    private func body(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            section(
                title: "Personal information",
                scale: scale,
                isPlaceholder: controller.isLoadingProfile
            ) {
                profileRow(
                    title: "Name",
                    value: controller.displayName,
                    isEditable: isEditing,
                    text: $controller.draftName,
                    scale: scale
                )
            }

            section(
                title: "Organization",
                scale: scale,
                isPlaceholder: controller.isLoadingProfile
            ) {
                roleRow(scale: scale)
                rowDivider(scale: scale)
                // 200:4207. Absent from the edit frames (200:4241 / 200:4269):
                // drilling into another screen mid-edit would strand the draft.
                if !isEditing {
                    membersRow(scale: scale)
                    rowDivider(scale: scale)
                }
                organizationRow(scale: scale)
                rowDivider(scale: scale)
                generateInviteRow(scale: scale)
            }
            .offset(y: 172 * scale)

            groupedTable(scale: scale) {
                actionRow(
                    title: isEditing ? "Delete Account" : "Sign out",
                    systemImage: isEditing ? "trash" : "rectangle.portrait.and.arrow.right",
                    scale: scale
                ) {
                    if isEditing { isConfirmingDelete = true } else { onSignOut() }
                }
            }
            .offset(y: destructiveTableTop * scale)

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13 * scale, weight: .regular))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(width: Layout.contentWidth * scale)
                    .offset(y: (destructiveTableTop + 64) * scale)
            }
        }
        .frame(width: Layout.contentWidth * scale, alignment: .topLeading)
    }

    /// Figma section: 28pt title, then the table 44pt below its own top.
    ///
    /// `isPlaceholder` covers the table while the profile is still loading.
    /// Every value in these two sections has a fallback -- "Not set", "—",
    /// Agent -- so an unredacted table states them as fact before the answer
    /// is known, and a slow request is indistinguishable from an empty
    /// profile. Only the table is redacted; the heading is already true.
    private func section<Content: View>(
        title: String,
        scale: CGFloat,
        isPlaceholder: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Text(title)
                .font(.system(size: 22 * scale, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: Layout.contentWidth * scale, height: 28 * scale, alignment: .leading)

            groupedTable(scale: scale, content: content)
                .offset(y: Layout.tableTop * scale)
                .redacted(reason: isPlaceholder ? .placeholder : [])
                // Redaction only greys the rows out; the invite row is still a
                // live button underneath one.
                .disabled(isPlaceholder)
        }
    }

    private func groupedTable<Content: View>(
        scale: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) { content() }
            .frame(width: Layout.contentWidth * scale)
            .background(.white, in: RoundedRectangle(cornerRadius: 26 * scale))
            .clipShape(RoundedRectangle(cornerRadius: 26 * scale))
    }

    /// Figma folds the separator into the row it closes: every table there is
    /// exactly 52 × rows (104 for two, 208 for four), never a point more. So
    /// the line straddles the boundary at zero layout height rather than
    /// pushing the table past the coordinates the sections are placed by.
    private func rowDivider(scale: CGFloat) -> some View {
        Rectangle()
            .fill(Color(uiColor: .separator).opacity(0.35))
            .frame(height: 1)
            .padding(.leading, 16 * scale)
            .frame(height: 0)
    }

    private func profileRow(
        title: String,
        value: String,
        isEditable: Bool,
        text: Binding<String>,
        scale: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 17 * scale, weight: .regular))
                .foregroundStyle(.black)

            Spacer(minLength: 8 * scale)

            if isEditable {
                TextField(title, text: text)
                    .font(.system(size: 17 * scale, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            } else {
                Text(value)
                    .font(.system(size: 17 * scale, weight: .regular))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16 * scale)
        .frame(width: Layout.contentWidth * scale, height: Layout.rowHeight * scale)
    }

    /// Figma 158:2335 — the role list with a checkmark on the current value.
    /// "Add role" is intentionally absent: role is a database enum, so the app
    /// cannot invent new values.
    private func roleRow(scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("Role")
                .font(.system(size: 17 * scale, weight: .regular))
                .foregroundStyle(.black)

            Spacer(minLength: 8 * scale)

            if isEditing {
                Menu {
                    ForEach(OrganizationRole.allCases, id: \.self) { role in
                        // Roles are assigned by the organization, not chosen by
                        // the member, so selecting is deliberately inert.
                        Button {} label: {
                            if role == controller.role {
                                Label(role.displayName, systemImage: "checkmark")
                            } else {
                                Text(role.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4 * scale) {
                        Text(controller.role.displayName)
                            .font(.system(size: 17 * scale, weight: .regular))
                            .foregroundStyle(Color(hex: "#8E8E93"))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 13 * scale, weight: .semibold))
                            .foregroundStyle(Color(hex: "#8E8E93"))
                    }
                }
            } else {
                Text(controller.role.displayName)
                    .font(.system(size: 17 * scale, weight: .regular))
                    .foregroundStyle(Color(hex: "#8E8E93"))
            }
        }
        .padding(.horizontal, 16 * scale)
        .frame(width: Layout.contentWidth * scale, height: Layout.rowHeight * scale)
    }

    /// Figma 200:4207 — the member count with a drill-in to 200:4212.
    private func membersRow(scale: CGFloat) -> some View {
        Button {
            isShowingMembers = true
        } label: {
            HStack(spacing: 0) {
                Text("Members list")
                    .font(.system(size: 17 * scale, weight: .regular))
                    .foregroundStyle(.black)

                Spacer(minLength: 8 * scale)

                Text("\(controller.members.count)")
                    .font(.system(size: 17 * scale, weight: .regular))
                    .foregroundStyle(Color(hex: "#8E8E93"))

                Image(systemName: "chevron.right")
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .padding(.leading, 8 * scale)
            }
            .padding(.horizontal, 16 * scale)
            .frame(width: Layout.contentWidth * scale, height: Layout.rowHeight * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows everyone in this organization")
    }

    // MARK: - Members list (Figma 200:4212 — section at y0, rows 52 tall)

    /// Scrolls because the table grows with the organization: Figma draws five
    /// members, but 13 already run past the sheet's bottom edge.
    private func membersBody(scale: CGFloat, availableHeight: CGFloat) -> some View {
        let tableHeight = Layout.rowHeight * CGFloat(controller.members.count)

        return ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                section(title: "Members list", scale: scale) {
                    ForEach(Array(controller.members.enumerated()), id: \.element.id) { index, member in
                        if index > 0 { rowDivider(scale: scale) }
                        memberRow(member, scale: scale)
                    }
                }
            }
            .frame(
                width: Layout.contentWidth * scale,
                height: (Layout.tableTop + tableHeight) * scale,
                alignment: .topLeading
            )
        }
        .frame(
            width: Layout.contentWidth * scale,
            height: max(0, availableHeight - Layout.bodyTop * scale),
            alignment: .topLeading
        )
    }

    private func memberRow(_ member: ProfileEntity, scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(member.displayName?.isEmpty == false ? member.displayName! : "Not set")
                .font(.system(size: 17 * scale, weight: .regular))
                .foregroundStyle(.black)
                .lineLimit(1)

            Spacer(minLength: 8 * scale)

            Text(member.role.displayName)
                .font(.system(size: 17 * scale, weight: .regular))
                .foregroundStyle(Color(hex: "#8E8E93"))
        }
        .padding(.horizontal, 16 * scale)
        .frame(width: Layout.contentWidth * scale, height: Layout.rowHeight * scale)
        .accessibilityElement(children: .combine)
    }

    private func organizationRow(scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("Organization ID")
                .font(.system(size: 17 * scale, weight: .regular))
                .foregroundStyle(.black)

            Spacer(minLength: 8 * scale)

            Text(controller.organizationCode)
                .font(.system(size: 17 * scale, weight: .regular))
                .foregroundStyle(Color(hex: "#8E8E93"))

            Button {
                UIPasteboard.general.string = controller.organizationCode
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15 * scale, weight: .regular))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .frame(width: 24 * scale, height: Layout.rowHeight * scale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy organization ID")
        }
        .padding(.leading, 16 * scale)
        .padding(.trailing, 12 * scale)
        .frame(width: Layout.contentWidth * scale, height: Layout.rowHeight * scale)
    }

    private func generateInviteRow(scale: CGFloat) -> some View {
        Button {
            Task {
                await controller.generateInvite()
                if let invite = controller.invite { onShowInvite(invite) }
            }
        } label: {
            HStack(spacing: 6 * scale) {
                if controller.isGeneratingInvite {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 15 * scale, weight: .regular))
                }
                Text("Generate invite code")
                    .font(.system(size: 17 * scale, weight: .regular))
            }
            .foregroundStyle(Color.accentColor)
            .frame(width: Layout.contentWidth * scale, height: Layout.rowHeight * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(controller.isGeneratingInvite || !controller.canGenerateInvite)
        .opacity(controller.canGenerateInvite ? 1 : 0)
    }

    private func actionRow(
        title: String,
        systemImage: String,
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6 * scale) {
                if isDeleting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 15 * scale, weight: .regular))
                }
                Text(title)
                    .font(.system(size: 17 * scale, weight: .regular))
            }
            .foregroundStyle(.red)
            .frame(width: Layout.contentWidth * scale, height: Layout.rowHeight * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
    }

    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await onDeleteAccount()
        } catch {
            controller.setErrorMessage(error.localizedDescription)
        }
    }
}
