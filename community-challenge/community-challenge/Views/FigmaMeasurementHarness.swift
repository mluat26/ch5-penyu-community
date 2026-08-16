import SwiftUI

#if DEBUG

/// Renders one Figma-backed screen full-bleed with the design's own sample
/// values, so a simulator screenshot can be diffed against the Figma export.
///
/// Driven by the `FIGMA_SCREEN` environment variable rather than a source
/// edit, so a measurement pass does not require touching the app entry point
/// between screens. Absent or unknown, the real app runs.
///
/// Fixture values are Figma's, not the database's: measuring against live data
/// would compare a different string's width and report drift that is not there.
enum FigmaMeasurementHarness {
    static var requestedScreen: String? {
        ProcessInfo.processInfo.environment["FIGMA_SCREEN"]
    }

    static var isActive: Bool { requestedScreen != nil }

    @ViewBuilder
    static func view(for screen: String) -> some View {
        switch screen {
        case "invite":
            InvitationCodeView(
                invite: OrganizationInviteEntity(
                    code: "3333",
                    expiresAt: Date().addingTimeInterval(600)
                ),
                onBack: {},
                onRegenerate: {}
            )

        case "join-empty":
            JoinWithCodeView(onJoin: { _ in }, onBack: {})

        default:
            Text("Unknown FIGMA_SCREEN “\(screen)”")
                .font(.system(size: 17, weight: .semibold))
        }
    }
}

#endif
