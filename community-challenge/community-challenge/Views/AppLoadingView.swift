import SwiftUI

/// The app's loading screen: the app mark
/// drops in, breathes through the wait, then scales out once there is a screen
/// to show.
///
/// This is the screen Figma 272:4832 and 272:4836 describe, and it replaces the
/// old `OpeningHatcheryView` -- a bare `ProgressView` over "Opening Hatch_01...".
/// It covers the whole wait rather than only the tail of it: the root has to
/// run the hatchery list query *and* restore the chosen hatchery's scan session
/// before anything real can render, and putting a designed screen on the second
/// half only meant two different loaders back to back.
///
/// The two frames are the same screen with and without the mark, so this is one
/// view with a phase rather than two screens. The background is
/// `HatcheryWarmBackdrop`, which already is that design -- white behind a
/// 621pt warm ellipse offset (-110, -378) with a 50pt blur, the same numbers
/// the frames carry.
/// The animation's state, held outside the view on purpose.
///
/// As `@State` inside `AppLoadingView` it was lost repeatedly: a cold launch
/// switches the root between three branches, the overlay's content is removed
/// and re-inserted across those switches, and a removed view's state does not
/// survive -- so `phase.hasDropped` reset and the spring replayed from off-screen,
/// once per switch. Pinning identity with `.id` did not help, because identity
/// only preserves state for a view that stays in the hierarchy.
///
/// Owned by the root instead, it cannot be reset by anything the root renders
/// underneath, and `hasBegun` makes a second `begin()` a no-op even if the view
/// appears again.
@MainActor
@Observable
final class AppLoadingPhase {
    var hasDropped = false
    var isPulsing = false
    var sheenPhase: CGFloat = -1
    var isLeaving = false
    /// Set once the drop and a full loop have had time to play. Without it a
    /// query that returns in 50ms makes the mark flash rather than animate.
    var hasShownLoop = false
    fileprivate var hasBegun = false
}

struct AppLoadingView: View {
    /// True once the first load has returned, successfully or not. Either way
    /// there is a real screen to show, so this stops waiting.
    let isReady: Bool
    /// Called after the exit finishes, so the caller can drop this view. The
    /// view outlives `isReady` on purpose -- removing it the moment the data
    /// arrived would cut the exit instead of playing it.
    var onFinished: () -> Void = {}
    /// Supplied by the caller and outlives this view. See `AppLoadingPhase`.
    let phase: AppLoadingPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Figma's 402pt canvas, the same reference the hatchery screens scale from.
    private static let referenceWidth: CGFloat = 402
    /// The logo alone, 124pt square.
    ///
    /// Figma's node 272:4835 is 221x124 because it carries a white backing
    /// plate behind the icon as a second image fill. That plate is invisible in
    /// Figma, whose page is near-white there, but it drew a hard white
    /// rectangle over this screen's warm backdrop -- so the asset is cropped to
    /// the icon and the plate is gone. Same visible logo, same position.
    private static let markSize = CGSize(width: 124, height: 124)
    /// The mark's centre on that canvas: 243 + 124 / 2.
    private static let markCentreY: CGFloat = 305

    /// The spring's response, and roughly how long the mark takes to arrive.
    ///
    /// It has a long way to travel -- from above the screen down to y=305, over
    /// 400pt -- so a short response gives it a high starting velocity and the
    /// mark arrives looking flung rather than lowered.
    private static let dropDuration: Double = 1.15
    private static let exitDuration: Double = 0.7
    /// The pulse and sweep start once the spring has done most of its travel.
    ///
    /// Derived rather than a separate constant, so slowing the drop moves the
    /// loops with it instead of starting them mid-flight. Sequenced rather than
    /// `.delay()` on a `repeatForever`, which starts its first cycle from the
    /// pre-delay value and lands a visible jump on top of the drop.
    private static let loopStartDelay: Double = dropDuration * 0.7
    /// One sweep across the mark.
    private static let sheenDuration: Double = 2.0
    /// One half of the pulse, so a full brighten-and-dim takes twice this.
    private static let pulseDuration: Double = 1.5
    private static let pulseAnimation: Animation = .easeInOut(duration: pulseDuration)
        .repeatForever(autoreverses: true)

