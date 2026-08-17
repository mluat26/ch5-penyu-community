import SwiftUI

/// The shared Figma ellipse used behind hatchery screens.
///
/// This deliberately follows the design component rather than using a
/// `Circle`: it is a 621 × 621pt clear rectangle with a warm background,
/// fully rounded corners, and a 50pt blur. Screens can reuse it without
/// drifting in color, size, or blur strength.
struct HatcheryWarmEllipse: View {
    static let figmaFill = Color(red: 1, green: 0.96, blue: 0.93)

    var fill = figmaFill
    var scale: CGFloat = 1

    var body: some View {
        Rectangle()
            .foregroundColor(.clear)
            .frame(width: 621 * scale, height: 621 * scale)
            .background(fill)
            .cornerRadius(621 * scale)
            .blur(radius: 50 * scale)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Figma's recurring warm glow behind hatchery and add-nest screens. Screens
/// may supply a status color or scale, but the 402pt reference placement
/// remains consistent.
struct HatcheryWarmBackdrop: View {
    var glowColor = HatcheryWarmEllipse.figmaFill
    var scale: CGFloat = 1

    var body: some View {
        Color.white
            .overlay(alignment: .topLeading) {
                HatcheryWarmEllipse(fill: glowColor, scale: scale)
                    .offset(x: -110 * scale, y: -378 * scale)
            }
            .allowsHitTesting(false)
    }
}
