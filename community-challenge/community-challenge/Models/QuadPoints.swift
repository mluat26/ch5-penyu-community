import CoreGraphics

/// Four corner points describing the hatchery area.
///
/// The hatchery is **not** necessarily a rectangle — it is a free
/// quadrilateral whose corners can be dragged independently. Points are stored
/// in the coordinate space of whatever view is drawing them (e.g. the camera
/// preview). Normalization for persistence is handled separately by
/// `HatcheryBoundary` (Phase 4).
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
            topLeft:     CGPoint(x: w * 0.28, y: h * 0.30),
            topRight:    CGPoint(x: w * 0.72, y: h * 0.30),
            bottomRight: CGPoint(x: w * 0.82, y: h * 0.72),
            bottomLeft:  CGPoint(x: w * 0.18, y: h * 0.72)
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

    /// A quad is "simple" when non-adjacent edges do not cross — i.e. it is not
    /// a self-intersecting bow-tie. Adjacent corners must also keep a minimum
    /// separation so the shape can't collapse to a degenerate sliver.
    func isValid(minCornerSpacing: CGFloat = 24) -> Bool {
        // Edges: e0 = TL→TR, e1 = TR→BR, e2 = BR→BL, e3 = BL→TL.
        // Only non-adjacent pairs can create a self-intersection.
        if Self.segmentsIntersect(topLeft, topRight, bottomRight, bottomLeft) { return false }
        if Self.segmentsIntersect(topRight, bottomRight, bottomLeft, topLeft) { return false }

        // No two neighbouring corners collapsed onto each other.
        let edges = [
            (topLeft, topRight),
            (topRight, bottomRight),
            (bottomRight, bottomLeft),
            (bottomLeft, topLeft)
        ]
        for (a, b) in edges where Self.distance(a, b) < minCornerSpacing {
            return false
        }
        return true
    }

    // MARK: - Geometry helpers

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Do segments `p1p2` and `p3p4` intersect?
    private static func segmentsIntersect(
        _ p1: CGPoint, _ p2: CGPoint,
        _ p3: CGPoint, _ p4: CGPoint
    ) -> Bool {
        let d1 = orientation(p3, p4, p1)
        let d2 = orientation(p3, p4, p2)
        let d3 = orientation(p1, p2, p3)
        let d4 = orientation(p1, p2, p4)

        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
           ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }
        return false
    }

    /// Cross product sign of (b-a) × (c-a): >0 CCW, <0 CW, 0 collinear.
    private static func orientation(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
}
