import CoreGraphics
import ImageIO
import XCTest
@testable import community_challenge

final class HatcheryBoundaryDetectorTests: XCTestCase {
    func testVisionPointFlipsYAxisIntoTopLeftCoordinates() {
        let point = HatcheryBoundaryDetector.appPoint(
            from: CGPoint(x: 0.25, y: 0.80)
        )

        XCTAssertEqual(point.x, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(point.y, 0.20, accuracy: 0.000_001)
    }

    func testOrientedSizeSwapsOnlyQuarterTurnOrientations() {
        let original = CGSize(width: 640, height: 480)
        let swapped = CGSize(width: 480, height: 640)

        for orientation in [
            CGImagePropertyOrientation.up,
            .upMirrored,
            .down,
            .downMirrored,
        ] {
            XCTAssertEqual(
                HatcheryBoundaryDetector.orientedSize(
                    width: 640,
                    height: 480,
                    orientation: orientation
                ),
                original
            )
        }

        for orientation in [
            CGImagePropertyOrientation.left,
            .leftMirrored,
            .right,
            .rightMirrored,
        ] {
            XCTAssertEqual(
                HatcheryBoundaryDetector.orientedSize(
                    width: 640,
                    height: 480,
                    orientation: orientation
                ),
                swapped
            )
        }
    }

    func testStabilizerRequiresTwoCompatibleDetections() throws {
        let detector = HatcheryBoundaryDetector()
        let candidate = makeDetection(boundary: makeBoundary(), confidence: 0.70)

        XCTAssertNil(detector.stabilize(candidate))

        let stable = try XCTUnwrap(detector.stabilize(candidate))
        XCTAssertEqual(stable, candidate)
    }

    func testStabilizerAppliesExponentialSmoothingToTrackingCandidate() throws {
        let detector = HatcheryBoundaryDetector()
        let initialBoundary = makeBoundary()
        let initial = makeDetection(boundary: initialBoundary, confidence: 0.60)
        _ = detector.stabilize(initial)
        _ = detector.stabilize(initial)

        let movedBoundary = shifted(initialBoundary, x: 0.10, y: 0.05)
        let moved = makeDetection(boundary: movedBoundary, confidence: 0.90)
        let smoothed = try XCTUnwrap(detector.stabilize(moved))

        let expectedBoundary = shifted(initialBoundary, x: 0.03, y: 0.015)
        assertBoundary(smoothed.boundary, equals: expectedBoundary, accuracy: 0.000_001)
        XCTAssertEqual(smoothed.confidence, 0.69, accuracy: 0.000_001)
    }

    func testStabilizerRequiresRepeatedConfirmationBeforeReplacingLargeJump() throws {
        let detector = HatcheryBoundaryDetector()
        let initial = makeDetection(boundary: makeBoundary(), confidence: 0.65)
        _ = detector.stabilize(initial)
        let originalStable = try XCTUnwrap(detector.stabilize(initial))

        let jumped = makeDetection(
            boundary: makeBoundary(left: 0.48, top: 0.20, right: 0.88, bottom: 0.70),
            confidence: 0.82
        )

        XCTAssertEqual(detector.stabilize(jumped), originalStable)
        XCTAssertEqual(detector.stabilize(jumped), jumped)
    }

    func testStabilizerRetainsThreeMissesAndClearsOnFourth() throws {
        let detector = HatcheryBoundaryDetector()
        let candidate = makeDetection(boundary: makeBoundary(), confidence: 0.75)
        _ = detector.stabilize(candidate)
        let stable = try XCTUnwrap(detector.stabilize(candidate))

        XCTAssertEqual(detector.stabilize(nil), stable)
        XCTAssertEqual(detector.stabilize(nil), stable)
        XCTAssertEqual(detector.stabilize(nil), stable)
        XCTAssertNil(detector.stabilize(nil))
    }

    func testScoringRejectsBoundariesOutsideAllowedArea() {
        let tooSmall = makeBoundary(left: 0.20, top: 0.20, right: 0.40, bottom: 0.40)
        let tooLarge = makeBoundary(left: 0.01, top: 0.01, right: 0.99, bottom: 0.99)

        XCTAssertLessThan(HatcheryBoundaryDetector.polygonArea(tooSmall), 0.08)
        XCTAssertGreaterThan(HatcheryBoundaryDetector.polygonArea(tooLarge), 0.92)
        XCTAssertNil(
            HatcheryBoundaryDetector.score(
                boundary: tooSmall,
                confidence: 0.99,
                reference: nil
            )
        )
        XCTAssertNil(
            HatcheryBoundaryDetector.score(
                boundary: tooLarge,
                confidence: 0.99,
                reference: nil
            )
        )
    }

    func testHigherConfidenceProducesHigherScoreForSameBoundary() throws {
        let boundary = makeBoundary()
        let lowConfidence = try XCTUnwrap(
            HatcheryBoundaryDetector.score(
                boundary: boundary,
                confidence: 0.60,
                reference: nil
            )
        )
        let highConfidence = try XCTUnwrap(
            HatcheryBoundaryDetector.score(
                boundary: boundary,
                confidence: 0.90,
                reference: nil
            )
        )

        XCTAssertGreaterThan(highConfidence, lowConfidence)
    }

    func testLargerBoundaryProducesHigherScoreWhenCenterAndConfidenceMatch() throws {
        let small = makeBoundary(left: 0.30, top: 0.30, right: 0.70, bottom: 0.70)
        let large = makeBoundary(left: 0.20, top: 0.20, right: 0.80, bottom: 0.80)

        let smallScore = try XCTUnwrap(
            HatcheryBoundaryDetector.score(
                boundary: small,
                confidence: 0.75,
                reference: nil
            )
        )
        let largeScore = try XCTUnwrap(
            HatcheryBoundaryDetector.score(
                boundary: large,
                confidence: 0.75,
                reference: nil
            )
        )

        XCTAssertGreaterThan(largeScore, smallScore)
    }

    func testCenteredBoundaryProducesHigherScoreWhenAreaAndConfidenceMatch() throws {
        let centered = makeBoundary(left: 0.30, top: 0.30, right: 0.70, bottom: 0.70)
        let offCenter = makeBoundary(left: 0.05, top: 0.05, right: 0.45, bottom: 0.45)

        let centeredScore = try XCTUnwrap(
            HatcheryBoundaryDetector.score(
                boundary: centered,
                confidence: 0.75,
                reference: nil
            )
        )
        let offCenterScore = try XCTUnwrap(
            HatcheryBoundaryDetector.score(
                boundary: offCenter,
                confidence: 0.75,
                reference: nil
            )
        )

        XCTAssertGreaterThan(centeredScore, offCenterScore)
    }

    func testReferenceContinuityProducesHigherScoreForNearbyCandidate() throws {
        let reference = makeBoundary(left: 0.20, top: 0.20, right: 0.60, bottom: 0.60)
        let nearby = shifted(reference, x: 0.02, y: 0.02)
        let distant = shifted(reference, x: 0.20, y: 0.20)

        let nearbyScore = try XCTUnwrap(
            HatcheryBoundaryDetector.score(
                boundary: nearby,
                confidence: 0.75,
                reference: reference
            )
        )
        let distantScore = try XCTUnwrap(
            HatcheryBoundaryDetector.score(
                boundary: distant,
                confidence: 0.75,
                reference: reference
            )
        )

        XCTAssertGreaterThan(nearbyScore, distantScore)
    }

    func testStillDetectionFindsHighContrastRectangle() throws {
        let image = try makeImage(
            width: 600,
            height: 600,
            rectangle: CGRect(x: 120, y: 120, width: 360, height: 360)
        )

        let result = HatcheryBoundaryDetector().detectStill(cgImage: image, orientation: .up)

        let detection = try XCTUnwrap(result)
        XCTAssertEqual(detection.orientedImageSize, CGSize(width: 600, height: 600))
        XCTAssertTrue(detection.boundary.isValid)
        XCTAssertGreaterThanOrEqual(detection.confidence, 0.55)
        assertBoundary(detection.boundary, isNear: 0.2...0.8, accuracy: 0.08)
    }

    func testStillDetectionReturnsNilWhenImageContainsNoEdges() throws {
        let image = try makeImage(width: 600, height: 600, rectangle: nil)

        let result = HatcheryBoundaryDetector().detectStill(cgImage: image, orientation: .up)

        XCTAssertNil(result)
    }

    func testStillDetectionReportsRotatedImageSize() throws {
        let image = try makeImage(
            width: 640,
            height: 480,
            rectangle: CGRect(x: 176, y: 96, width: 288, height: 288)
        )

        let result = HatcheryBoundaryDetector().detectStill(cgImage: image, orientation: .right)

        let detection = try XCTUnwrap(result)
        XCTAssertEqual(detection.orientedImageSize, CGSize(width: 480, height: 640))
        XCTAssertTrue(detection.boundary.isValid)
    }

    private func makeImage(
        width: Int,
        height: Int,
        rectangle: CGRect?
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if let rectangle {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(rectangle)
        }

        return try XCTUnwrap(context.makeImage())
    }

    private func makeBoundary(
        left: Double = 0.20,
        top: Double = 0.20,
        right: Double = 0.70,
        bottom: Double = 0.70
    ) -> HatcheryBoundary {
        HatcheryBoundary(
            topLeft: NormalizedPoint(x: left, y: top),
            topRight: NormalizedPoint(x: right, y: top),
            bottomRight: NormalizedPoint(x: right, y: bottom),
            bottomLeft: NormalizedPoint(x: left, y: bottom)
        )
    }

    private func makeDetection(
        boundary: HatcheryBoundary,
        confidence: Float
    ) -> HatcheryBoundaryDetection {
        HatcheryBoundaryDetection(
            boundary: boundary,
            orientedImageSize: CGSize(width: 1_920, height: 1_080),
            confidence: confidence
        )
    }

    private func shifted(
        _ boundary: HatcheryBoundary,
        x: Double,
        y: Double
    ) -> HatcheryBoundary {
        let points = boundary.ordered.map {
            NormalizedPoint(x: $0.x + x, y: $0.y + y)
        }
        return HatcheryBoundary(
            topLeft: points[0],
            topRight: points[1],
            bottomRight: points[2],
            bottomLeft: points[3]
        )
    }

    private func assertBoundary(
        _ actual: HatcheryBoundary,
        equals expected: HatcheryBoundary,
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (actualPoint, expectedPoint) in zip(actual.ordered, expected.ordered) {
            XCTAssertEqual(actualPoint.x, expectedPoint.x, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(actualPoint.y, expectedPoint.y, accuracy: accuracy, file: file, line: line)
        }
    }

    private func assertBoundary(
        _ boundary: HatcheryBoundary,
        isNear expectedRange: ClosedRange<Double>,
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = [
            NormalizedPoint(x: expectedRange.lowerBound, y: expectedRange.lowerBound),
            NormalizedPoint(x: expectedRange.upperBound, y: expectedRange.lowerBound),
            NormalizedPoint(x: expectedRange.upperBound, y: expectedRange.upperBound),
            NormalizedPoint(x: expectedRange.lowerBound, y: expectedRange.upperBound),
        ]

        for (actual, expected) in zip(boundary.ordered, expected) {
            XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
        }
    }
}
