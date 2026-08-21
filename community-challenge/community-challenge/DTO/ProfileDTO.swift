import Foundation

/// Wire representation of `public.profile` — one row per authenticated user,
/// sharing its primary key with `auth.users`.
struct ProfileDTO: Codable, Sendable {
    let id: UUID
    let displayName: String?
    let appleEmail: String?
    let organizationID: UUID?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case appleEmail = "apple_email"
        case organizationID = "organization_id"
        case role
    }
}

extension ProfileDTO {
    func toEntity() throws -> ProfileEntity {
        guard let role else {
            throw DataMappingError.missingRequiredValue(field: "profile.role")
        }
        guard let parsedRole = OrganizationRole(rawValue: role) else {
            throw DataMappingError.missingRequiredValue(field: "profile.role (\(role))")
        }

        return ProfileEntity(
            id: id,
            displayName: displayName,
            appleEmail: appleEmail,
            organizationID: organizationID,
            role: parsedRole
        )
    }
}

/// The subset of `public.profile` this app is allowed to change. `role` and
/// `organization_id` are deliberately absent: a member must not be able to
/// promote themselves or move into another organization by writing the table.
struct ProfileUpdateDTO: Codable, Sendable {
    let displayName: String?
    let appleEmail: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case appleEmail = "apple_email"
    }
}

/// A row from `generate_organization_invite()`.
struct OrganizationInviteDTO: Codable, Sendable {
    let code: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case code
        case expiresAt = "expires_at"
    }
}

extension OrganizationInviteDTO {
    func toEntity() -> OrganizationInviteEntity {
        OrganizationInviteEntity(code: code, expiresAt: expiresAt)
    }
}

/// Parameters for `set_organization_member_role`.
struct SetMemberRoleDTO: Codable, Sendable {
    let memberID: UUID
    let newRole: String

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case newRole = "new_role"
    }
}

/// Parameters for `remove_organization_member`.
struct RemoveMemberDTO: Codable, Sendable {
    let memberID: UUID

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
    }
}

/// Parameters for `redeem_organization_invite`.
struct RedeemInviteDTO: Codable, Sendable {
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
    }
}
