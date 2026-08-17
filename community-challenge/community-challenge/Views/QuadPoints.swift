import CoreGraphics

/// Four corner points describing the hatchery area.
///
/// The hatchery is **not** necessarily a rectangle — it is a free
/// quadrilateral whose corners can be dragged independently. Points are stored
/// in the coordinate space of whatever view is drawing them (e.g. the camera
/// preview). Normalization for persistence is handled separately by
/// `HatcheryBoundary` before the result leaves the scan flow.
struct QuadPoints: Equatable {

    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    // MARK: - Corner addressing

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomRight, bottomLeft
    }

    subscript(corner: Corner) -> CGPoint {
        get {
            switch corner {
            case .topLeft: return topLeft
            case .topRight: return topRight
            case .bottomRight: return bottomRight
            case .bottomLeft: return bottomLeft
            }
        }
        set {
            switch corner {
            case .topLeft: topLeft = newValue
            case .topRight: topRight = newValue
            case .bottomRight: bottomRight = newValue
            case .bottomLeft: bottomLeft = newValue
            }
        }
    }

    /// Corners in draw order (clockwise starting top-left).
    var ordered: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    func withCorner(_ corner: Corner, at point: CGPoint) -> QuadPoints {
        var copy = self
        copy[corner] = point
        return copy
    }

    // MARK: - Defaults

    /// A perspective trapezoid (wider at the bottom, like looking down at the
    /// hatchery) sized to a container. Matches the reference framing.
    static func defaultShape(in size: CGSize) -> QuadPoints {
        let w = size.width
        let h = size.height
        return QuadPoints(
            topLeft:     CGPoint(x: w * 0.2788, y: h * 0.2997),
            topRight:    CGPoint(x: w * 0.7062, y: h * 0.2997),
            bottomRight: CGPoint(x: w * 0.8370, y: h * 0.6740),
            bottomLeft:  CGPoint(x: w * 0.1704, y: h * 0.6740)
        )
    }

    // MARK: - Bounds

    /// Clamps a candidate point so a corner cannot leave the container,
    /// keeping a `margin` so the handle stays fully visible.
    static func clamp(_ point: CGPoint, in size: CGSize, margin: CGFloat) -> CGPoint {
        CGPoint(
            x: min(max(point.x, margin), size.width - margin),
            y: min(max(point.y, margin), size.height - margin)
        )
    }

    // MARK: - Validity

    /// A valid editing boundary is convex and has four separated corners.
    func isValid(minCornerSpacing: CGFloat = 24) -> Bool {
        let points = ordered
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            if Self.distance(points[index], next) < minCornerSpacing {
                return false
            }
        }

        let turns = points.indices.map { index in
            Self.orientation(
                points[index],
                points[(index + 1) % points.count],
                points[(index + 2) % points.count]
            )
        }
        let epsilon: CGFloat = 0.5
        if turns.contains(where: { abs($0) <= epsilon }) {
            return false
        }
        return turns.allSatisfy { $0 > 0 } || turns.allSatisfy { $0 < 0 }
    }

    // MARK: - Geometry helpers

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Cross product sign of (b-a) × (c-a): >0 CCW, <0 CW, 0 collinear.
    private static func orientation(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
}
