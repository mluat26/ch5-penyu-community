import XCTest
@testable import community_challenge

final class HatcherySectionSolverTests: XCTestCase {
    func testEvenlyDividingBedPicksIdealTwoMeterSections() throws {
        let layout = try XCTUnwrap(
            HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: 6, heightM: 8))
        )

        XCTAssertEqual(layout.columns, 3)
        XCTAssertEqual(layout.rows, 4)
        XCTAssertEqual(layout.sectionWidthM, 2.0, accuracy: 0.000_001)
        XCTAssertEqual(layout.sectionLengthM, 2.0, accuracy: 0.000_001)
    }

    func testOrientationIsNotCollapsedToTheSamePhysicalGrid() throws {
        let layout = try XCTUnwrap(
            HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: 8, heightM: 6))
        )

        // The bed is the 6x8 bed above, rotated. The optimal configuration
        // rotates with it rather than reusing 3x4.
        XCTAssertEqual(layout.columns, 4)
        XCTAssertEqual(layout.rows, 3)
        XCTAssertEqual(layout.sectionWidthM, 2.0, accuracy: 0.000_001)
        XCTAssertEqual(layout.sectionLengthM, 2.0, accuracy: 0.000_001)
    }

    func testNonPerfectBedIsScoredOnActualSectionDimensions() throws {
        let sevenByNine = try XCTUnwrap(
            HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: 7, heightM: 9))
        )
        XCTAssertEqual(sevenByNine.columns, 4)
        XCTAssertEqual(sevenByNine.rows, 4)
        XCTAssertEqual(sevenByNine.sectionWidthM, 1.75, accuracy: 0.000_001)
        XCTAssertEqual(sevenByNine.sectionLengthM, 2.25, accuracy: 0.000_001)

        let nineBySeven = try XCTUnwrap(
            HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: 9, heightM: 7))
        )
        XCTAssertEqual(nineBySeven.columns, 4)
        XCTAssertEqual(nineBySeven.rows, 4)
        XCTAssertEqual(nineBySeven.sectionWidthM, 2.25, accuracy: 0.000_001)
        XCTAssertEqual(nineBySeven.sectionLengthM, 1.75, accuracy: 0.000_001)
    }

    func testInvalidDimensionsReturnNil() {
        XCTAssertNil(HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: 0, heightM: 6)))
        XCTAssertNil(HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: 6, heightM: 0)))
        XCTAssertNil(HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: -4, heightM: 6)))
        XCTAssertNil(HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: 6, heightM: -4)))
        XCTAssertNil(HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: .infinity, heightM: 6)))
        XCTAssertNil(HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: 6, heightM: .nan)))
    }

    /// Regression: an `abs(sw/sl - 1.0)` shape penalty is bounded below 1.0 for
    /// slivers while the area term is unbounded, so it used to prefer a single
    /// 0.80m x 5.00m row over a squarer split. The symmetric ratio must not.
    func testDoesNotProduceASliverSection() throws {
        let layout = try XCTUnwrap(
            HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: 4, heightM: 5))
        )

        XCTAssertGreaterThan(layout.rows, 1)
        XCTAssertLessThan(layout.sectionLengthM / layout.sectionWidthM, 2.0)
    }

    func testLargeBedStaysWithinTheCellCap() throws {
        let layout = try XCTUnwrap(
            HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: 300, heightM: 300))
        )

        XCTAssertLessThanOrEqual(layout.columns, 100)
        XCTAssertLessThanOrEqual(layout.rows, 100)
        XCTAssertLessThanOrEqual(layout.totalSections, 2_500)
    }

    /// Regression: the solver clamps itself to the cell caps, so validation must
    /// not ask it whether a bed fits — it would always say yes and hand back
    /// grossly oversized sections instead of rejecting the bed.
    func testOversizedBedIsRejectedRatherThanSilentlyGivenHugeSections() {
        XCTAssertNotNil(HatcheryDimension(widthM: 300, heightM: 300).validationMessage)
        XCTAssertNotNil(HatcheryDimension(widthM: 250, heightM: 4).validationMessage)
        XCTAssertFalse(HatcheryDimension(widthM: 300, heightM: 300).isValid)
        XCTAssertNil(HatcheryGridGenerator.generate(
            dimension: HatcheryDimension(widthM: 300, heightM: 300),
            boundary: .fullImage
        ))
    }

    /// 15 x 7 is the setup flow's default draft dimension, so pin what it produces.
    func testDefaultDraftDimensionLayout() throws {
        let layout = try XCTUnwrap(
            HatcherySectionSolver.solve(dimension: HatcheryDimension(widthM: 15, heightM: 7))
        )

        XCTAssertEqual(layout.columns, 9)
        XCTAssertEqual(layout.rows, 3)
        XCTAssertEqual(layout.totalSections, 27)
        XCTAssertEqual(layout.sectionWidthM, 15.0 / 9.0, accuracy: 0.000_001)
        XCTAssertEqual(layout.sectionLengthM, 7.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(layout.sectionAreaM2, 3.888_888, accuracy: 0.000_01)

        // The grid tiles the bed exactly: no sand is truncated away.
        XCTAssertEqual(
            Double(layout.totalSections) * layout.sectionAreaM2,
            15.0 * 7.0,
            accuracy: 0.000_001
        )
    }

    func testBedsWithinTheSupportedSizeStayValid() {
        XCTAssertNil(HatcheryDimension(widthM: 6, heightM: 8).validationMessage)
        XCTAssertNil(HatcheryDimension(widthM: 15, heightM: 7).validationMessage)
        XCTAssertNil(HatcheryDimension(widthM: 2, heightM: 2).validationMessage)
        XCTAssertNotNil(HatcheryDimension(widthM: 1.5, heightM: 4).validationMessage)
    }
}
