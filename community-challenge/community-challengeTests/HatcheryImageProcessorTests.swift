import CoreGraphics
import UIKit
import XCTest
@testable import community_challenge

final class HatcheryImageProcessorTests: XCTestCase {
    func testMaskKeepsSandPixelsAndClearsPixelsOutsideSegment() throws {
        let image = makeSolidImage(size: CGSize(width: 100, height: 100))
        let sandRegion = try XCTUnwrap(
            HatcherySandRegion(points: [
                NormalizedPoint(x: 0, y: 0),
                NormalizedPoint(x: 0.70, y: 0),
                NormalizedPoint(x: 0, y: 0.70)
            ])
        )

        let masked = HatcheryImageProcessor.maskedImage(image, to: sandRegion)

        // Sample along the horizontal center line so this raw-CGImage probe
        // is independent of Core Graphics' bottom-left pixel storage.
        XCTAssertGreaterThan(alpha(at: CGPoint(x: 10, y: 50), in: masked), 0)
        XCTAssertEqual(alpha(at: CGPoint(x: 90, y: 50), in: masked), 0)
        XCTAssertEqual(masked.size, image.size)
    }

    func testPerspectiveRectificationCarriesTheSegmentIntoTheCorrectedImage() throws {
        let boundary = HatcheryBoundary(
            topLeft: NormalizedPoint(x: 0.18, y: 0.18),
            topRight: NormalizedPoint(x: 0.82, y: 0.25),
            bottomRight: NormalizedPoint(x: 0.90, y: 0.82),
            bottomLeft: NormalizedPoint(x: 0.10, y: 0.74)
        )
        let mapper = try XCTUnwrap(HatcheryPerspectiveMapper(boundary: boundary))
        let sourceRegion = try XCTUnwrap(
            HatcherySandRegion(
                // A right triangle, not a rectangle: rectification crops to
                // the sand's bounding box, so a region that filled its own box
                // would fill the cropped image and prove nothing.
                points: try [
                    NormalizedPoint(x: 0, y: 0),
                    NormalizedPoint(x: 0.55, y: 0),
                    NormalizedPoint(x: 0, y: 1)
                ].map { rectifiedPoint in
                    let sourcePoint = try XCTUnwrap(
                        mapper.sourcePoint(forRectified: rectifiedPoint)
                    )
                    return NormalizedPoint(
                        x: Double(sourcePoint.x),
                        y: Double(sourcePoint.y)
                    )
                }
            )
        )

        let result = try XCTUnwrap(
            HatcheryImageProcessor.rectification(
                from: makeSolidImage(size: CGSize(width: 400, height: 300)),
                boundary: boundary,
                sandRegion: sourceRegion
            )
        )

        XCTAssertTrue(result.sandRegion.contains(NormalizedPoint(x: 0.25, y: 0.5)))
        XCTAssertFalse(result.sandRegion.contains(NormalizedPoint(x: 0.75, y: 0.5)))

        let inside = CGPoint(
            x: result.image.size.width * 0.25,
            y: result.image.size.height * 0.5
        )
        let outside = CGPoint(
            x: result.image.size.width * 0.75,
            y: result.image.size.height * 0.5
        )
        XCTAssertGreaterThan(alpha(at: inside, in: result.image), 0)
        XCTAssertEqual(alpha(at: outside, in: result.image), 0)
    }

    private func makeSolidImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.setFillColor(UIColor.systemTeal.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func alpha(at point: CGPoint, in image: UIImage) -> UInt8 {
        guard let cgImage = image.cgImage else {
            XCTFail("Expected a CGImage-backed masked image")
            return 0
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Could not create a bitmap context")
            return 0
        }

        context.translateBy(x: -point.x, y: -point.y)
        context.draw(cgImage, in: CGRect(origin: .zero, size: image.size))

        guard let pixel = context.data?.assumingMemoryBound(to: UInt8.self) else {
            XCTFail("Could not access rendered pixel data")
            return 0
        }
        return pixel[3]
    }
}
