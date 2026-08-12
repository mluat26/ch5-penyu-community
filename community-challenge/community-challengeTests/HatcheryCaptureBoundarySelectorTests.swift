import CoreGraphics
import XCTest
@testable import community_challenge

final class HatcheryCaptureBoundarySelectorTests: XCTestCase {
    func testNearbyStillDetectionRefinesLiveBoundary() {
        let live = makeBoundary(left: 0.20, top: 0.20, right: 0.70, bottom: 0.70)
        let still = makeBoundary(left: 0.24, top: 0.22, right: 0.74, bottom: 0.72)

        let selection = HatcheryCaptureBoundarySelector.select(
            stillDetection: makeDetection(still),
            liveBoundary: live,
            fallbackBoundary: .fullImage
        )

        XCTAssertEqual(selection.boundary, still)
        XCTAssertEqual(selection.source, .stillRefinement)
    }

    func testDistantStillDetectionDoesNotReplaceLiveSnapshot() {
        let live = makeBoundary(left: 0.10, top: 0.10, right: 0.50, bottom: 0.50)
        let distantStill = makeBoundary(left: 0.45, top: 0.45, right: 0.85, bottom: 0.85)

        let selection = HatcheryCaptureBoundarySelector.select(
            stillDetection: makeDetection(distantStill),
            liveBoundary: live,
            fallbackBoundary: .fullImage
        )

        XCTAssertEqual(selection.boundary, live)
        XCTAssertEqual(selection.source, .liveSnapshot)
    }

    func testMissingStillDetectionUsesLiveSnapshot() {
        let live = makeBoundary(left: 0.20, top: 0.20, right: 0.70, bottom: 0.70)

        let selection = HatcheryCaptureBoundarySelector.select(
            stillDetection: nil,
            liveBoundary: live,
            fallbackBoundary: .fullImage
        )

        XCTAssertEqual(selection.boundary, live)
        XCTAssertEqual(selection.source, .liveSnapshot)
    }

    func testPhotoLibraryImageUsesStillDetectionWithoutLiveBoundary() {
        let still = makeBoundary(left: 0.18, top: 0.16, right: 0.82, bottom: 0.78)

        let selection = HatcheryCaptureBoundarySelector.select(
            stillDetection: makeDetection(still),
            liveBoundary: nil,
            fallbackBoundary: .fullImage
        )

        XCTAssertEqual(selection.boundary, still)
        XCTAssertEqual(selection.source, .stillDetection)
    }

    func testNoDetectionUsesDefaultGuide() {
        let fallback = makeBoundary(left: 0.28, top: 0.30, right: 0.72, bottom: 0.67)

        let selection = HatcheryCaptureBoundarySelector.select(
            stillDetection: nil,
            liveBoundary: nil,
            fallbackBoundary: fallback
        )

        XCTAssertEqual(selection.boundary, fallback)
        XCTAssertEqual(selection.source, .defaultGuide)
    }

    func testRefinementThresholdIsInclusive() {
        let live = makeBoundary(left: 0.25, top: 0.25, right: 0.50, bottom: 0.50)
        let still = makeBoundary(left: 0.3125, top: 0.25, right: 0.5625, bottom: 0.50)

        let selection = HatcheryCaptureBoundarySelector.select(
            stillDetection: makeDetection(still),
            liveBoundary: live,
            fallbackBoundary: .fullImage,
            maximumRefinementDistance: 0.0625
        )

        XCTAssertEqual(selection.source, .stillRefinement)
    }

    private func makeDetection(_ boundary: HatcheryBoundary) -> HatcheryBoundaryDetection {
        HatcheryBoundaryDetection(
            boundary: boundary,
            orientedImageSize: CGSize(width: 1_920, height: 1_080),
            confidence: 0.80
        )
    }

    private func makeBoundary(
        left: Double,
        top: Double,
        right: Double,
        bottom: Double
    ) -> HatcheryBoundary {
        HatcheryBoundary(
            topLeft: NormalizedPoint(x: left, y: top),
            topRight: NormalizedPoint(x: right, y: top),
            bottomRight: NormalizedPoint(x: right, y: bottom),
            bottomLeft: NormalizedPoint(x: left, y: bottom)
        )
    }
}
