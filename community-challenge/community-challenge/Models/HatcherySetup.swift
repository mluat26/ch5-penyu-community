import CoreGraphics
import Foundation
import UIKit

struct NormalizedPoint: Codable, Hashable {
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
struct HatcheryBoundary: Codable, Hashable {
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

    /// The framing trapezoid used before the user adjusts anything. Mirrors
    /// `QuadPoints.defaultShape(in:)` so a capture always starts out valid,
    /// even if the container size is unknown at the moment of delivery.
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
    ///
    /// The thresholds must stay *looser* than `QuadPoints.isValid()`, which is
    /// what actually gates dragging. That check works in screen points, so its
    /// limits shrink by the rendered area (roughly 6e5 px²) once normalized:
    /// its 0.5 pt turn becomes ~9e-7 and its 24 pt corner spacing becomes an
    /// area of ~1e-3. Anything stricter here would silently reject a boundary
    /// the user was allowed to draw, disabling Confirm and Next with no
    /// explanation.
    var isValid: Bool {
        let points = ordered.map(\.cgPoint)
        let signedTurns = points.indices.map { index -> CGFloat in
            let a = points[index]
            let b = points[(index + 1) % points.count]
            let c = points[(index + 2) % points.count]
            return Self.cross(a, b, c)
        }

        let epsilon: CGFloat = 1e-7
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
        return abs(doubledArea) * 0.5 > 1e-4
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

/// Converts points between an aspect-filled image and its SwiftUI container.
struct AspectFillImageMapper {
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

struct HatcheryDimension: Hashable {
    var widthM: Double
    var heightM: Double

    /// Why this dimension cannot be gridded, or `nil` when it is usable. The
    /// screen shows this instead of just greying out Next, so the minimum-side
    /// rule is never a silent dead end.
    var validationMessage: String? {
        guard
            widthM.isFinite, heightM.isFinite,
            widthM > 0, heightM > 0
        else {
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

struct HatcheryGrid: Hashable {
    let rows: Int
    let columns: Int

    var sectionCount: Int { rows * columns }

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

enum HatcheryGridGenerator {
    /// `HatcheryDimension.validationMessage` spells this out as "2 m" — change both together.
    static let targetSectionSizeM = 2.0

    static func generate(
        dimension: HatcheryDimension,
        boundary: HatcheryBoundary
    ) -> HatcheryGrid? {
        guard dimension.isValid, boundary.isValid else { return nil }

        let columns = Int(floor(dimension.widthM / targetSectionSizeM))
        let rows = Int(floor(dimension.heightM / targetSectionSizeM))
        guard columns > 0, rows > 0 else { return nil }

        return HatcheryGrid(rows: rows, columns: columns)
    }
}

/// UI-only companion for the database-facing `Hatchery` model.
struct SavedHatchery: Identifiable {
    let hatchery: Hatchery
    let rectifiedPhoto: UIImage
    let grid: HatcheryGrid

    var id: UUID { hatchery.id }
}
