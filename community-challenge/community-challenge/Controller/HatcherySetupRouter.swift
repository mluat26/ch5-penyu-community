import Observation

enum HatcherySetupRoute: Hashable {
    case scan
    case camera
    case adjustBoundary
    case dimensions
    case preview
}

/// Typed SwiftUI navigation for hatchery setup. This is a UI router, not an
/// HTTP backend router.
@MainActor
@Observable
final class HatcherySetupRouter {
    var path: [HatcherySetupRoute] = []

    func push(_ route: HatcherySetupRoute) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func restartCamera() {
        path = [.scan, .camera]
    }
}
