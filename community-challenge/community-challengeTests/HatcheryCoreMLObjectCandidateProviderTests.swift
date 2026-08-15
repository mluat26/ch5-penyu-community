import CoreGraphics
import CoreVideo
import ImageIO
import XCTest
@testable import community_challenge

final class HatcheryCoreMLObjectCandidateProviderTests: XCTestCase {
    func testVisionBoundingBoxConvertsFromLowerLeftToTopLeftCoordinates() throws {
        let boundary = try XCTUnwrap(
            HatcheryCoreMLObjectCandidateProvider.boundary(
                forVisionBoundingBox: CGRect(x: 0.20, y: 0.30, width: 0.40, height: 0.50)
            )
        )

        XCTAssertEqual(boundary.topLeft.x, 0.20, accuracy: 0.000_001)
        XCTAssertEqual(boundary.topLeft.y, 0.20, accuracy: 0.000_001)
        XCTAssertEqual(boundary.topRight.x, 0.60, accuracy: 0.000_001)
        XCTAssertEqual(boundary.topRight.y, 0.20, accuracy: 0.000_001)
        XCTAssertEqual(boundary.bottomRight.x, 0.60, accuracy: 0.000_001)
        XCTAssertEqual(boundary.bottomRight.y, 0.70, accuracy: 0.000_001)
        XCTAssertEqual(boundary.bottomLeft.x, 0.20, accuracy: 0.000_001)
        XCTAssertEqual(boundary.bottomLeft.y, 0.70, accuracy: 0.000_001)
    }

