import Lottie
import SwiftUI

/// An animated check mark for "this worked" moments.
///
/// It replaces a static `checkmark.circle.fill` rather than playing over one:
/// the animation draws its own check, so overlaying the two shows a second
/// tick floating across whatever sits below.
///
/// Reusable anywhere a success beat is needed — nest registered, hatchery
/// saved, invite redeemed. Callers set the size; the animation fills it.
///
/// The asset is a dotLottie bundle (a zip holding the animation JSON), so it
/// loads through `DotLottieFile` rather than `.named()`, which reads only bare
/// JSON.
struct NestSuccessCheckmark: View {
    /// The space this reserves in the layout — the same slot the 60pt symbol
    /// it replaced occupied.
    var size: CGFloat = 72
    /// How far the animation is allowed to spill past that slot. The dotLottie
    /// artboard has padding around the check, so it must draw well beyond its
    /// footprint to read at the right weight; overlapping the title is
    /// intended rather than pushing it down the screen.
    var overscale: CGFloat = 2.6
    /// Colour for the still symbol shown when motion is reduced. The animation
    /// carries its own colours, so this applies only to that fallback.
    var fallbackTint: Color = .appGreenPrimary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                // Something has to mark success, so this degrades to the
                // symbol it replaced rather than leaving a gap.
                // The still symbol has no artboard padding, so it is inset to
                // match the animation's visual weight.
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(fallbackTint)
                    .padding(size * 0.2)
            } else {
                LottieView {
                    try await DotLottieFile.named("success_confetti")
                }
                .playing(loopMode: .playOnce)
            }
        }
        .frame(width: size * overscale, height: size * overscale)
        // A clear slot of `size` keeps the layout put; the animation is drawn
        // over it and allowed to bleed outside.
        .frame(width: size, height: size)
        .zIndex(1)
        .accessibilityHidden(true)
    }
}
