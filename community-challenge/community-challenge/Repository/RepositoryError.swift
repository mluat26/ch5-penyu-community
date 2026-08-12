import Foundation

enum RepositoryError: Error, LocalizedError, Sendable {
    case notFound(resource: String, id: UUID)

    var errorDescription: String? {
        switch self {
        case let .notFound(resource, id):
            "\(resource) \(id.uuidString) was not found."
        }
    }
}
