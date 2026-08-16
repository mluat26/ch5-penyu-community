import Foundation

/// A freshly issued invite code. Short-lived and single-use by design: the
/// four-character code is only defensible because it expires in minutes and is
/// consumed the moment somebody redeems it.
struct OrganizationInviteEntity: Identifiable, Hashable, Sendable {
    let code: String
    let expiresAt: Date

    /// Codes are unique while live, so the code identifies the presentation.
    /// Regenerating produces a different code and therefore a fresh screen.
    var id: String { code }

    var hasExpired: Bool { expiresAt <= Date() }

    /// Whole minutes left, floored, never negative. Drives the countdown the
    /// invite screen shows so a person knows whether to read it out or
    /// generate a fresh one.
    var minutesRemaining: Int {
        max(0, Int(expiresAt.timeIntervalSinceNow / 60))
    }

    /// Figma renders the code as one box per character.
    var characters: [String] { code.map(String.init) }
}
