import CoreGraphics
import Foundation
import UIKit

nonisolated struct NormalizedPoint: Codable, Hashable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    var cgPoint: CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}

/// A four-corner hatchery boundary stored relative to the source image.
/// Values stay in the 0...1 range, so the boundary survives layout and device changes.
nonisolated struct HatcheryBoundary: Codable, Hashable {
    var topLeft: NormalizedPoint
    var topRight: NormalizedPoint
    var bottomRight: NormalizedPoint
    var bottomLeft: NormalizedPoint

    static let fullImage = HatcheryBoundary(
        topLeft: NormalizedPoint(x: 0, y: 0),
        topRight: NormalizedPoint(x: 1, y: 0),
        bottomRight: NormalizedPoint(x: 1, y: 1),
        bottomLeft: NormalizedPoint(x: 0, y: 1)
    )

    /// The valid initial framing used when the camera has no detected boundary.
    static let defaultSuggestion = HatcheryBoundary(
        topLeft: NormalizedPoint(x: 0.2788, y: 0.2997),
        topRight: NormalizedPoint(x: 0.7062, y: 0.2997),
        bottomRight: NormalizedPoint(x: 0.8370, y: 0.6740),
        bottomLeft: NormalizedPoint(x: 0.1704, y: 0.6740)
    )

    var ordered: [NormalizedPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    func point(columnFraction u: Double, rowFraction v: Double) -> NormalizedPoint {
        let clampedU = min(max(u, 0), 1)
        let clampedV = min(max(v, 0), 1)
        let top = Self.interpolate(topLeft, topRight, amount: clampedU)
        let bottom = Self.interpolate(bottomLeft, bottomRight, amount: clampedU)
        return Self.interpolate(top, bottom, amount: clampedV)
    }

    func sectionBoundary(
        row: Int,
        column: Int,
        rowCount: Int,
        columnCount: Int
    ) -> HatcheryBoundary {
        let left = Double(column) / Double(max(columnCount, 1))
        let right = Double(column + 1) / Double(max(columnCount, 1))
        let top = Double(row) / Double(max(rowCount, 1))
        let bottom = Double(row + 1) / Double(max(rowCount, 1))

        return HatcheryBoundary(
            topLeft: point(columnFraction: left, rowFraction: top),
            topRight: point(columnFraction: right, rowFraction: top),
            bottomRight: point(columnFraction: right, rowFraction: bottom),
            bottomLeft: point(columnFraction: left, rowFraction: bottom)
        )
    }

    /// Prevents folded or collapsed projections before grid generation.
    var isValid: Bool {
        let points = ordered.map(\.cgPoint)
        let signedTurns = points.indices.map { index -> CGFloat in
            let a = points[index]
            let b = points[(index + 1) % points.count]
            let c = points[(index + 2) % points.count]
            return Self.cross(a, b, c)
        }

        let epsilon: CGFloat = 0.0005
        guard signedTurns.allSatisfy({ abs($0) > epsilon }) else { return false }
        let allClockwise = signedTurns.allSatisfy { $0 < 0 }
        let allCounterClockwise = signedTurns.allSatisfy { $0 > 0 }
        guard allClockwise || allCounterClockwise else { return false }

        let doubledArea = points.indices.reduce(CGFloat.zero) { partial, index in
            let nextIndex = (index + 1) % points.count
            return partial
                + points[index].x * points[nextIndex].y
                - points[nextIndex].x * points[index].y
        }
        return abs(doubledArea) * 0.5 > 0.01
    }

    private static func interpolate(
        _ start: NormalizedPoint,
        _ end: NormalizedPoint,
        amount: Double
    ) -> NormalizedPoint {
        NormalizedPoint(
            x: start.x + (end.x - start.x) * amount,
            y: start.y + (end.y - start.y) * amount
        )
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
    }
}

/// The usable sand footprint within a hatchery image.
///
/// The four-point `HatcheryBoundary` remains the perspective plane used to
/// project a rectangular grid. This polygon is intentionally separate: it can
/// describe concave or otherwise irregular sand areas and decides which grid
/// sections are usable.
nonisolated struct HatcherySandRegion: Codable, Hashable {
    static let minimumPointCount = 3
    static let maximumPointCount = 12

    let points: [NormalizedPoint]

    init?(points: [NormalizedPoint]) {
        guard Self.isSimplePolygon(points) else { return nil }
        self.points = points
    }

    init(boundary: HatcheryBoundary) {
        self.points = boundary.ordered
    }

    static func `default`(from boundary: HatcheryBoundary) -> HatcherySandRegion {
        HatcherySandRegion(boundary: boundary)
    }

    var isValid: Bool {
        Self.isSimplePolygon(points)
    }

    /// Uses an even-odd ray test and treats the perimeter as part of the
    /// region, so a grid center exactly on the sand boundary stays usable.
    func contains(point: NormalizedPoint) -> Bool {
        guard isValid else { return false }

        for index in points.indices {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            if Self.isOnSegment(point, start, end) {
                return true
            }
        }

        var inside = false
        var previous = points[points.count - 1]
        for current in points {
            let crossesHorizontalRay = (current.y > point.y) != (previous.y > point.y)
            if crossesHorizontalRay {
                let intersectionX = (previous.x - current.x)
                    * (point.y - current.y)
                    / (previous.y - current.y)
                    + current.x
                if point.x < intersectionX {
                    inside.toggle()
                }
            }
            previous = current
        }
        return inside
    }

    func contains(_ point: NormalizedPoint) -> Bool {
        contains(point: point)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decodedPoints = try container.decode([NormalizedPoint].self)
        guard let region = HatcherySandRegion(points: decodedPoints) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Hatchery sand regions must be simple polygons with 3...12 points."
            )
        }
        self = region
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(points)
    }

    private static let epsilon = 0.000_001

    private static func isSimplePolygon(_ points: [NormalizedPoint]) -> Bool {
        guard (minimumPointCount...maximumPointCount).contains(points.count) else {
            return false
        }
        guard points.allSatisfy({
            $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
        }) else {
            return false
        }
        guard abs(signedArea(of: points)) > epsilon else { return false }

        for firstIndex in points.indices {
            for secondIndex in points.indices where secondIndex > firstIndex {
                guard squaredDistance(points[firstIndex], points[secondIndex]) > epsilon * epsilon else {
                    return false
                }
            }
        }

        for index in points.indices {
            let previous = points[(index - 1 + points.count) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            if isBacktracking(previous, current, next) {
                return false
            }
        }

        for firstEdge in points.indices {
            let firstStart = points[firstEdge]
            let firstEnd = points[(firstEdge + 1) % points.count]

            for secondEdge in (firstEdge + 1)..<points.count {
                guard !areAdjacent(firstEdge, secondEdge, count: points.count) else { continue }

                let secondStart = points[secondEdge]
                let secondEnd = points[(secondEdge + 1) % points.count]
                if segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd) {
                    return false
                }
            }
        }
        return true
    }

    private static func signedArea(of points: [NormalizedPoint]) -> Double {
        points.indices.reduce(0) { area, index in
            let current = points[index]
            let next = points[(index + 1) % points.count]
            return area + current.x * next.y - next.x * current.y
        } * 0.5
    }

    private static func areAdjacent(_ first: Int, _ second: Int, count: Int) -> Bool {
        abs(first - second) == 1 || (first == 0 && second == count - 1)
    }

    private static func isBacktracking(
        _ previous: NormalizedPoint,
        _ current: NormalizedPoint,
        _ next: NormalizedPoint
    ) -> Bool {
        let firstX = current.x - previous.x
        let firstY = current.y - previous.y
        let secondX = next.x - current.x
        let secondY = next.y - current.y
        let cross = firstX * secondY - firstY * secondX
        let dot = firstX * secondX + firstY * secondY
        return abs(cross) <= epsilon && dot < 0
    }

    private static func segmentsIntersect(
        _ firstStart: NormalizedPoint,
        _ firstEnd: NormalizedPoint,
        _ secondStart: NormalizedPoint,
        _ secondEnd: NormalizedPoint
    ) -> Bool {
        let first = cross(firstStart, firstEnd, secondStart)
        let second = cross(firstStart, firstEnd, secondEnd)
        let third = cross(secondStart, secondEnd, firstStart)
        let fourth = cross(secondStart, secondEnd, firstEnd)

        if abs(first) <= epsilon && isOnSegment(secondStart, firstStart, firstEnd) { return true }
        if abs(second) <= epsilon && isOnSegment(secondEnd, firstStart, firstEnd) { return true }
        if abs(third) <= epsilon && isOnSegment(firstStart, secondStart, secondEnd) { return true }
        if abs(fourth) <= epsilon && isOnSegment(firstEnd, secondStart, secondEnd) { return true }

        return (first > epsilon && second < -epsilon || first < -epsilon && second > epsilon)
            && (third > epsilon && fourth < -epsilon || third < -epsilon && fourth > epsilon)
    }

    private static func isOnSegment(
        _ point: NormalizedPoint,
        _ start: NormalizedPoint,
        _ end: NormalizedPoint
    ) -> Bool {
        guard abs(cross(start, end, point)) <= epsilon else { return false }
        return point.x >= min(start.x, end.x) - epsilon
            && point.x <= max(start.x, end.x) + epsilon
            && point.y >= min(start.y, end.y) - epsilon
            && point.y <= max(start.y, end.y) + epsilon
    }

    private static func cross(
        _ start: NormalizedPoint,
        _ end: NormalizedPoint,
        _ point: NormalizedPoint
    ) -> Double {
        (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x)
    }

    private static func squaredDistance(_ first: NormalizedPoint, _ second: NormalizedPoint) -> Double {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return deltaX * deltaX + deltaY * deltaY
    }
}

