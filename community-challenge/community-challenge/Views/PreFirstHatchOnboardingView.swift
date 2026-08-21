import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

/// The two introductory Figma frames shown before a user creates their first
/// hatchery. Keeping this local to the empty-hatchery route means it naturally
/// disappears as soon as the real hatchery list becomes non-empty.
struct PreFirstHatchOnboardingView: View {
    private enum Step {
        case welcome
        case start
    }

    private enum Layout {
        static let referenceWidth: CGFloat = 402
        static let referenceHeight: CGFloat = 874
    }

    let onCreateHatchery: () -> Void
    /// Token, nonce, and the full name Apple supplies. That name arrives only
    /// on a person's very first authorization and never again, so it has to be
    /// captured here or it is lost for good.
    let onSignInWithApple: (String, String, String?) async throws -> Void
    /// Redeems an invite code and joins that organization. Throws so the join
    /// screen can show the database's own reason for refusing a code.
    var onJoinWithCode: ((String) async throws -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = Step.welcome
    @State private var isShowingJoinWithCode = false
    /// Only reachable when no join handler was supplied, so the button still
    /// explains itself rather than doing nothing.
    @State private var isShowingJoinUnavailableAlert = false
    @State private var appleSignIn = AppleSignInCoordinator()
    @State private var rawAppleNonce: String?
    @State private var isSigningInWithApple = false
    @State private var appleSignInError: String?
    @State private var isShowingAppleSignInError = false

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, geometry.size.width / Layout.referenceWidth)
            let canvasWidth = Layout.referenceWidth * scale
            let canvasHeight = Layout.referenceHeight * scale
            let canvasX = max((geometry.size.width - canvasWidth) / 2, 0)

