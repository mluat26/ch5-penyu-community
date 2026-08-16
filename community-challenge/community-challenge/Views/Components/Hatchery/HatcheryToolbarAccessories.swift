import SwiftUI

/// Decorative, consistently-sized top-right controls shared by dashboard,
/// management, and hatch creation screens. Their enclosing screen continues
/// to own any navigation or menu interaction.
struct HatcheryToolbarAccessories: View {
    var scale: CGFloat = 1
    /// Supplied by screens that can open the profile sheet. Left `nil`
    /// elsewhere so the icon stays decorative, as it was for every caller
    /// before the profile screen existed.
    var onProfile: (() -> Void)?

    var body: some View {
        HStack(spacing: 12 * scale) {
            HatcheryToolbarAccessoryIcon(
                systemName: "bell",
                accessibilityLabel: "Notifications",
                scale: scale
            )

            if let onProfile {
                Button(action: onProfile) {
                    HatcheryToolbarAccessoryIcon(
                        systemName: "person",
                        accessibilityLabel: "Profile",
                        scale: scale
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens your profile and organization")
            } else {
                HatcheryToolbarAccessoryIcon(
                    systemName: "person",
                    accessibilityLabel: "Profile",
                    scale: scale
                )
            }
        }
        .frame(width: 156 * scale, height: 48 * scale)
    }
}

private struct HatcheryToolbarAccessoryIcon: View {
    let systemName: String
    let accessibilityLabel: String
    let scale: CGFloat

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 20 * scale, weight: .regular))
            .foregroundStyle(.black)
            .frame(width: 48 * scale, height: 48 * scale)
            .glassEffect(.regular, in: .circle)
            .accessibilityLabel(accessibilityLabel)
    }
}
