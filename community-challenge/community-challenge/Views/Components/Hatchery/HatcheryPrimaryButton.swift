import SwiftUI

/// The shared full-width primary call to action used throughout the hatchery
/// and nest flows. Page-specific placement stays with each screen; this view
/// owns only the stable 55 pt visual and interaction contract.
struct HatcheryPrimaryButton: View {
    let title: String
    var scale: CGFloat = 1
    var isDisabled = false
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: HatcheryDesignMetrics.primaryButtonCornerRadius * scale,
            style: .continuous
        )
    }

    var body: some View {
        Button(action: action) {
            Text(title)
            .font(.system(size: 17 * scale, weight: .semibold))
            .foregroundStyle(Color(hex: "#FAF8F4"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appGreenPrimary, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .frame(height: HatcheryDesignMetrics.primaryButtonHeight * scale)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

enum HatcheryDesignMetrics {
    static let primaryButtonCornerRadius: CGFloat = 26
    static let primaryButtonHeight: CGFloat = 55
}

#Preview("Primary button") {
    HatcheryPrimaryButton(title: "Continue", action: {})
        .padding()
        .background(Color.white)
}
