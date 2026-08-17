import SwiftUI

/// The two Figma name-entry variants share the same keyboard-safe canvas and
/// differ only in their artwork/copy/chrome. Keeping them in one view means a
/// newly added hatch follows precisely the same validation and routing path as
/// the very first one.
enum HatcheryNameEntryStyle {
    case firstHatch
    case additionalHatch

    fileprivate var configuration: HatcheryNameEntryConfiguration {
        switch self {
        case .firstHatch:
            HatcheryNameEntryConfiguration(
                defaultName: "Hatch_01",
                title: "Create your first\nhatch",
                subtitle: "Name your first turtle egg incubator\nhatch",
                buttonTitle: "Create a hatch",
                titleTop: 423,
                titleHeight: 138,
                titleTextHeight: 82,
                subtitleTextHeight: 44,
                fieldTop: 617,
                buttonTop: 742
            )
        case .additionalHatch:
            HatcheryNameEntryConfiguration(
                defaultName: "Hatch_02",
                title: "Create new hatch",
                subtitle: "Name your turtle egg incubator hatch",
                buttonTitle: "Scan new hatchery area",
                titleTop: 431,
                titleHeight: 75,
                titleTextHeight: 41,
                subtitleTextHeight: 22,
                fieldTop: 562,
                buttonTop: 795
            )
        }
    }
}

private struct HatcheryNameEntryConfiguration {
    let defaultName: String
    let title: String
    let subtitle: String
    let buttonTitle: String
    let titleTop: CGFloat
    let titleHeight: CGFloat
    let titleTextHeight: CGFloat
    let subtitleTextHeight: CGFloat
    let fieldTop: CGFloat
    let buttonTop: CGFloat
}

/// The hatchery name screen, matched to a 402 × 874 Figma canvas.
///
/// The foreground remains inside the keyboard-safe area. When the field gets
/// focus, the canvas translates upward as one unit so the artwork travels with
/// the form. The artwork's dimensions are always computed from its width, so
/// that movement never turns into an aspect-fill zoom.
struct CreateFirstHatchView: View {
    private enum Layout {
        static let referenceWidth: CGFloat = 402
        static let referenceHeight: CGFloat = 874
        static let artworkHeight: CGFloat = 437

        static let titleWidth: CGFloat = 287
        static let fieldWidth: CGFloat = 303
        static let fieldHeight: CGFloat = 92
        static let buttonWidth: CGFloat = 370
        static let buttonHeight: CGFloat = 55
    }

    let style: HatcheryNameEntryStyle
    let onCreate: (String) -> Void
    let onBack: (() -> Void)?

    @State private var hatchName: String
    @FocusState private var isNameFocused: Bool

    init(
        style: HatcheryNameEntryStyle = .firstHatch,
        onCreate: @escaping (String) -> Void = { _ in },
        onBack: (() -> Void)? = nil
    ) {
        self.style = style
        self.onCreate = onCreate
        self.onBack = onBack
        _hatchName = State(initialValue: style.configuration.defaultName)
    }

