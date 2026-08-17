import SwiftUI

/// Figma 175:3792. Stands in for the hatchery grid when the area was never
/// photographed.
///
/// A skipped scan still produces a valid grid, so the dashboard would
/// otherwise render a blank white rectangle that looks like a loading failure.
/// This says what is missing and how to fix it instead.
struct HatcheryScanPrompt: View {
    let onScan: () -> Void

    var body: some View {
        Button(action: onScan) {
            VStack(spacing: 10) {
                Image(systemName: "move.3d")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Color(hex: "#C7C7CC"))
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Scan your hatchery area now")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)

                    Text("Some description here what they will have if scan, like the benefit")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.black.opacity(0.45))
                }
                .multilineTextAlignment(.center)
                .frame(width: 248)
            }
            .padding(10)
            .frame(width: 370, height: 295)
            .background(
                Color.white.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 24)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        Color(hex: "#C7C7CC"),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 6])
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan your hatchery area")
        .accessibilityHint("Opens the camera to map this hatchery")
    }
}

#Preview("Scan prompt · Figma 175:3792", traits: .fixedLayout(width: 402, height: 400)) {
    HatcheryScanPrompt(onScan: {})
}
