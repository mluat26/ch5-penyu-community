import Foundation

/// A member's role inside their organization. The database stores this as the
/// `public.org_role` enum, so the raw values must stay in step with it.
enum OrganizationRole: String, Codable, CaseIterable, Sendable {
    case manager
    case coordinator
    case officer
    case agent

    /// Shown to a person, so it is translated. Deliberately separate from
    /// `rawValue`, which is the `public.org_role` value the database stores
    /// and must never change with the reader's language.
    ///
    /// `String(localized:)` rather than `LocalizedStringKey`: the latter is a
    /// SwiftUI type, and an entity has no business importing SwiftUI to name
    /// a role. Both are read by the same extractor.
    var displayName: String {
        switch self {
        case .manager: String(localized: "Manager")
        case .coordinator: String(localized: "Coordinator")
        case .officer: String(localized: "Officer")
        case .agent: String(localized: "Agent")
        }
    }

    /// Only a manager may issue invite codes. The database enforces this too;
    /// this exists so the UI can hide an action that would be refused.
    var canGenerateInviteCode: Bool { self == .manager }

    /// The roles an owner may hand out. `agent` is absent because it means
    /// "belongs to no organization" — that is what removing a member does, and
    /// `set_organization_member_role` refuses it for the same reason.
    static var assignable: [OrganizationRole] { allCases.filter { $0 != .agent } }
}

/// The signed-in person and their organization membership.
///
/// Apple returns a full name only on a person's very first authorization, so
/// `displayName` is captured then and stored — it cannot be re-read later.
struct ProfileEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    var displayName: String?
    var appleEmail: String?
    var organizationID: UUID?
    var role: OrganizationRole
}
