import SwiftUI

/// Figma 158:2371. Shows a freshly issued invite code as one box per
/// character.
///
/// Every element is placed by the node's own coordinates on the 402pt canvas:
/// header at y163, boxes 78 × 99 on an 88pt pitch from x30/y332, button at
/// x16/y795.
struct InvitationCodeView: View {
    let invite: OrganizationInviteEntity
    let onBack: () -> Void
    let onRegenerate: () async -> Void

    private enum Layout {
        static let referenceWidth: CGFloat = 402
        static let boxWidth: CGFloat = 78
        static let boxHeight: CGFloat = 99
        static let boxPitch: CGFloat = 88
    }

    @State private var didCopy = false
    @State private var hasExpired = false

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, geometry.size.width / Layout.referenceWidth)
            let canvasX = max((geometry.size.width - Layout.referenceWidth * scale) / 2, 0)

            ZStack(alignment: .topLeading) {
                Color.white
                HatcheryWarmEllipse(scale: scale)
                    .offset(x: -110 * scale, y: -378 * scale)

                ZStack(alignment: .topLeading) {
                    backButton(scale: scale)
                        .offset(x: 16 * scale, y: 82 * scale)

                    header(scale: scale)
                        .offset(x: 40.5 * scale, y: 163 * scale)

                    codeBoxes(scale: scale)
                        .offset(x: 30 * scale, y: 332 * scale)

                    copyButton(scale: scale)
                        .offset(x: 16 * scale, y: 795 * scale)
                }
                .offset(x: canvasX)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .task { await trackExpiry() }
    }

    /// 158:2379 — a 72 × 48 accessory bar, not a circular button.
    private func backButton(scale: CGFloat) -> some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17 * scale, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 72 * scale, height: 48 * scale)
                .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    /// 158:2374 — icon (34), title at y46 (34), subtitle at y92 (44), all 321 wide.
    private func header(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 28 * scale, weight: .regular))
                .foregroundStyle(Color.appGreenPrimary)
                .frame(width: 321 * scale, height: 34 * scale)
                .accessibilityHidden(true)

            Text("Invitation Code")
                .font(.system(size: 28 * scale, weight: .bold))
                .foregroundStyle(Color.appGreenPrimary)
                .frame(width: 321 * scale, height: 34 * scale)
                .offset(y: 46 * scale)

            Text("Share the invite code to join your organization’s hatchery.")
                .font(.system(size: 17 * scale, weight: .regular))
                .foregroundStyle(Color.appNeutralGray1)
                .multilineTextAlignment(.center)
                .lineSpacing(2 * scale)
                .frame(width: 321 * scale, height: 44 * scale)
                .offset(y: 92 * scale)
        }
        .multilineTextAlignment(.center)
        .frame(width: 321 * scale, height: 136 * scale, alignment: .topLeading)
    }

    /// 158:2381 — four 78 × 99 boxes on an 88pt pitch, digit 55pt.
    private func codeBoxes(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(invite.characters.enumerated()), id: \.offset) { index, character in
                Text(character)
                    .font(.system(size: 55 * scale, weight: .bold))
                    .tracking(0.4 * scale)
                    .foregroundStyle(
                        Color(hex: "#0C7C4D").opacity(hasExpired ? 0.2 : 1)
                    )
                    .frame(width: Layout.boxWidth * scale, height: Layout.boxHeight * scale)
                    .background(
                        Color(hex: "#F1F1F1"),
                        in: RoundedRectangle(cornerRadius: 16 * scale)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16 * scale)
                            .stroke(Color(hex: "#EBEBEB"), lineWidth: 1)
                    }
                    .offset(x: Layout.boxPitch * CGFloat(index) * scale)
            }
        }
        // One label for the whole code: four separate characters would be read
        // out as unrelated letters.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Invite code \(invite.characters.joined(separator: " "))")
        .frame(
            width: (Layout.boxPitch * 3 + Layout.boxWidth) * scale,
            height: Layout.boxHeight * scale,
            alignment: .topLeading
        )
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
                .foregroundStyle(Color(hex: "#FAF8F4"))
                .frame(width: 370 * scale, height: 55 * scale)
                .background(
                    Color.appGreenPrimary,
                    in: RoundedRectangle(cornerRadius: 26 * scale)
                )
                .contentShape(RoundedRectangle(cornerRadius: 26 * scale))
        }
        .buttonStyle(.plain)
    }

    /// The code dies in ten minutes. Figma has no countdown, so the screen
    /// stays as drawn until it lapses and the button becomes the way to get a
    /// fresh one — rather than adding chrome the design does not have.
    private func trackExpiry() async {
        while !Task.isCancelled {
            hasExpired = invite.hasExpired
            if hasExpired { return }
            try? await Task.sleep(for: .seconds(15))
        }
    }
}

#Preview("Invitation Code · Figma 158:2371", traits: .fixedLayout(width: 402, height: 874)) {
    InvitationCodeView(
        invite: OrganizationInviteEntity(
            code: "3333",
            expiresAt: Date().addingTimeInterval(600)
        ),
        onBack: {},
        onRegenerate: {}
    )
}
