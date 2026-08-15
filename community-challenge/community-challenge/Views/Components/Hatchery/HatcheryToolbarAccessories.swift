import SwiftUI

/// Decorative, consistently-sized top-right controls shared by dashboard,
/// management, and hatch creation screens. Their enclosing screen continues
/// to own any navigation or menu interaction.
struct HatcheryToolbarAccessories: View {
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 12 * scale) {
            HatcheryToolbarAccessoryIcon(
                systemName: "bell",
                accessibilityLabel: "Notifications",
                scale: scale
            )
            HatcheryToolbarAccessoryIcon(
                systemName: "person",
                accessibilityLabel: "Profile",
                scale: scale
            )
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
