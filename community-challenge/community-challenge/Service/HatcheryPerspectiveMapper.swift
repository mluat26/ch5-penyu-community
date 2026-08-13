import CoreGraphics
import Foundation

/// Converts coordinates between the original hatchery photo and the
/// perspective-corrected rectangle produced from `HatcheryBoundary`.
///
/// The source image uses a normalized top-left origin, as do the rest of the
/// hatchery models. The corrected image is normalized to a unit rectangle.
/// Keeping this transform separate means the editable sand polygon can remain
/// in source-photo coordinates while every later screen renders the matching
/// corrected shape.
nonisolated struct HatcheryPerspectiveMapper {
    private static let unitSquare = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 1, y: 0),
        CGPoint(x: 1, y: 1),
        CGPoint(x: 0, y: 1),
    ]

    private let sourceToRectified: ProjectiveTransform
    private let rectifiedToSource: ProjectiveTransform

    init?(boundary: HatcheryBoundary) {
        guard boundary.isValid else { return nil }

        let sourcePoints = boundary.ordered.map(\.cgPoint)
        guard
            let sourceToRectified = ProjectiveTransform(
                source: sourcePoints,
                destination: Self.unitSquare
            ),
            let rectifiedToSource = ProjectiveTransform(
                source: Self.unitSquare,
                destination: sourcePoints
            )
        else {
            return nil
        }

        self.sourceToRectified = sourceToRectified
        self.rectifiedToSource = rectifiedToSource
    }

    func rectifiedPoint(forSource point: NormalizedPoint) -> CGPoint? {
        sourceToRectified.map(point.cgPoint)
    }

    func sourcePoint(forRectified point: NormalizedPoint) -> CGPoint? {
        rectifiedToSource.map(point.cgPoint)
    }

    /// Maps a source-photo polygon into the corrected image, clipping only the
    /// portion that lies within the corrected hatchery rectangle.
    func rectifiedRegion(for sourceRegion: HatcherySandRegion) -> HatcherySandRegion? {
        mappedRegion(sourceRegion, using: sourceToRectified)
    }

    /// The inverse used when a future screen needs to edit a corrected-image
    /// polygon while retaining the source-photo model as the source of truth.
    func sourceRegion(for rectifiedRegion: HatcherySandRegion) -> HatcherySandRegion? {
        mappedRegion(rectifiedRegion, using: rectifiedToSource)
    }

    private func mappedRegion(
        _ region: HatcherySandRegion,
        using transform: ProjectiveTransform
    ) -> HatcherySandRegion? {
        let mappedPoints = region.points.compactMap { transform.map($0.cgPoint) }
        guard mappedPoints.count == region.points.count else { return nil }

        return Self.region(clippingToUnitSquare: mappedPoints)
    }

    private static func region(clippingToUnitSquare points: [CGPoint]) -> HatcherySandRegion? {
        var clipped = points
        for edge in ClipEdge.allCases {
            clipped = clip(clipped, against: edge)
            guard clipped.count >= HatcherySandRegion.minimumPointCount else { return nil }
        }

        return HatcherySandRegion(
            points: simplifiedUnitPoints(clipped).map {
                NormalizedPoint(x: Double($0.x), y: Double($0.y))
            }
        )
    }

    private static func clip(_ points: [CGPoint], against edge: ClipEdge) -> [CGPoint] {
        guard let previous = points.last else { return [] }

        var output: [CGPoint] = []
        var previousPoint = previous
        var previousInside = edge.contains(previousPoint)

        for currentPoint in points {
            let currentInside = edge.contains(currentPoint)

            if currentInside != previousInside,
               let intersection = edge.intersection(from: previousPoint, to: currentPoint) {
                output.append(intersection)
            }
            if currentInside {
                output.append(currentPoint)
            }

            previousPoint = currentPoint
            previousInside = currentInside
        }

        return output
    }

    private static func simplifiedUnitPoints(_ points: [CGPoint]) -> [CGPoint] {
        let epsilon: CGFloat = 0.000_001
        var result: [CGPoint] = []

        for point in points {
            let clamped = CGPoint(
                x: min(max(point.x, 0), 1),
                y: min(max(point.y, 0), 1)
            )
            if let last = result.last,
               hypot(last.x - clamped.x, last.y - clamped.y) <= epsilon {
                continue
            }
            result.append(clamped)
        }

        if result.count > 1,
           let first = result.first,
           let last = result.last,
           hypot(first.x - last.x, first.y - last.y) <= epsilon {
            result.removeLast()
        }

        var removedPoint = true
        while removedPoint, result.count > HatcherySandRegion.minimumPointCount {
            removedPoint = false
            for index in result.indices {
                let previous = result[(index - 1 + result.count) % result.count]
                let current = result[index]
                let next = result[(index + 1) % result.count]
                let firstX = current.x - previous.x
                let firstY = current.y - previous.y
                let secondX = next.x - current.x
                let secondY = next.y - current.y
                let cross = firstX * secondY - firstY * secondX
                let dot = firstX * secondX + firstY * secondY

                if abs(cross) <= epsilon, dot >= 0 {
                    result.remove(at: index)
                    removedPoint = true
                    break
                }
            }
        }

        return result
    }
}

