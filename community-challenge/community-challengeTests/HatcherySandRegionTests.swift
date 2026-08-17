import XCTest
@testable import community_challenge

final class HatcherySandRegionTests: XCTestCase {
    func testConcaveSandRegionIsAccepted() throws {
        let region = try XCTUnwrap(makeConcaveRegion())

        XCTAssertTrue(region.isValid)
        XCTAssertEqual(region.points.count, 6)
    }

    func testSelfIntersectingSandRegionIsRejected() {
        let bowTie = HatcherySandRegion(points: [
            NormalizedPoint(x: 0.15, y: 0.15),
            NormalizedPoint(x: 0.85, y: 0.85),
            NormalizedPoint(x: 0.85, y: 0.15),
            NormalizedPoint(x: 0.15, y: 0.85)
        ])

        XCTAssertNil(bowTie)
    }

    func testContainsSupportsConcavityAndIncludesPerimeter() throws {
        let region = try XCTUnwrap(makeConcaveRegion())

        XCTAssertTrue(region.contains(NormalizedPoint(x: 0.25, y: 0.25)))
        XCTAssertTrue(region.contains(NormalizedPoint(x: 0.70, y: 0.70)))
        XCTAssertTrue(region.contains(NormalizedPoint(x: 0.55, y: 0.55)))
        XCTAssertFalse(region.contains(NormalizedPoint(x: 0.25, y: 0.70)))
    }

    func testGridMarksSectionsOutsideSandRegionInactive() throws {
        let sandRegion = try XCTUnwrap(
            HatcherySandRegion(points: [
                NormalizedPoint(x: 0, y: 0),
                NormalizedPoint(x: 0.66, y: 0),
                NormalizedPoint(x: 0.66, y: 1),
                NormalizedPoint(x: 0, y: 1)
            ])
        )
        let grid = try XCTUnwrap(
            HatcheryGridGenerator.generate(
                dimension: HatcheryDimension(widthM: 6, heightM: 6),
                boundary: .fullImage,
                sandRegion: sandRegion
            )
        )

        XCTAssertEqual(grid.sections.filter(\.isActive).map(\.id), ["A1", "B1", "A2", "B2", "A3", "B3"])
        XCTAssertEqual(grid.sections.filter { !$0.isActive }.map(\.id), ["C1", "C2", "C3"])
    }

    func testGridWithoutSandRegionKeepsEverySectionActive() throws {
        let grid = try XCTUnwrap(
            HatcheryGridGenerator.generate(
                dimension: HatcheryDimension(widthM: 6, heightM: 4),
                boundary: .fullImage
            )
        )

        XCTAssertTrue(grid.sections.allSatisfy(\.isActive))
    }

    func testDefaultRegionUsesThePerspectiveBoundaryPoints() {
        let boundary = HatcheryBoundary(
            topLeft: NormalizedPoint(x: 0.20, y: 0.20),
            topRight: NormalizedPoint(x: 0.80, y: 0.25),
            bottomRight: NormalizedPoint(x: 0.90, y: 0.85),
            bottomLeft: NormalizedPoint(x: 0.10, y: 0.75)
        )

        XCTAssertEqual(HatcherySandRegion.default(from: boundary).points, boundary.ordered)
    }

    private func makeConcaveRegion() -> HatcherySandRegion? {
        HatcherySandRegion(points: [
            NormalizedPoint(x: 0.10, y: 0.10),
            NormalizedPoint(x: 0.90, y: 0.10),
            NormalizedPoint(x: 0.90, y: 0.90),
            NormalizedPoint(x: 0.55, y: 0.90),
            NormalizedPoint(x: 0.55, y: 0.45),
            NormalizedPoint(x: 0.10, y: 0.45)
        ])
    }
}
