import CoreGraphics
import Foundation

nonisolated struct NormalizedPoint: Codable, Hashable, Sendable {
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
nonisolated struct HatcheryBoundary: Codable, Hashable, Sendable {
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
nonisolated struct HatcherySandRegion: Codable, Hashable, Sendable {
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

nonisolated struct HatcheryDimension: Codable, Hashable, Sendable {
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

/// A compact, versioned representation of the grid that is safe to store in
/// Postgres. Individual section quadrilaterals are deliberately not persisted:
/// they are deterministically derived from the saved perspective boundary.
/// The active-cell list is retained because it records the user's irregular
/// sand mask without depending on a future grid-generation algorithm.
nonisolated struct HatcheryGridSnapshot: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumRowsOrColumns = 100
    static let maximumCellCount = 2_500

    let schemaVersion: Int
    let rows: Int
    let columns: Int
    let sectionWidthM: Double
    let sectionHeightM: Double
    let activeCells: [HatcheryGridCellCoordinate]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case rows
        case columns
        case sectionWidthM = "section_width_m"
        case sectionHeightM = "section_height_m"
        case activeCells = "active_cells"
    }

    init(grid: HatcheryGrid) {
        schemaVersion = Self.currentSchemaVersion
        rows = grid.rows
        columns = grid.columns
        sectionWidthM = grid.sections.first?.widthM ?? HatcheryGridGenerator.targetSectionSizeM
        sectionHeightM = grid.sections.first?.heightM ?? HatcheryGridGenerator.targetSectionSizeM
        activeCells = grid.sections
            .filter(\.isActive)
            .map { HatcheryGridCellCoordinate(row: $0.row, column: $0.column) }
            .sorted()
    }

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        rows: Int,
        columns: Int,
        sectionWidthM: Double,
        sectionHeightM: Double,
        activeCells: [HatcheryGridCellCoordinate]
    ) {
        self.schemaVersion = schemaVersion
        self.rows = rows
        self.columns = columns
        self.sectionWidthM = sectionWidthM
        self.sectionHeightM = sectionHeightM
        self.activeCells = activeCells.sorted()
    }

    /// Recreates the projection exactly as it was saved. This intentionally
    /// does not call `HatcheryGridGenerator`: its future tuning must never
    /// change which cells were usable for a historical hatchery scan.
    func makeGrid(boundary: HatcheryBoundary) throws -> HatcheryGrid {
        try validate(boundary: boundary)

        let activeCoordinates = Set(activeCells)
        let sections = (0..<rows).flatMap { row in
            (0..<columns).map { column in
                HatcherySection(
                    id: "\(HatcheryGrid.columnLabel(column))\(row + 1)",
                    row: row,
                    column: column,
                    widthM: sectionWidthM,
                    heightM: sectionHeightM,
                    boundary: boundary.sectionBoundary(
                        row: row,
                        column: column,
                        rowCount: rows,
                        columnCount: columns
                    ),
                    isActive: activeCoordinates.contains(
                        HatcheryGridCellCoordinate(row: row, column: column)
                    )
                )
            }
        }

        return HatcheryGrid(rows: rows, columns: columns, sections: sections)
    }

    func validate(boundary: HatcheryBoundary) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw HatcheryLayoutPersistenceError.unsupportedGridSchema
        }
        guard boundary.isValid else {
            throw HatcheryLayoutPersistenceError.invalidBoundary
        }
        guard
            (1...Self.maximumRowsOrColumns).contains(rows),
            (1...Self.maximumRowsOrColumns).contains(columns),
            rows * columns <= Self.maximumCellCount,
            sectionWidthM.isFinite,
            sectionHeightM.isFinite,
            sectionWidthM > 0,
            sectionHeightM > 0
        else {
            throw HatcheryLayoutPersistenceError.invalidGridSnapshot
        }

        let coordinateSet = Set(activeCells)
        guard coordinateSet.count == activeCells.count,
              activeCells.allSatisfy({
                  (0..<rows).contains($0.row) && (0..<columns).contains($0.column)
              })
        else {
            throw HatcheryLayoutPersistenceError.invalidGridSnapshot
        }
    }
}

nonisolated struct HatcheryGridCellCoordinate: Codable, Hashable, Comparable, Sendable {
    let row: Int
    let column: Int

    static func < (lhs: HatcheryGridCellCoordinate, rhs: HatcheryGridCellCoordinate) -> Bool {
        lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
    }
}

nonisolated enum HatcheryLayoutPersistenceError: LocalizedError {
    case invalidBoundary
    case invalidGridSnapshot
    case unsupportedGridSchema
    case malformedPhoto
    case missingSourcePhoto
    case unexpectedLayoutState

    var errorDescription: String? {
        switch self {
        case .invalidBoundary:
            "The saved hatchery boundary is invalid. Please scan it again."
        case .invalidGridSnapshot:
            "The saved hatchery grid is invalid. Please scan it again."
        case .unsupportedGridSchema:
            "This hatchery layout needs to be re-scanned before it can be opened."
        case .malformedPhoto:
            "The saved hatchery photo could not be opened. Please scan it again."
        case .missingSourcePhoto:
            "The saved hatchery photo is missing. Please scan it again."
        case .unexpectedLayoutState:
            "This hatchery layout is not ready yet. Please try again."
        }
    }
}