    func testNearEdgeOvershootIsClampedBeforeBoundaryValidation() throws {
        let boundary = try XCTUnwrap(
            HatcheryCoreMLObjectCandidateProvider.boundary(
                forVisionBoundingBox: CGRect(
                    x: -0.018,
                    y: 0.15,
                    width: 0.40,
                    height: 0.865
                )
            )
        )

        XCTAssertEqual(boundary.topLeft.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(boundary.topLeft.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(boundary.topRight.x, 0.382, accuracy: 0.000_001)
        XCTAssertEqual(boundary.bottomLeft.y, 0.85, accuracy: 0.000_001)
    }

    func testAreaIsValidatedAfterNearEdgeOvershootIsClamped() {
        XCTAssertNotNil(
            HatcheryCoreMLObjectCandidateProvider.boundary(
                forVisionBoundingBox: CGRect(
                    x: 0.04,
                    y: 0.01,
                    width: 0.929,
                    height: 0.999
                )
            )
        )
    }

    func testMateriallyOutsideOrTooSmallVisionBoundingBoxesAreRejected() {
        XCTAssertNil(
            HatcheryCoreMLObjectCandidateProvider.boundary(
                forVisionBoundingBox: CGRect(x: 0.10, y: 0.10, width: 0.10, height: 0.10)
            )
        )
        XCTAssertNil(
            HatcheryCoreMLObjectCandidateProvider.boundary(
                forVisionBoundingBox: CGRect(x: -0.021, y: 0.10, width: 0.50, height: 0.50)
            )
        )
        XCTAssertNil(
            HatcheryCoreMLObjectCandidateProvider.boundary(
                forVisionBoundingBox: CGRect(x: 0.20, y: 0.10, width: 0.821, height: 0.50)
            )
        )
        XCTAssertNil(
            HatcheryCoreMLObjectCandidateProvider.boundary(
                forVisionBoundingBox: CGRect(x: 0.50, y: 0.10, width: -0.40, height: 0.50)
            )
        )
    }

    func testMissingBundledModelIsOptional() {
        XCTAssertNil(
            HatcheryCoreMLObjectCandidateProvider.bundled(
                resourceName: "MissingHatcheryDetectorForTests"
            )
        )
    }

    func testObjectAnalysisRefreshesNoMoreOftenThanItsInterval() {
        XCTAssertTrue(
            HatcheryBoundaryDetector.shouldRefreshObjectDetection(
                lastAnalyzedAt: nil,
                now: 10
            )
        )
        XCTAssertFalse(
            HatcheryBoundaryDetector.shouldRefreshObjectDetection(
                lastAnalyzedAt: 10,
                now: 10.19
            )
        )
        XCTAssertTrue(
            HatcheryBoundaryDetector.shouldRefreshObjectDetection(
                lastAnalyzedAt: 10,
                now: 10.20
            )
        )
    }

    func testUnavailableModelPreservesRectangleStillDetection() throws {
        let image = try makeImage(
            width: 600,
            height: 600,
            rectangle: CGRect(x: 120, y: 120, width: 360, height: 360)
        )
        let detector = HatcheryBoundaryDetector(
            objectCandidateProvider: UnavailableObjectProvider()
        )

        let detection = try XCTUnwrap(
            detector.detectStill(cgImage: image, orientation: .up)
        )

        XCTAssertTrue(detection.boundary.isValid)
        XCTAssertGreaterThanOrEqual(detection.confidence, 0.55)
        XCTAssertEqual(detection.boundary.topLeft.x, 0.20, accuracy: 0.08)
        XCTAssertEqual(detection.boundary.topLeft.y, 0.20, accuracy: 0.08)
        XCTAssertEqual(detection.boundary.bottomRight.x, 0.80, accuracy: 0.08)
        XCTAssertEqual(detection.boundary.bottomRight.y, 0.80, accuracy: 0.08)
    }

    func testIncompatibleModelROIFallsBackToModelBoundary() throws {
        let image = try makeImage(
            width: 600,
            height: 600,
            rectangle: CGRect(x: 120, y: 120, width: 360, height: 360)
        )
        let modelROI = HatcheryBoundary(
            topLeft: NormalizedPoint(x: 0.02, y: 0.02),
            topRight: NormalizedPoint(x: 0.32, y: 0.02),
            bottomRight: NormalizedPoint(x: 0.32, y: 0.32),
            bottomLeft: NormalizedPoint(x: 0.02, y: 0.32)
        )
        let detector = HatcheryBoundaryDetector(
            objectCandidateProvider: StaticObjectProvider(
                detection: HatcheryObjectDetection(
                    boundary: modelROI,
                    confidence: 0.95
                )
            )
        )

        let detection = try XCTUnwrap(
            detector.detectStill(cgImage: image, orientation: .up)
        )

        XCTAssertEqual(detection.boundary, modelROI)
        XCTAssertEqual(detection.confidence, 0.95)
    }

    func testModelSelectsBestAlignedPerspectiveRectangleOverGenericRectangleScore() {
        let modelBoundary = makeBoundary(x: 0.20, y: 0.20, width: 0.60, height: 0.60)
        let broadlyAlignedButLowerQuality = HatcheryBoundaryDetector.Candidate(
            boundary: makeBoundary(x: 0.15, y: 0.15, width: 0.70, height: 0.70),
            confidence: 0.98,
            score: 0.99
        )
        let bestAligned = HatcheryBoundaryDetector.Candidate(
            boundary: modelBoundary,
            confidence: 0.60,
            score: 0.10
        )

        let selected = HatcheryBoundaryDetector.resolvedCandidate(
            objectDetection: HatcheryObjectDetection(
                boundary: modelBoundary,
                confidence: 0.90
            ),
            rectangleCandidates: [broadlyAlignedButLowerQuality, bestAligned]
        )

        XCTAssertEqual(selected?.boundary, bestAligned.boundary)
    }

    func testModelBecomesConservativeFallbackWhenNoRectangleIsStrongEnough() {
        let modelBoundary = makeBoundary(x: 0.20, y: 0.20, width: 0.60, height: 0.60)
        let smallInnerRectangle = HatcheryBoundaryDetector.Candidate(
            boundary: makeBoundary(x: 0.40, y: 0.40, width: 0.16, height: 0.16),
            confidence: 0.99,
            score: 0.99
        )

        let selected = HatcheryBoundaryDetector.resolvedCandidate(
            objectDetection: HatcheryObjectDetection(
                boundary: modelBoundary,
                confidence: 0.90
            ),
            rectangleCandidates: [smallInnerRectangle]
        )

        XCTAssertEqual(selected?.boundary, modelBoundary)
        XCTAssertEqual(selected?.confidence, 0.90)
    }

    func testOrientationChangeRefreshesCachedObjectDetectionImmediately() throws {
        let provider = CountingObjectProvider(
            detection: HatcheryObjectDetection(
                boundary: makeBoundary(x: 0.20, y: 0.20, width: 0.60, height: 0.60),
                confidence: 0.90
            )
        )
        let detector = HatcheryBoundaryDetector(objectCandidateProvider: provider)
        let pixelBuffer = try makePixelBuffer(width: 64, height: 64)

        _ = detector.processLive(pixelBuffer: pixelBuffer, orientation: .up)
        _ = detector.processLive(pixelBuffer: pixelBuffer, orientation: .right)

        XCTAssertEqual(provider.pixelBufferCallCount, 2)
    }

    private func makeImage(
        width: Int,
        height: Int,
        rectangle: CGRect
    ) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rectangle)
        return try XCTUnwrap(context.makeImage())
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(pixelBuffer)
    }

    private func makeBoundary(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> HatcheryBoundary {
        HatcheryBoundary(
            topLeft: NormalizedPoint(x: x, y: y),
            topRight: NormalizedPoint(x: x + width, y: y),
            bottomRight: NormalizedPoint(x: x + width, y: y + height),
            bottomLeft: NormalizedPoint(x: x, y: y + height)
        )
    }
}

private final class UnavailableObjectProvider: HatcheryObjectCandidateProviding {
    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> HatcheryObjectDetection? {
        nil
    }

    func detect(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> HatcheryObjectDetection? {
        nil
    }
}

private final class StaticObjectProvider: HatcheryObjectCandidateProviding {
    let detection: HatcheryObjectDetection?

    init(detection: HatcheryObjectDetection?) {
        self.detection = detection
    }

    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> HatcheryObjectDetection? {
        detection
    }

    func detect(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> HatcheryObjectDetection? {
        detection
    }
}

private final class CountingObjectProvider: HatcheryObjectCandidateProviding {
    let detection: HatcheryObjectDetection?
    private(set) var pixelBufferCallCount = 0

    init(detection: HatcheryObjectDetection?) {
        self.detection = detection
    }

    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> HatcheryObjectDetection? {
        pixelBufferCallCount += 1
        return detection
    }

    func detect(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> HatcheryObjectDetection? {
        detection
    }
}