/// Converts points between an aspect-filled image and its SwiftUI container.
nonisolated struct AspectFillImageMapper {
    let imageSize: CGSize
    let containerSize: CGSize

    private var scale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return max(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
    }

    private var origin: CGPoint {
        let renderedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGPoint(
            x: (containerSize.width - renderedSize.width) / 2,
            y: (containerSize.height - renderedSize.height) / 2
        )
    }

    func viewPoint(for point: NormalizedPoint) -> CGPoint {
        CGPoint(
            x: origin.x + CGFloat(point.x) * imageSize.width * scale,
            y: origin.y + CGFloat(point.y) * imageSize.height * scale
        )
    }

    func normalizedPoint(for viewPoint: CGPoint) -> NormalizedPoint {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NormalizedPoint(x: 0.5, y: 0.5)
        }
        return NormalizedPoint(
            x: Double((viewPoint.x - origin.x) / (imageSize.width * scale)),
            y: Double((viewPoint.y - origin.y) / (imageSize.height * scale))
        )
    }

    func viewQuad(for boundary: HatcheryBoundary) -> QuadPoints {
        QuadPoints(
            topLeft: viewPoint(for: boundary.topLeft),
            topRight: viewPoint(for: boundary.topRight),
            bottomRight: viewPoint(for: boundary.bottomRight),
            bottomLeft: viewPoint(for: boundary.bottomLeft)
        )
    }

    func boundary(for quad: QuadPoints) -> HatcheryBoundary {
        HatcheryBoundary(
            topLeft: normalizedPoint(for: quad.topLeft),
            topRight: normalizedPoint(for: quad.topRight),
            bottomRight: normalizedPoint(for: quad.bottomRight),
            bottomLeft: normalizedPoint(for: quad.bottomLeft)
        )
    }
}

