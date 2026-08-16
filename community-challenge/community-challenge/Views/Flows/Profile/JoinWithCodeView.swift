import SwiftUI

/// Figma 165:2740 (empty), 165:2765 (entering), 165:2791 (complete).
///
/// One screen with three states rather than three screens: the frames differ
/// only in whether the keyboard is up and whether the code is complete enough
/// to enable the button.
struct JoinWithCodeView: View {
    let onJoin: (String) async throws -> Void
    let onBack: () -> Void

    private enum Layout {
        static let referenceWidth: CGFloat = 402
        static let codeLength = 4
    }

    /// Matches the alphabet `generate_invite_code_text()` draws from, so a
    /// character that could never appear in a real code cannot be typed.
    private static let allowedCharacters = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    @State private var code = ""
    @State private var isJoining = false
    @State private var errorMessage: String?
    @FocusState private var isCodeFieldFocused: Bool

    private var isComplete: Bool { code.count == Layout.codeLength }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, geometry.size.width / Layout.referenceWidth)

            ZStack(alignment: .topLeading) {
                Color.white
                HatcheryWarmEllipse(scale: scale)
                    .offset(x: -110 * scale, y: -378 * scale)

                backButton(scale: scale)
                    .offset(x: 16 * scale, y: 72 * scale)

                header(scale: scale)
                    .offset(x: 40.5 * scale, y: 163 * scale)

                codeBoxes(scale: scale)
                    .offset(x: 30 * scale, y: 332 * scale)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 15 * scale, weight: .regular))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(width: 370 * scale)
                        .offset(x: 16 * scale, y: 452 * scale)
                }

                joinButton(scale: scale)
                    .offset(x: 16 * scale, y: 761 * scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            // Tapping anywhere returns to the code field, so the keyboard is
            // never stranded away from the only input on the screen.
            .contentShape(Rectangle())
            .onTapGesture { isCodeFieldFocused = true }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .onAppear { isCodeFieldFocused = true }
    }

    private func backButton(scale: CGFloat) -> some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17 * scale, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44 * scale, height: 44 * scale)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private func header(scale: CGFloat) -> some View {
        VStack(spacing: 12 * scale) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 28 * scale, weight: .regular))
                .foregroundStyle(Color.appGreenPrimary)
                .accessibilityHidden(true)

            Text("Invitation Code")
                .font(.system(size: 28 * scale, weight: .bold))
                .tracking(0.38 * scale)
                .foregroundStyle(Color.appGreenPrimary)

            Text("Enter the invite code to join your organization’s hatchery.")
                .font(.system(size: 17 * scale, weight: .regular))
                .foregroundStyle(Color.appNeutralGray1)
                .lineSpacing(2 * scale)
        }
        .multilineTextAlignment(.center)
        .frame(width: 321 * scale)
    }

    private func codeBoxes(scale: CGFloat) -> some View {
        ZStack {
            // The real input: one hidden field behind the boxes. Four separate
            // fields would fight each other over focus and break paste.
            TextField("", text: $code)
                .focused($isCodeFieldFocused)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(width: 342 * scale, height: 99 * scale)
                .onChange(of: code) { _, newValue in
                    code = Self.sanitize(newValue)
                    errorMessage = nil
                }

            HStack(spacing: 10 * scale) {
                ForEach(0..<Layout.codeLength, id: \.self) { index in
                    codeBox(at: index, scale: scale)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(width: 342 * scale, height: 99 * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Invite code")
        .accessibilityValue(code.isEmpty ? "Empty" : code.map(String.init).joined(separator: " "))
    }

    private func codeBox(at index: Int, scale: CGFloat) -> some View {
        let characters = Array(code)
        let character = index < characters.count ? String(characters[index]) : "3"
        let isFilled = index < characters.count

        return Text(character)
            .font(.system(size: 55 * scale, weight: .bold))
            .tracking(0.4 * scale)
            .foregroundStyle(Color(hex: "#0C7C4D").opacity(isFilled ? 1 : 0.2))
            .frame(width: 78 * scale, height: 99 * scale)
            .background(
                Color(hex: "#F1F1F1"),
                in: RoundedRectangle(cornerRadius: 16 * scale)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16 * scale)
                    .stroke(Color(hex: "#EBEBEB"), lineWidth: 1)
            }
    }

    private func joinButton(scale: CGFloat) -> some View {
        Button {
            Task { await join() }
        } label: {
            ZStack {
                Text("Join Hatchery")
                    .font(.system(size: 17 * scale, weight: .semibold))
                    .foregroundStyle(isComplete ? .white : Color(hex: "#8E8E93"))
                    .opacity(isJoining ? 0 : 1)

                if isJoining {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: 370 * scale, height: 55 * scale)
            .background(
                isComplete ? Color.appGreenPrimary : Color(hex: "#F2F2F7"),
                in: RoundedRectangle(cornerRadius: 26 * scale)
            )
            .contentShape(RoundedRectangle(cornerRadius: 26 * scale))
        }
        .buttonStyle(.plain)
        .disabled(!isComplete || isJoining)
    }

    /// Uppercases, drops anything outside the code alphabet, and caps the
    /// length — so a pasted code with stray spaces still lands correctly.
    private static func sanitize(_ value: String) -> String {
        String(
            value
                .uppercased()
                .filter { allowedCharacters.contains($0) }
                .prefix(Layout.codeLength)
        )
    }

    private func join() async {
        guard isComplete, !isJoining else { return }
        isJoining = true
        errorMessage = nil
        defer { isJoining = false }

        do {
            try await onJoin(code)
        } catch {
            // The database owns the reasons a code fails — expired, already
            // used, unknown — so surface its message rather than guessing.
            errorMessage = error.localizedDescription
            isCodeFieldFocused = true
        }
    }
}

#Preview("Join with code · Figma 165:2740", traits: .fixedLayout(width: 402, height: 874)) {
    JoinWithCodeView(onJoin: { _ in }, onBack: {})
}
