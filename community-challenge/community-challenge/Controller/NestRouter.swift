import Observation

enum NestRoute: Hashable {
    case scan
    case nestInfo
    case review
}

/// Typed SwiftUI navigation for the add-nest flow.
@MainActor
@Observable
final class NestRouter {
    var path: [NestRoute] = []

    func push(_ route: NestRoute) {
        path.append(route)
    }

    func reset() {
        path.removeAll()
    }
}
