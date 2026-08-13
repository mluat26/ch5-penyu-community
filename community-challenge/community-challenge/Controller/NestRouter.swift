import Observation

enum NestRoute: Hashable {
    case identity
    case sectionPicker
    case eggInformation
    case preview
    case success
    case sectionOverview(section: HatcherySectionDashboard)
    case nestDetail(
        item: NestDashboardItem,
        ordinal: Int,
        sectionID: String
    )
}

/// Typed SwiftUI navigation for hatchery and nest screens.
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

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func replace(with route: NestRoute) {
        path = [route]
    }
}
