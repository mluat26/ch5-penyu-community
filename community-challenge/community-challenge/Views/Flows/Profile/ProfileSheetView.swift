import SwiftUI

/// Figma 158:2280 (view), 158:2307 (edit), and 158:2335 (role menu open).
///
/// One screen with an editing flag rather than three: the frames differ only
/// in whether values are editable, which toolbar action shows, and whether the
/// destructive row reads Sign out or Delete Account.
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
    /// (158:2307 / 158:2335) can be rendered directly.
    var startsEditing = false

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
    }

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, geometry.size.width / Layout.sheetWidth)

            ZStack(alignment: .topLeading) {
                Color(uiColor: .systemGroupedBackground)

                toolbar(scale: scale)
                    .offset(y: 16 * scale)

                body(scale: scale)
                    .offset(x: Layout.contentInset * scale, y: Layout.bodyTop * scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .task {
            isEditing = startsEditing
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

    // MARK: - Toolbar (Figma 158:2290 — 44pt buttons at x16 / x330, title at y13)

    private func toolbar(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Button {
                if isEditing {
                    controller.discardEdits()
                    isEditing = false
                } else {
                    onClose()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17 * scale, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44 * scale, height: 44 * scale)
                    .background(Color(hex: "#E9E9EB"), in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 16 * scale)
            .accessibilityLabel(isEditing ? "Discard changes" : "Close")

            // Figma's title node is 36pt wide because that is what "Profile"
            // measures there; constraining to it truncates under SwiftUI's
            // metrics. Centre a full-width label at the same y instead.
            Text("Profile")
                .font(.system(size: 17 * scale, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: Layout.sheetWidth * scale, height: 22 * scale)
                .offset(y: 13 * scale)

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
        .frame(width: Layout.sheetWidth * scale, height: 54 * scale, alignment: .topLeading)
    }

    // MARK: - Body (Figma 158:2293 — sections at y0 / y172 / y396)

    private func body(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            section(title: "Personal information", scale: scale) {
                profileRow(
                    title: "Name",
                    value: controller.displayName,
                    isEditable: isEditing,
                    text: $controller.draftName,
                    scale: scale
                )
                rowDivider(scale: scale)
                profileRow(
                    title: "Apple Account",
                    value: controller.appleAccount,
                    // Apple owns this value; never editable here.
                    isEditable: false,
                    text: .constant(""),
                    scale: scale
                )
            }

            section(title: "Organization", scale: scale) {
                roleRow(scale: scale)
                rowDivider(scale: scale)
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
            .offset(y: 396 * scale)

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13 * scale, weight: .regular))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(width: Layout.contentWidth * scale)
                    .offset(y: 460 * scale)
            }
        }
        .frame(width: Layout.contentWidth * scale, alignment: .topLeading)
    }

    /// Figma section: 28pt title, then the table 44pt below its own top.
    private func section<Content: View>(
        title: String,
        scale: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Text(title)
                .font(.system(size: 22 * scale, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: Layout.contentWidth * scale, height: 28 * scale, alignment: .leading)

            groupedTable(scale: scale, content: content)
                .offset(y: 44 * scale)
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

    private func rowDivider(scale: CGFloat) -> some View {
        Rectangle()
            .fill(Color(uiColor: .separator).opacity(0.35))
            .frame(height: 1 / max(scale, 0.001) * scale)
            .padding(.leading, 16 * scale)
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
