import SwiftUI

/// Figma 158:2371. Shows a freshly issued invite code as one box per
/// character, with the remaining lifetime made explicit — the code is only
/// valid for minutes, so a screen that hid that would be misleading.
struct InvitationCodeView: View {
    let invite: OrganizationInviteEntity
    let onBack: () -> Void
    let onRegenerate: () async -> Void

    private enum Layout {
        static let referenceWidth: CGFloat = 402
    }

    @State private var didCopy = false
    @State private var minutesRemaining: Int

    init(
        invite: OrganizationInviteEntity,
        onBack: @escaping () -> Void,
        onRegenerate: @escaping () async -> Void
    ) {
        self.invite = invite
        self.onBack = onBack
        self.onRegenerate = onRegenerate
        _minutesRemaining = State(initialValue: invite.minutesRemaining)
    }

    private var hasExpired: Bool { minutesRemaining <= 0 }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, geometry.size.width / Layout.referenceWidth)

            ZStack(alignment: .topLeading) {
                Color.white
                HatcheryWarmEllipse(scale: scale)
                    .offset(x: -110 * scale, y: -378 * scale)

                VStack(spacing: 0) {
                    header(scale: scale)

                    Spacer(minLength: 0)

                    copyButton(scale: scale)
                        .padding(.bottom, 34 * scale)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .task { await trackRemainingTime() }
    }

    private func header(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17 * scale, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 44 * scale, height: 44 * scale)
                        .glassEffect(.regular, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16 * scale)
            .padding(.top, 62 * scale)

            Image(systemName: "person.badge.key")
                .font(.system(size: 28 * scale, weight: .regular))
                .foregroundStyle(Color.appGreenPrimary)
                .padding(.top, 22 * scale)
                .accessibilityHidden(true)

            Text("Invitation Code")
                .font(.system(size: 28 * scale, weight: .bold))
                .foregroundStyle(Color.appGreenPrimary)
                .padding(.top, 12 * scale)

            Text("Share the invite code to join your\norganization’s hatchery.")
                .font(.system(size: 17 * scale, weight: .regular))
                .foregroundStyle(Color.appNeutralGray1)
                .multilineTextAlignment(.center)
                .lineSpacing(2 * scale)
                .padding(.top, 8 * scale)

            codeBoxes(scale: scale)
                .padding(.top, 28 * scale)

            expiryLabel(scale: scale)
                .padding(.top, 16 * scale)
        }
    }

    private func codeBoxes(scale: CGFloat) -> some View {
        HStack(spacing: 12 * scale) {
            ForEach(Array(invite.characters.enumerated()), id: \.offset) { _, character in
                Text(character)
                    .font(.system(size: 40 * scale, weight: .bold))
                    .foregroundStyle(
                        hasExpired
                            ? Color.appNeutralGray1.opacity(0.4)
                            : Color.appGreenPrimary.opacity(0.45)
                    )
                    .frame(width: 74 * scale, height: 96 * scale)
                    .background(
                        Color(hex: "#F1F1F1"),
                        in: RoundedRectangle(cornerRadius: 18 * scale)
                    )
            }
        }
        // One label for the whole code: four separate characters would be read
        // out as unrelated letters.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Invite code \(invite.characters.joined(separator: " "))")
    }

    @ViewBuilder
    private func expiryLabel(scale: CGFloat) -> some View {
        if hasExpired {
            Text("This code has expired")
                .font(.system(size: 15 * scale, weight: .semibold))
                .foregroundStyle(.red)
        } else {
            Text(
                minutesRemaining == 1
                    ? "Expires in 1 minute"
                    : "Expires in \(minutesRemaining) minutes"
            )
            .font(.system(size: 15 * scale, weight: .regular))
            .foregroundStyle(Color.appNeutralGray1)
        }
    }

    private func copyButton(scale: CGFloat) -> some View {
        Button {
            if hasExpired {
                Task { await onRegenerate() }
            } else {
                UIPasteboard.general.string = invite.code
                didCopy = true
            }
        } label: {
            Text(hasExpired ? "Generate a new code" : (didCopy ? "Copied" : "Copy code"))
                .font(.system(size: 17 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 370 * scale, height: 55 * scale)
                .background(
                    Color.appGreenPrimary,
                    in: RoundedRectangle(cornerRadius: 26 * scale)
                )
                .contentShape(RoundedRectangle(cornerRadius: 26 * scale))
        }
        .buttonStyle(.plain)
    }

    /// The code dies in minutes, so the countdown has to keep moving while the
    /// screen is open rather than freeze at whatever it said on appear.
    private func trackRemainingTime() async {
        while !Task.isCancelled {
            minutesRemaining = invite.minutesRemaining
            if minutesRemaining <= 0 { return }
            try? await Task.sleep(for: .seconds(15))
        }
    }
}

#Preview("Invitation Code · Figma 158:2371", traits: .fixedLayout(width: 402, height: 874)) {
    InvitationCodeView(
        invite: OrganizationInviteEntity(
            code: "K7P2",
            expiresAt: Date().addingTimeInterval(600)
        ),
        onBack: {},
        onRegenerate: {}
    )
}
