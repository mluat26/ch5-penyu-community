import CoreGraphics
import XCTest
@testable import community_challenge

final class HatcheryPerspectiveMapperTests: XCTestCase {
    func testSkewedBoundaryCornersMapToRectifiedUnitSquare() throws {
        let boundary = makeSkewedBoundary()
        let mapper = try XCTUnwrap(HatcheryPerspectiveMapper(boundary: boundary))
        let expectedCorners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1)
        ]

        for (source, expected) in zip(boundary.ordered, expectedCorners) {
            let rectified = try XCTUnwrap(mapper.rectifiedPoint(forSource: source))
            assertEqual(rectified, expected)
        }
    }

    func testSkewedBoundaryRoundTripsInteriorPoints() throws {
        let mapper = try XCTUnwrap(HatcheryPerspectiveMapper(boundary: makeSkewedBoundary()))
        let sourcePoints = [
            NormalizedPoint(x: 0.34, y: 0.30),
            NormalizedPoint(x: 0.52, y: 0.49),
            NormalizedPoint(x: 0.69, y: 0.64)
        ]

        for source in sourcePoints {
            let rectified = try XCTUnwrap(mapper.rectifiedPoint(forSource: source))
            let roundTrip = try XCTUnwrap(
                mapper.sourcePoint(
                    forRectified: NormalizedPoint(x: Double(rectified.x), y: Double(rectified.y))
                )
            )

            XCTAssertEqual(roundTrip.x, source.cgPoint.x, accuracy: 0.000_001)
            XCTAssertEqual(roundTrip.y, source.cgPoint.y, accuracy: 0.000_001)
        }
    }

    func testConcaveSandRegionMapsIntoRectifiedSpaceAndPreservesMembership() throws {
        let mapper = try XCTUnwrap(HatcheryPerspectiveMapper(boundary: makeSkewedBoundary()))
        let rectifiedPoints = [
            NormalizedPoint(x: 0.10, y: 0.10),
            NormalizedPoint(x: 0.90, y: 0.10),
            NormalizedPoint(x: 0.90, y: 0.90),
            NormalizedPoint(x: 0.55, y: 0.90),
            NormalizedPoint(x: 0.55, y: 0.45),
            NormalizedPoint(x: 0.10, y: 0.45)
        ]
        let sourceRegion = try XCTUnwrap(
            HatcherySandRegion(
                points: try rectifiedPoints.map { point in
                    let source = try XCTUnwrap(mapper.sourcePoint(forRectified: point))
                    return NormalizedPoint(x: Double(source.x), y: Double(source.y))
                }
            )
        )

        let rectifiedRegion = try XCTUnwrap(mapper.rectifiedRegion(for: sourceRegion))

        XCTAssertTrue(rectifiedRegion.isValid)
        XCTAssertTrue(rectifiedRegion.points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        XCTAssertTrue(rectifiedRegion.contains(NormalizedPoint(x: 0.25, y: 0.25)))
        XCTAssertTrue(rectifiedRegion.contains(NormalizedPoint(x: 0.70, y: 0.70)))
        XCTAssertFalse(rectifiedRegion.contains(NormalizedPoint(x: 0.25, y: 0.70)))
    }

    func testRegionCrossingBoundaryIsClippedToCorrectedImage() throws {
        let boundary = makeSkewedBoundary()
        let mapper = try XCTUnwrap(HatcheryPerspectiveMapper(boundary: boundary))
        let sourceRegion = try XCTUnwrap(
            HatcherySandRegion(points: [
                NormalizedPoint(x: 0.02, y: 0.25),
                NormalizedPoint(x: 0.98, y: 0.25),
                NormalizedPoint(x: 0.98, y: 0.90),
                NormalizedPoint(x: 0.02, y: 0.90)
            ])
        )

        let rectifiedRegion = try XCTUnwrap(mapper.rectifiedRegion(for: sourceRegion))

        XCTAssertTrue(rectifiedRegion.isValid)
        XCTAssertTrue(rectifiedRegion.points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        XCTAssertTrue(rectifiedRegion.contains(NormalizedPoint(x: 0.5, y: 0.5)))
    }

    func testGridClassifiesActiveSectionsInRectifiedSandCoordinates() throws {
        let boundary = makeSkewedBoundary()
        let mapper = try XCTUnwrap(HatcheryPerspectiveMapper(boundary: boundary))
        let sourceRegion = try XCTUnwrap(
            HatcherySandRegion(
                points: try [
                    NormalizedPoint(x: 0, y: 0),
                    NormalizedPoint(x: 0.62, y: 0),
                    NormalizedPoint(x: 0.62, y: 1),
                    NormalizedPoint(x: 0, y: 1)
                ].map { point in
                    let source = try XCTUnwrap(mapper.sourcePoint(forRectified: point))
                    return NormalizedPoint(x: Double(source.x), y: Double(source.y))
                }
            )
        )

        let grid = try XCTUnwrap(
            HatcheryGridGenerator.generate(
                dimension: HatcheryDimension(widthM: 6, heightM: 6),
                boundary: boundary,
                sandRegion: sourceRegion
            )
        )

        XCTAssertEqual(
            grid.sections.filter(\.isActive).map(\.id),
            ["A1", "B1", "A2", "B2", "A3", "B3"]
        )
        XCTAssertEqual(
            grid.sections.filter { !$0.isActive }.map(\.id),
            ["C1", "C2", "C3"]
        )
    }

    private func makeSkewedBoundary() -> HatcheryBoundary {
        HatcheryBoundary(
            topLeft: NormalizedPoint(x: 0.20, y: 0.15),
            topRight: NormalizedPoint(x: 0.80, y: 0.25),
            bottomRight: NormalizedPoint(x: 0.88, y: 0.85),
            bottomLeft: NormalizedPoint(x: 0.10, y: 0.75)
        )
    }

    private func assertEqual(
        _ actual: CGPoint,
        _ expected: CGPoint,
        accuracy: CGFloat = 0.000_001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
    }
}
