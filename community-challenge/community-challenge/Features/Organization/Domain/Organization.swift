import Foundation

struct Organization: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
}
