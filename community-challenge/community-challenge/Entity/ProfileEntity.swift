import Foundation

/// A member's role inside their organization. The database stores this as the
/// `public.org_role` enum, so the raw values must stay in step with it.
enum OrganizationRole: String, Codable, CaseIterable, Sendable {
    case manager
    case coordinator
    case officer
    case agent

    var displayName: String {
        switch self {
        case .manager: "Manager"
        case .coordinator: "Coordinator"
        case .officer: "Officer"
        case .agent: "Agent"
        }
    }

    /// Only a manager may issue invite codes. The database enforces this too;
    /// this exists so the UI can hide an action that would be refused.
    var canGenerateInviteCode: Bool { self == .manager }
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