            ZStack(alignment: .topLeading) {
                Color.white

                // Figma's pre-onboarding ellipse sits 20pt lower than the
                // hatchery/setup screens. The shared component preserves the
                // exact 621pt shape, #FFF5ED fill, and 50pt blur.
                HatcheryWarmEllipse(scale: scale)
                    .offset(x: -110 * scale, y: -358 * scale)

                ZStack(alignment: .topLeading) {
                    switch step {
                    case .welcome:
                        welcomeCanvas(scale: scale)
                            .transition(.opacity)

                    case .start:
                        startCanvas(scale: scale)
                            .transition(.opacity)
                    }
                }
                .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
                .clipped()
                .offset(x: canvasX)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $isShowingJoinWithCode) {
            if let onJoinWithCode {
                JoinWithCodeView(
                    onJoin: { code in
                        try await onJoinWithCode(code)
                        isShowingJoinWithCode = false
                    },
                    onBack: { isShowingJoinWithCode = false }
                )
            }
        }
        .alert("Join with code", isPresented: $isShowingJoinUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Joining an existing hatchery with an invite code is not available yet.")
        }
        .alert("Sign in with Apple", isPresented: $isShowingAppleSignInError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appleSignInError ?? "Sign in could not be completed. Please try again.")
        }
    }

    private func welcomeCanvas(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            PreFirstHatchWelcomeArtwork()
                .frame(width: 402 * scale, height: 437 * scale)
                .offset(y: 20 * scale)
                .accessibilityHidden(true)

            introCopy(
                title: "Welcome to\nTurterra",
                subtitle: "Protect every nest\nfrom egg to hatchling.",
                titleHeight: 82,
                scale: scale
            )
            .offset(x: 50 * scale, y: 443 * scale)

            appleSignInButton(scale: scale)
                .offset(x: 16 * scale, y: 762 * scale)
        }
    }

    /// Figma 153:1995. `SignInWithAppleButton` scales its own label to the
    /// button's height, so a 55pt-tall system button renders text far larger
    /// than this design's 17pt. Drawing the button keeps Figma's exact metrics
    /// while `ASAuthorizationController` still runs Apple's real sheet. The
    /// styling stays within Apple's guidance: black fill, the Apple mark, and
    /// the unmodified "Sign in with Apple" wording.
    private func appleSignInButton(scale: CGFloat) -> some View {
        Button(action: startAppleSignIn) {
            HStack(spacing: 5 * scale) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 22 * scale, weight: .regular))
                    .frame(width: 20 * scale, height: 28 * scale)

                // No explicit `tracking`: SF Pro already applies Figma's
                // Body letter spacing (-0.43) natively at 17pt, so setting it
                // again renders the label measurably tighter than the design.
                Text("Sign in with Apple")
                    .font(.system(size: 17 * scale, weight: .semibold))
                    .frame(height: 22 * scale)
            }
            .foregroundStyle(Color(hex: "#FAF8F4"))
            .frame(width: 370 * scale, height: 55 * scale)
            .background(.black, in: RoundedRectangle(cornerRadius: 26 * scale))
            .contentShape(RoundedRectangle(cornerRadius: 26 * scale))
        }
        .buttonStyle(.plain)
        .disabled(isSigningInWithApple)
        .overlay {
            if isSigningInWithApple {
                ProgressView()
                    .tint(.white)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Sign in with Apple")
        .accessibilityHint("Signs in with your Apple ID")
    }

    private func startAppleSignIn() {
        let nonce = AppleSignInNonce.make()
        rawAppleNonce = nonce

        appleSignIn.requestAuthorization(
            hashedNonce: AppleSignInNonce.sha256(nonce)
        ) { result in
            Task { @MainActor in
                await handleAppleAuthorization(result)
            }
        }
    }

    private func startCanvas(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("HatcheryManagementHero")
                .resizable()
                .scaledToFill()
                .frame(width: 496 * scale, height: 278 * scale)
                .clipped()
                .offset(x: -47 * scale, y: 165 * scale)
                .accessibilityHidden(true)

            introCopy(
                title: "Let’s get started",
                subtitle: "Create a new hatchery or\njoin an existing one.",
                titleHeight: 41,
                scale: scale
            )
            .offset(x: 50 * scale, y: 443 * scale)

            VStack(spacing: 10 * scale) {
                startOption(
                    systemImage: "plus.viewfinder",
                    title: "Create a hatchery",
                    subtitle: "Set up a new hatchery",
                    scale: scale,
                    action: onCreateHatchery
                )

                startOption(
                    systemImage: "qrcode",
                    title: "Join with code",
                    subtitle: "Enter invite code to join",
                    scale: scale,
                    action: {
                        if onJoinWithCode == nil {
                            isShowingJoinUnavailableAlert = true
                        } else {
                            isShowingJoinWithCode = true
                        }
                    }
                )
            }
            .offset(x: 16 * scale, y: 596 * scale)
        }
    }

    private func introCopy(
        title: String,
        subtitle: String,
        titleHeight: CGFloat,
        scale: CGFloat
    ) -> some View {
        VStack(spacing: 12 * scale) {
            Text(title)
                .font(.system(size: 34 * scale, weight: .bold))
                .lineSpacing(0)
                .foregroundStyle(Color.appGreenPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: titleHeight * scale, alignment: .top)

            Text(subtitle)
                .font(.system(size: 17 * scale, weight: .regular))
                .foregroundStyle(Color.appNeutralGray1)
                .lineSpacing(2 * scale)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 44 * scale, alignment: .top)
        }
        .multilineTextAlignment(.center)
        .frame(width: 287 * scale, alignment: .top)
        .frame(width: 303 * scale, alignment: .center)
    }

    private func startOption(
        systemImage: String,
        title: String,
        subtitle: String,
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            // Figma 153:2013 places the icon box at x17 (41×41) and the text
            // block at x93.75, so only the icon-to-text gap is 35.75. It has
            // to be padding rather than HStack spacing, which would also apply
            // either side of the Spacer and overflow the 370pt row.
            HStack(spacing: 0) {
                Image(systemName: systemImage)
                    .font(.system(size: 34 * scale, weight: .regular))
                    .foregroundStyle(Color.appGreenPrimary)
                    .frame(width: 41 * scale, height: 41 * scale)

                VStack(alignment: .leading, spacing: 7 * scale) {
                    Text(title)
                        .font(.system(size: 17 * scale, weight: .semibold))
                        .foregroundStyle(Color(hex: "#2A2A2A"))

                    Text(subtitle)
                        .font(.system(size: 13 * scale, weight: .bold))
                        .foregroundStyle(Color.appNeutralGray1)
                }
                .frame(width: 215.5 * scale, alignment: .leading)
                .padding(.leading, 35.75 * scale)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17 * scale, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(width: 8 * scale, height: 22 * scale)
            }
            .padding(.horizontal, 17 * scale)
            .frame(width: 370 * scale, height: 81 * scale)
            .background(
                Color(hex: "#F1F1F1"),
                in: RoundedRectangle(cornerRadius: 24 * scale)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24 * scale)
                    .stroke(Color(hex: "#EBEBEB"), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 24 * scale))
        }
        .buttonStyle(.plain)
        .frame(width: 370 * scale, height: 81 * scale)
        .accessibilityHint(title == "Create a hatchery"
            ? "Begins first hatchery setup"
            : "Explains how to join an existing hatchery")
    }

    private func showStartStep() {
        if reduceMotion {
            step = .start
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                step = .start
            }
        }
    }

    private func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) async {
        defer { rawAppleNonce = nil }

        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let identityToken = credential.identityToken,
                let token = String(data: identityToken, encoding: .utf8),
                let rawAppleNonce
            else {
                presentAppleSignInError(AppleSignInError.missingIdentityToken)
                return
            }

            isSigningInWithApple = true
            defer { isSigningInWithApple = false }

            do {
                try await onSignInWithApple(
                    token,
                    rawAppleNonce,
                    Self.formattedName(from: credential.fullName)
                )
                showStartStep()
            } catch {
                guard !Task.isCancelled else { return }
                presentAppleSignInError(error)
            }

        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            presentAppleSignInError(error)
        }
    }

    private func presentAppleSignInError(_ error: Error) {
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            return
        }

        appleSignInError = error.localizedDescription
        isShowingAppleSignInError = true
    }
}