    private var canContinue: Bool {
        !hatchName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var configuration: HatcheryNameEntryConfiguration {
        style.configuration
    }

    var body: some View {
        ZStack {
            // The background remains full-screen. Only it ignores the
            // keyboard; the foreground below must reflow when it appears.
            Color.white
                .ignoresSafeArea()

            HatcherySetupBackdrop()
                .ignoresSafeArea()

            GeometryReader { geometry in
                let scale = geometry.size.width / Layout.referenceWidth
                let contentWidth = geometry.size.width
                let canvasHeight = Layout.referenceHeight * scale
                let canvasOffset = min(0, geometry.size.height - canvasHeight)

                ZStack(alignment: .top) {
                    // An absolute 402 × 874 design canvas preserves every
                    // Figma coordinate. On keyboard compression the complete
                    // canvas moves, so image, copy, input, and CTA stay in
                    // lockstep without resizing the image.
                    ZStack(alignment: .top) {
                        artwork(contentWidth: contentWidth, scale: scale)

                        header
                            .frame(
                                width: min(Layout.titleWidth * scale, contentWidth),
                                height: configuration.titleHeight * scale
                            )
                            .offset(y: configuration.titleTop * scale)

                        hatchNameField
                            .frame(
                                width: min(Layout.fieldWidth * scale, contentWidth),
                                height: Layout.fieldHeight * scale
                            )
                            .offset(y: configuration.fieldTop * scale)

                        createButton
                            .frame(
                                width: min(Layout.buttonWidth * scale, contentWidth),
                                height: Layout.buttonHeight * scale
                            )
                            .offset(y: configuration.buttonTop * scale)
                    }
                    .frame(width: contentWidth, height: canvasHeight, alignment: .top)
                    .offset(y: canvasOffset)

                    if style == .additionalHatch {
                        additionalChrome(scale: scale, contentWidth: contentWidth)
                            .offset(y: canvasOffset)
                    }
                }
            }
            // The canvas starts at the same top edge as the Figma iPhone
            // frame. Deliberately ignore only device container insets—never
            // the keyboard safe area.
            .ignoresSafeArea(.container)
        }
        .contentShape(Rectangle())
        .onTapGesture { isNameFocused = false }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text(configuration.title)
                .font(.system(size: 34, weight: .bold))
                .tracking(0.4)
                .lineSpacing(0)
                .foregroundStyle(Color.appGreenPrimary)
                .frame(
                    maxWidth: .infinity,
                    minHeight: configuration.titleTextHeight,
                    alignment: .top
                )

            Text(configuration.subtitle)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.appNeutralGray1)
                .frame(
                    maxWidth: .infinity,
                    minHeight: configuration.subtitleTextHeight,
                    alignment: .top
                )
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private func artwork(contentWidth: CGFloat, scale: CGFloat) -> some View {
        switch style {
        case .firstHatch:
            Image("TurtleHatchingOnboarding")
                .resizable()
                .scaledToFit()
                .frame(
                    width: contentWidth,
                    height: Layout.artworkHeight * scale
                )
                .accessibilityHidden(true)

        case .additionalHatch:
            HatcheryNewHatchHeroArtwork()
                .frame(
                    width: contentWidth,
                    height: Layout.artworkHeight * scale
                )
                .accessibilityHidden(true)
        }
    }

    private func additionalChrome(
        scale: CGFloat,
        contentWidth: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            Button {
                isNameFocused = false
                onBack?()
            } label: {
                HStack(spacing: 4) {
                    Text("Back")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "#0C7C4D"))
                .frame(width: 101 * scale, height: 44 * scale, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Back")

            Spacer(minLength: 0)

            HStack(spacing: 12 * scale) {
                chromeIcon(systemName: "bell", label: "Notifications", scale: scale)
                chromeIcon(systemName: "person", label: "Profile", scale: scale)
            }
            .frame(width: 156 * scale, height: 48 * scale)
        }
        .frame(
            width: max(0, contentWidth - 16 * scale),
            height: 48 * scale
        )
        .padding(.leading, 16 * scale)
        .padding(.top, 87 * scale)
    }

    private func chromeIcon(
        systemName: String,
        label: String,
        scale: CGFloat
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20 * scale, weight: .regular))
            .foregroundStyle(.black)
            .frame(width: 48 * scale, height: 48 * scale)
            .glassEffect(.regular, in: .circle)
            .accessibilityLabel(label)
    }

    private var hatchNameField: some View {
        VStack(spacing: 6) {
            TextField("", text: $hatchName, prompt: Text(configuration.defaultName))
                .font(.system(size: 28, weight: .bold))
                .tracking(0.38)
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isNameFocused)
                .onSubmit { isNameFocused = false }
                .frame(maxWidth: .infinity)
                .frame(height: 34)

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color(hex: "E6E6E6"))
                    .frame(height: 1)

                Text("Naming your hatch")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.appNeutralGray3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52, alignment: .top)
        }
    }

    private var createButton: some View {
        Button {
            onCreate(hatchName.trimmingCharacters(in: .whitespacesAndNewlines))
        } label: {
            Text(configuration.buttonTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "FAF8F4"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appGreenPrimary, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canContinue)
        .opacity(canContinue ? 1 : 0.5)
        .accessibilityHint(
            canContinue ? "Continues to hatchery scanning" : "Enter a hatch name to continue"
        )
    }
}

/// Figma's `image 20` asset is intentionally much wider than its 402 × 437
/// display container. These percentages reproduce its exact source crop from
/// node 82:792 rather than relying on a platform-dependent aspect-fill crop.
private struct HatcheryNewHatchHeroArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            Image("HatcheryNewHatchHero")
                .resizable()
                .frame(
                    width: geometry.size.width * 1.5846,
                    height: geometry.size.height * 1.0503
                )
                .offset(
                    x: -geometry.size.width * 0.4614,
                    y: -geometry.size.height * 0.0503
                )
        }
        .clipped()
    }
}

#Preview("First hatch · Figma reference", traits: .fixedLayout(width: 402, height: 874)) {
    CreateFirstHatchView()
}

#Preview("Additional hatch · Figma reference", traits: .fixedLayout(width: 402, height: 874)) {
    CreateFirstHatchView(style: .additionalHatch)
}
