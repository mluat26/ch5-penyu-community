import SwiftUI

/// The passive visual label for the hatchery selector. The presenting screen
/// owns the full-size native Button hit target so physical-device interaction
/// remains reliable.
struct HatcherySelectorLabel: View {
    let hatcheryName: String

    var body: some View {
        HStack(spacing: 4) {
            Text(hatcheryName)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Image(systemName: "chevron.up.chevron.down")
                .font(.title3)
        }
        .foregroundStyle(Color.appGreenPrimary)
        .frame(width: 148, height: 48, alignment: .leading)
        .accessibilityHidden(true)
    }
}