nonisolated struct HatcheryDimension: Hashable {
    var widthM: Double
    var heightM: Double

    var validationMessage: String? {
        guard widthM.isFinite, heightM.isFinite, widthM > 0, heightM > 0 else {
            return "Enter a width and a height in metres."
        }

        let sectionSize = HatcheryGridGenerator.targetSectionSizeM
        guard widthM >= sectionSize, heightM >= sectionSize else {
            return "Each side needs at least 2 m so one section fits."
        }

        let columns = floor(widthM / sectionSize)
        let rows = floor(heightM / sectionSize)
        guard columns <= 100, rows <= 100, columns * rows <= 2_500 else {
            return "That area is too large to divide into sections."
        }

        return nil
    }

    var isValid: Bool {
        validationMessage == nil
    }

    var areaM2: Double {
        widthM * heightM
    }
}

nonisolated struct HatcherySection: Identifiable, Hashable {
    let id: String
    let row: Int
    let column: Int
    let widthM: Double
    let heightM: Double
    let boundary: HatcheryBoundary
    /// `false` means this projected grid cell falls outside the usable sand region.
    let isActive: Bool

    init(
        id: String,
        row: Int,
        column: Int,
        widthM: Double,
        heightM: Double,
        boundary: HatcheryBoundary,
        isActive: Bool = true
    ) {
        self.id = id
        self.row = row
        self.column = column
        self.widthM = widthM
        self.heightM = heightM
        self.boundary = boundary
        self.isActive = isActive
    }
}

