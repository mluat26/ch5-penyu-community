import SwiftUI

/// Confirms a finished hatchery setup before handing the user to the
/// dashboard, for both the first hatchery in onboarding and every one added
/// afterwards.
///
/// Terminal by design: the grid has already been written by the time this
/// appears, so there is no back affordance -- the only way on is forward.
struct HatcheryReadyView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            HatcherySetupBackdrop()
                .ignoresSafeArea()

            // Centred as one column rather than pinned at Figma's y-offsets:
            // the sibling setup screens hardcode heights that add up to
            // exactly 874pt and lose their buttons on anything shorter.
            VStack(spacing: 0) {
                // Draws its own check, so it stands in for the static glyph
                // rather than playing over it. Reserves Figma's 54pt slot and
                // is allowed to bleed past it -- the 56pt gap below still
                // clears the title.
                NestSuccessCheckmark(size: 54)

                Text("You’re all set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appGreenPrimary)
                    .padding(.top, 56)

                Text("Your hatchery is ready.")
                    .font(.body)
                    .foregroundStyle(Color.appNeutralGray1)
                    .padding(.top, 12)

                Image("HatchedTurtle")
                    .resizable()
                    .scaledToFit()
                    .padding(.top, 64)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.center)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HatcheryPrimaryButton(title: "Go to the Hatchery", action: onContinue)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }
}

#Preview {
    HatcheryReadyView {}
}
