import Observation

enum NestRoute: Hashable {
    /// The one screen ahead of the numbered stepper. NFC isn't wired up yet,
    /// so nothing here actually reads a tag; tapping the page is the
    /// placeholder for what will become an automatic advance once a bucket
    /// is detected.
    case connectBucket
    case identity
    /// The section grid is presented as a sheet rather than pushed, so it has
    /// no route: choosing a cell is a modal decision, not a step to go back to.
    case locationPicker
    case eggInformation
    case preview
    case success
    // Nest detail has no route: it is a sheet presented after this flow
    // closes, not another page pushed on top of it.
}

/// Typed SwiftUI navigation for the Add Nest flow.
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

    /// Returns to an earlier page, dropping everything stacked above it. A
    /// route that is not on the path leaves it untouched, so a stale tap
    /// cannot unwind the flow.
    func popTo(_ route: NestRoute) {
        guard let index = path.lastIndex(of: route) else { return }
        path.removeSubrange(path.index(after: index)...)
    }

    func replace(with route: NestRoute) {
        path = [route]
    }
}