private extension HatcheryPerspectiveMapper {
    enum ClipEdge: CaseIterable {
        case left
        case right
        case top
        case bottom

        func contains(_ point: CGPoint) -> Bool {
            switch self {
            case .left: point.x >= 0
            case .right: point.x <= 1
            case .top: point.y >= 0
            case .bottom: point.y <= 1
            }
        }

        func intersection(from start: CGPoint, to end: CGPoint) -> CGPoint? {
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y

            switch self {
            case .left:
                guard deltaX != 0 else { return nil }
                let amount = -start.x / deltaX
                return CGPoint(x: 0, y: start.y + amount * deltaY)
            case .right:
                guard deltaX != 0 else { return nil }
                let amount = (1 - start.x) / deltaX
                return CGPoint(x: 1, y: start.y + amount * deltaY)
            case .top:
                guard deltaY != 0 else { return nil }
                let amount = -start.y / deltaY
                return CGPoint(x: start.x + amount * deltaX, y: 0)
            case .bottom:
                guard deltaY != 0 else { return nil }
                let amount = (1 - start.y) / deltaY
                return CGPoint(x: start.x + amount * deltaX, y: 1)
            }
        }
    }

    struct ProjectiveTransform {
        private let a: Double
        private let b: Double
        private let c: Double
        private let d: Double
        private let e: Double
        private let f: Double
        private let g: Double
        private let h: Double

        init?(source: [CGPoint], destination: [CGPoint]) {
            guard source.count == 4, destination.count == 4 else { return nil }

            var matrix: [[Double]] = []
            for (sourcePoint, destinationPoint) in zip(source, destination) {
                let x = Double(sourcePoint.x)
                let y = Double(sourcePoint.y)
                let u = Double(destinationPoint.x)
                let v = Double(destinationPoint.y)

                matrix.append([x, y, 1, 0, 0, 0, -u * x, -u * y, u])
                matrix.append([0, 0, 0, x, y, 1, -v * x, -v * y, v])
            }

            guard let values = Self.solve(matrix) else { return nil }
            a = values[0]
            b = values[1]
            c = values[2]
            d = values[3]
            e = values[4]
            f = values[5]
            g = values[6]
            h = values[7]
        }

        func map(_ point: CGPoint) -> CGPoint? {
            let x = Double(point.x)
            let y = Double(point.y)
            let denominator = g * x + h * y + 1
            guard denominator.isFinite, abs(denominator) > 0.000_000_001 else { return nil }

            let mappedX = (a * x + b * y + c) / denominator
            let mappedY = (d * x + e * y + f) / denominator
            guard mappedX.isFinite, mappedY.isFinite else { return nil }
            return CGPoint(x: mappedX, y: mappedY)
        }

        private static func solve(_ input: [[Double]]) -> [Double]? {
            guard input.count == 8, input.allSatisfy({ $0.count == 9 }) else { return nil }
            var matrix = input
            let epsilon = 0.000_000_000_1

            for column in 0..<8 {
                guard let pivotRow = (column..<8).max(by: {
                    abs(matrix[$0][column]) < abs(matrix[$1][column])
                }), abs(matrix[pivotRow][column]) > epsilon else {
                    return nil
                }

                if pivotRow != column {
                    matrix.swapAt(pivotRow, column)
                }

                let pivot = matrix[column][column]
                for index in column..<9 {
                    matrix[column][index] /= pivot
                }

                for row in 0..<8 where row != column {
                    let factor = matrix[row][column]
                    guard factor != 0 else { continue }
                    for index in column..<9 {
                        matrix[row][index] -= factor * matrix[column][index]
                    }
                }
            }

            return (0..<8).map { matrix[$0][8] }
        }
    }
}
