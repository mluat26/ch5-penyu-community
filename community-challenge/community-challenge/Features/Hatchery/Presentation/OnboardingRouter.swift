import Observation

enum OnboardingRoute: Hashable {
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
final class OnboardingRouter {
    var path: [OnboardingRoute] = []

    func push(_ route: OnboardingRoute) {
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
