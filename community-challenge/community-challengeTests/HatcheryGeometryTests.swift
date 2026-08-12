import CoreGraphics
import XCTest
@testable import community_challenge

final class HatcheryGeometryTests: XCTestCase {
    func testNormalizedPointClampsValuesToUnitRange() {
        XCTAssertEqual(NormalizedPoint(x: -0.4, y: 1.4), NormalizedPoint(x: 0, y: 1))
    }

    func testValidPerspectiveBoundaryIsAccepted() {
        let boundary = HatcheryBoundary(
            topLeft: NormalizedPoint(x: 0.28, y: 0.30),
            topRight: NormalizedPoint(x: 0.71, y: 0.30),
            bottomRight: NormalizedPoint(x: 0.84, y: 0.67),
            bottomLeft: NormalizedPoint(x: 0.17, y: 0.67)
        )

        XCTAssertTrue(boundary.isValid)
    }

    func testCrossedBoundaryIsRejected() {
        let boundary = HatcheryBoundary(
            topLeft: NormalizedPoint(x: 0.15, y: 0.15),
            topRight: NormalizedPoint(x: 0.85, y: 0.85),
            bottomRight: NormalizedPoint(x: 0.85, y: 0.15),
            bottomLeft: NormalizedPoint(x: 0.15, y: 0.85)
        )

        XCTAssertFalse(boundary.isValid)
    }

    func testCollapsedBoundaryIsRejected() {
        let boundary = HatcheryBoundary(
            topLeft: NormalizedPoint(x: 0.49, y: 0.49),
            topRight: NormalizedPoint(x: 0.51, y: 0.49),
            bottomRight: NormalizedPoint(x: 0.51, y: 0.51),
            bottomLeft: NormalizedPoint(x: 0.49, y: 0.51)
        )

        XCTAssertFalse(boundary.isValid)
    }

    func testAspectFillRoundTripPreservesBoundaryWithHorizontalCrop() {
        let mapper = AspectFillImageMapper(
            imageSize: CGSize(width: 4_000, height: 3_000),
            containerSize: CGSize(width: 402, height: 874)
        )
        let boundary = HatcheryBoundary(
            topLeft: NormalizedPoint(x: 0.28, y: 0.30),
            topRight: NormalizedPoint(x: 0.71, y: 0.30),
            bottomRight: NormalizedPoint(x: 0.84, y: 0.67),
            bottomLeft: NormalizedPoint(x: 0.17, y: 0.67)
        )

        let roundTrip = mapper.boundary(for: mapper.viewQuad(for: boundary))

        assertEqual(roundTrip, boundary, accuracy: 0.000_001)
    }

    func testAspectFillRoundTripPreservesBoundaryWithVerticalCrop() {
        let mapper = AspectFillImageMapper(
            imageSize: CGSize(width: 3_000, height: 4_000),
            containerSize: CGSize(width: 874, height: 402)
        )
        let boundary = HatcheryBoundary(
            topLeft: NormalizedPoint(x: 0.10, y: 0.25),
            topRight: NormalizedPoint(x: 0.90, y: 0.25),
            bottomRight: NormalizedPoint(x: 0.80, y: 0.75),
            bottomLeft: NormalizedPoint(x: 0.20, y: 0.75)
        )

        let roundTrip = mapper.boundary(for: mapper.viewQuad(for: boundary))

        assertEqual(roundTrip, boundary, accuracy: 0.000_001)
    }

    func testAspectFillMapsImageCenterToContainerCenter() {
        let mapper = AspectFillImageMapper(
            imageSize: CGSize(width: 4_000, height: 3_000),
            containerSize: CGSize(width: 402, height: 874)
        )

        let center = mapper.viewPoint(for: NormalizedPoint(x: 0.5, y: 0.5))

        XCTAssertEqual(center.x, 201, accuracy: 0.000_001)
        XCTAssertEqual(center.y, 437, accuracy: 0.000_001)
    }

    func testGeneratedGridUsesAdjustedBoundaryForEverySection() throws {
        let adjustedBoundary = HatcheryBoundary(
            topLeft: NormalizedPoint(x: 0.27, y: 0.18),
            topRight: NormalizedPoint(x: 0.76, y: 0.23),
            bottomRight: NormalizedPoint(x: 0.88, y: 0.82),
            bottomLeft: NormalizedPoint(x: 0.12, y: 0.74)
        )
        let grid = try XCTUnwrap(
            HatcheryGridGenerator.generate(
                dimension: HatcheryDimension(widthM: 6, heightM: 4),
                boundary: adjustedBoundary
            )
        )

        XCTAssertEqual(grid.columns, 3)
        XCTAssertEqual(grid.rows, 2)
        XCTAssertEqual(grid.sections.count, 6)

        for section in grid.sections {
            XCTAssertEqual(
                section.boundary,
                adjustedBoundary.sectionBoundary(
                    row: section.row,
                    column: section.column,
                    rowCount: grid.rows,
                    columnCount: grid.columns
                )
            )
        }
        XCTAssertEqual(grid.sections.first?.boundary.topLeft, adjustedBoundary.topLeft)
        XCTAssertEqual(grid.sections.last?.boundary.bottomRight, adjustedBoundary.bottomRight)
    }

    private func assertEqual(
        _ actual: HatcheryBoundary,
        _ expected: HatcheryBoundary,
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (actualPoint, expectedPoint) in zip(actual.ordered, expected.ordered) {
            XCTAssertEqual(actualPoint.x, expectedPoint.x, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(actualPoint.y, expectedPoint.y, accuracy: accuracy, file: file, line: line)
        }
    }
}