nonisolated struct HatcheryGrid: Hashable {
    let rows: Int
    let columns: Int
    let sections: [HatcherySection]

    var sectionCount: Int { rows * columns }
    var activeSectionCount: Int { sections.count(where: \.isActive) }

    func isSectionActive(row: Int, column: Int) -> Bool {
        sections.first { $0.row == row && $0.column == column }?.isActive ?? false
    }

    var columnLabels: [String] {
        (0..<columns).map(Self.columnLabel)
    }

    var rowLabels: [String] {
        (1...max(rows, 1)).map(String.init)
    }

    static func columnLabel(_ zeroBasedIndex: Int) -> String {
        var value = zeroBasedIndex + 1
        var label = ""
        while value > 0 {
            value -= 1
            label = String(UnicodeScalar(65 + value % 26)!) + label
            value /= 26
        }
        return label
    }
}

nonisolated enum HatcheryGridGenerator {
    static let targetSectionSizeM = 2.0

    static func generate(
        dimension: HatcheryDimension,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion? = nil
    ) -> HatcheryGrid? {
        guard dimension.isValid, boundary.isValid, sandRegion?.isValid ?? true else { return nil }

        let columns = Int(floor(dimension.widthM / targetSectionSizeM))
        let rows = Int(floor(dimension.heightM / targetSectionSizeM))
        guard columns > 0, rows > 0 else { return nil }

        let cellWidth = targetSectionSizeM
        let cellHeight = targetSectionSizeM
        var sections: [HatcherySection] = []
        sections.reserveCapacity(rows * columns)

        for row in 0..<rows {
            for column in 0..<columns {
                let sectionBoundary = boundary.sectionBoundary(
                    row: row,
                    column: column,
                    rowCount: rows,
                    columnCount: columns
                )
                let projectedCenter = sectionBoundary.point(columnFraction: 0.5, rowFraction: 0.5)
                sections.append(
                    HatcherySection(
                        id: "\(HatcheryGrid.columnLabel(column))\(row + 1)",
                        row: row,
                        column: column,
                        widthM: cellWidth,
                        heightM: cellHeight,
                        boundary: sectionBoundary,
                        isActive: sandRegion?.contains(projectedCenter) ?? true
                    )
                )
            }
        }

        return HatcheryGrid(rows: rows, columns: columns, sections: sections)
    }
}

struct HatcherySetupDraft {
    var name = ""
    var image: UIImage?
    var rectifiedImage: UIImage?
    var usesMockImage = false
    var boundary: HatcheryBoundary?
    /// The editable usable-sand outline. It is separate from `boundary`,
    /// which remains the four-corner perspective plane for rectification.
    var sandRegion: HatcherySandRegion?
    var dimension = HatcheryDimension(widthM: 15, heightM: 7)
    var grid: HatcheryGrid?
}

/// UI-only companion for the database-facing `Hatchery` model.
///
/// Photos, rectification, grid projection, and sand-region metadata remain in
/// this session model until their Supabase Storage/schema contract is defined.
struct HatcherySessionData: Identifiable {
    let hatchery: Hatchery
    let photo: UIImage
    let rectifiedPhoto: UIImage
    let boundary: HatcheryBoundary
    /// The user-confirmed usable sand outline in original-photo coordinates.
    /// A default preserves saved/preview hatcheries created before this field.
    let sandRegion: HatcherySandRegion?
    let grid: HatcheryGrid

    var id: UUID { hatchery.id }

    init(
        hatchery: Hatchery,
        photo: UIImage,
        rectifiedPhoto: UIImage,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion? = nil,
        grid: HatcheryGrid
    ) {
        self.hatchery = hatchery
        self.photo = photo
        self.rectifiedPhoto = rectifiedPhoto
        self.boundary = boundary
        self.sandRegion = sandRegion
        self.grid = grid
    }
}

@available(*, deprecated, renamed: "HatcherySessionData")
typealias SavedHatchery = HatcherySessionData