    /// The shortest the screen stays, whatever the data does.
    ///
    /// The loops used to be unreachable rather than missing: the exit was
    /// allowed as soon as the drop settled, so a query that returned quickly
    /// took the screen away after about a third of one sweep. Holding for a
    /// full sweep past the point the loops start means the loop is always seen
    /// at least once.
    ///
    /// This is a floor on the launch, so it is the number to lower if the wait
    /// starts to feel long.
    private static let minimumOnScreen: Double = loopStartDelay + sheenDuration

    var body: some View {
        GeometryReader { geometry in
            let scale = max(geometry.size.width, 1) / Self.referenceWidth
            let markWidth = Self.markSize.width * scale
            let markHeight = Self.markSize.height * scale
            let markCentreY = Self.markCentreY * scale

            ZStack(alignment: .topLeading) {
                HatcheryWarmBackdrop(scale: scale)

                // Exported pre-clipped to the frame, so it is simply the
                // bottom of the screen at full width rather than the 589pt
                // node hanging off the left edge.
                Image("LaunchReefScene")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottom
                    )
                    .accessibilityHidden(true)

                appMark(
                    width: markWidth,
                    height: markHeight,
                    dropDistance: markCentreY + markHeight
                )
                .position(x: geometry.size.width / 2, y: markCentreY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        // The exit belongs to the screen, not only to the mark. Fading the mark
        // alone left the backdrop and the reef at full opacity until the
        // overlay was torn down, so the last thing seen was the whole screen
        // disappearing in one frame -- a cut, with the animation hidden inside
        // it. Fading here dissolves the screen onto the app underneath, which
        // is already composed and waiting.
        .opacity(phase.isLeaving ? 0 : 1)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Turterra")
        .onAppear(perform: begin)
        // Both conditions, and both evaluated here rather than inside the
        // Task below. `begin()`'s Task captures this view *struct*, so an
        // `isReady` read inside it is frozen at whatever it was when the task
        // started -- always false at launch. Once the floor grew past the time
        // the query takes, that stale read meant the exit was never triggered
        // from either side and the screen stayed up forever.
        .onChange(of: isReady) { _, _ in
            leaveIfPossible()
        }
        .onChange(of: phase.hasShownLoop) { _, _ in
            leaveIfPossible()
        }
    }

    private func appMark(
        width: CGFloat,
        height: CGFloat,
        dropDistance: CGFloat
    ) -> some View {
        let mark = Image("LaunchAppMark")
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)

        return mark
            .overlay {
                // Masked to the mark's own shape below. Left unmasked the
                // sweep would light up the transparent padding around the
                // artwork as a bright rectangle.
                // Across the band, not along it. Running top-to-bottom left
                // the strip's left and right sides at full brightness, so the
                // sweep had two hard vertical edges travelling with it instead
                // of reading as a shine.
                LinearGradient(
                    colors: [.clear, .white.opacity(0.65), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                // Far taller than the mark on purpose: rotated 20 degrees, a
                // band only as tall as the icon shows its own ends cutting
                // across the corners. Overshooting puts them outside the mask.
                .frame(width: width * 0.7, height: height * 2.6)
                .rotationEffect(.degrees(20))
                .offset(x: phase.sheenPhase * width * 1.4)
                // Declarative, bound to the value. Started with an imperative
                // `withAnimation` inside a Task, a `repeatForever` is dropped
                // when the root re-renders -- which it does repeatedly while
                // loading -- so the loop silently stopped and the sweep and
                // pulse were never seen. Attached here it is re-established on
                // every render instead.
                .animation(
                    .linear(duration: Self.sheenDuration)
                        .repeatForever(autoreverses: false),
                    value: phase.sheenPhase
                )
                .blendMode(.plusLighter)
            }
            .mask(mark)
            // Isolates the blend so it composites against the mark alone
            // rather than the whole screen behind it.
            //
            // No `drawingGroup()` here: it flattens the subtree into a bitmap
            // and took the mark's transparency with it, drawing an opaque
            // white rectangle around the logo. Cheaper on paper, wrong on
            // screen.
            .compositingGroup()
            // The pulse half of the loop, carried by the glow rather than by
            // the mark. A repeating `scaleEffect` on the mark itself changes
            // its apparent size, which reads as the icon dropping in again and
            // again; brightening and dimming behind it reads as a pulse
            // without anything appearing to move.
            //
            // Only the fill's opacity animates. The blur radius stays fixed --
            // animating that re-rasterises the blur every frame, which is what
            // made this screen stutter before.
            .background {
                // Wider than the mark and swinging over a much larger opacity
                // range than it first did. A green halo at a third opacity,
                // tucked behind the icon on a near-white backdrop, was there in
                // the code and invisible on the screen.
                Ellipse()
                    .fill(Color.appGreenPrimary)
                    .frame(width: width * 1.24, height: height * 1.06)
                    .blur(radius: 30)
                    .opacity(phase.isPulsing ? 0.55 : 0.06)
                    .animation(Self.pulseAnimation, value: phase.isPulsing)
            }
            // The mark lifts with the glow. Brightness is a colour filter, so
            // the icon reads as pulsing without its size or position changing --
            // which is what made the earlier scale pulse look like the icon
            // dropping in over and over.
            .brightness(phase.isPulsing ? 0.06 : 0)
            .animation(Self.pulseAnimation, value: phase.isPulsing)
            // The only scale on the mark, so nothing competes with the exit.
            .scaleEffect(phase.isLeaving ? 1.32 : 1)
            .offset(y: phase.hasDropped ? 0 : -dropDistance)
            .shadow(color: Color.appGreenPrimary.opacity(0.16), radius: 12, y: 6)
    }

    private func begin() {
        guard !phase.hasBegun else { return }
        phase.hasBegun = true

        // Reduce Motion keeps the screen and its meaning, and drops only the
        // movement: the mark is simply present, with no drop, pulse or sweep.
        guard !reduceMotion else {
            phase.hasDropped = true
            phase.hasShownLoop = true
            if isReady { leaveIfPossible() }
            return
        }

        // 0.85 damping, not 0.58. A spring that lightly damped overshoots the
        // centre, rebounds, overshoots again and only then settles -- several
        // visible bounces, which read as the mark dropping in over and over
        // rather than arriving once. This still springs, but it overshoots once
        // and stops.
        withAnimation(.spring(response: Self.dropDuration, dampingFraction: 0.85)) {
            phase.hasDropped = true
        }

        Task {
            try? await Task.sleep(for: .seconds(Self.loopStartDelay))
            guard !phase.isLeaving else { return }

            // Plain assignments. The `.animation(_:value:)` modifiers on the
            // mark carry the loops; the sweep is non-reversing so it always
            // travels the same way, restarting off the mark's left edge and
            // ending off its right, so the wrap is never on screen.
            phase.isPulsing = true
            phase.sheenPhase = 1.4

            try? await Task.sleep(
                for: .seconds(Self.minimumOnScreen - Self.loopStartDelay)
            )
            // Only records that the floor is met. The `onChange` above reacts
            // to it with a live `isReady`.
            phase.hasShownLoop = true
        }
    }

    private func leaveIfPossible() {
        guard isReady, !phase.isLeaving, phase.hasShownLoop else { return }

        // ponytail: the loops are left running through the exit. They drive
        // the glow, the brightness and the sweep; the exit drives opacity and
        // scale. Nothing overlaps, so stopping them first bought nothing.
        let duration = reduceMotion ? 0.2 : Self.exitDuration
        withAnimation(.easeOut(duration: duration)) {
            phase.isLeaving = true
        } completion: {
            onFinished()
        }
    }
}

/// Owns a phase so the screen can be rendered on its own -- by the measurement
/// harness or a preview -- without the caller having to hold one.
struct AppLoadingHost: View {
    let isReady: Bool
    var onFinished: () -> Void = {}

    @State private var phase = AppLoadingPhase()

    var body: some View {
        AppLoadingView(isReady: isReady, onFinished: onFinished, phase: phase)
    }
}

#if DEBUG
#Preview("Launch · loading", traits: .fixedLayout(width: 402, height: 874)) {
    AppLoadingHost(isReady: false)
}

#Preview("Launch · finished", traits: .fixedLayout(width: 402, height: 874)) {
    AppLoadingHost(isReady: true)
}
#endif
