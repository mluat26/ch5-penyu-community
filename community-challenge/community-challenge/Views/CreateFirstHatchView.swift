import SwiftUI

struct CreateFirstHatchView: View {

    /// Design-tuning knobs for the turtle artwork over the gradient.
    private static let artworkOffsetX: CGFloat = 0
    private static let artworkOffsetY: CGFloat = 0

    @State private var hatchName: String = ""
    @FocusState private var isNameFocused: Bool

    var onCreate: (String) -> Void = { _ in }

    private var canContinue: Bool {
        !hatchName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    var body: some View {
        ZStack {

            // MARK: - Background

            Image("BGHatchery")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Turtle artwork sits on top of the gradient, pinned to the top
            // edge at full width. Nudge with the two offsets below.
            GeometryReader { geometry in
                Image("TurtleHatchingOnboarding")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width)
                    .offset(x: Self.artworkOffsetX, y: Self.artworkOffsetY)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // MARK: - Content

            VStack(spacing: 0) {

                Spacer(minLength: 0)

                // MARK: - Header

                VStack(spacing: 12) {
                    Text("Create your first hatch")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appGreenPrimary)

                    Text("Name your first turtle egg incubator hatch")
                        .font(.body)
                        .foregroundStyle(Color.appNeutralGray1)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 360)

                Spacer()

                // MARK: - Hatch Name Input

                VStack(spacing: 8) {

                    // Large typed text
                    TextField(
                        "",
                        text: $hatchName
                    )
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.appNeutralBlack)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit {
                        isNameFocused = false
                    }
                    .frame(height: 50)

                    Rectangle()
                        .fill(Color.appNeutralGray3)
                        .frame(height: 1)

                    // Static caption below the line
                    Text("Naming your hatch")
                        .foregroundStyle(Color.appNeutralGray1)
                        .font(.body)
                }
                .padding(.horizontal, 32)

                Spacer()
                Spacer()

                // MARK: - Create Button

                Button {
                    let trimmedName = hatchName
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    onCreate(trimmedName)
                } label: {
                    Text("Create a hatch")
                        .font(.headline)
                        .foregroundStyle(Color.appOffWhite)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            Capsule()
                                .fill(Color.appGreenPrimary)
                                .opacity(canContinue ? 1.0 : 0.5)
                        )
                }
                .disabled(!canContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        // Tapping anywhere outside the field dismisses the keyboard.
        .contentShape(Rectangle())
        .onTapGesture {
            isNameFocused = false
        }
    }
}

#Preview {
    CreateFirstHatchView()
}