/// Runs Apple's real authorization sheet for the Figma-styled button, since a
/// hand-drawn button cannot use `SignInWithAppleButton`'s built-in request.
@MainActor
private final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var onCompletion: ((Result<ASAuthorization, Error>) -> Void)?

    func requestAuthorization(
        hashedNonce: String,
        onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void
    ) {
        self.onCompletion = onCompletion

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated { finish(.success(authorization)) }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            guard
                let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })?
                    .keyWindow
            else {
                preconditionFailure("Apple sign-in was started without a foreground window.")
            }
            return window
        }
    }

    /// Clears the stored handler before invoking it so a delegate callback
    /// cannot be delivered twice for one authorization.
    private func finish(_ result: Result<ASAuthorization, Error>) {
        let completion = onCompletion
        onCompletion = nil
        completion?(result)
    }
}

extension PreFirstHatchOnboardingView {
    /// Apple hands back name components, not a string, and omits them for a
    /// returning user. Returns nil rather than an empty string so a repeat
    /// sign-in never blanks a name the person already set.
    static func formattedName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatted = PersonNameComponentsFormatter.localizedString(
            from: components,
            style: .default
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }
}

private enum AppleSignInError: LocalizedError {
    case missingIdentityToken

    var errorDescription: String? {
        "Apple did not return a valid sign-in token. Please try again."
    }
}

/// Supabase verifies the nonce returned in Apple's ID token. Apple receives
/// only the SHA-256 hash; the original stays on-device for the token exchange.
private enum AppleSignInNonce {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

    static func make(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        guard status == errSecSuccess else {
            // This system API should never fail on a supported device. UUIDs
            // still give the authorization request a high-entropy fallback
            // rather than sending a request without nonce protection.
            return UUID().uuidString + UUID().uuidString
        }

        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Figma's `image 19` is a transparent image that is intentionally wider
/// than its 402 × 437pt display container. These source-crop values come
/// directly from node 119:3271, so the art is never re-encoded or zoomed.
private struct PreFirstHatchWelcomeArtwork: View {
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

#Preview("Welcome · Figma 119:3271", traits: .fixedLayout(width: 402, height: 874)) {
    PreFirstHatchOnboardingView(
        onCreateHatchery: {},
        onSignInWithApple: { _, _, _ in }
    )
}
