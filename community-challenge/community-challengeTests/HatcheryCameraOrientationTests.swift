import ImageIO
import UIKit
import XCTest
@testable import community_challenge

final class HatcheryCameraOrientationTests: XCTestCase {
    func testPortraitMapsVisionAndCameraRotation() {
        XCTAssertEqual(
            HatcheryCameraOrientation.backCamera(for: .portrait),
            HatcheryCameraOrientation(
                visionImageOrientation: .right,
                videoRotationAngle: 90
            )
        )
    }

    func testPortraitUpsideDownMapsVisionAndCameraRotation() {
        XCTAssertEqual(
            HatcheryCameraOrientation.backCamera(for: .portraitUpsideDown),
            HatcheryCameraOrientation(
                visionImageOrientation: .left,
                videoRotationAngle: 270
            )
        )
    }

    func testLandscapeLeftMapsVisionAndCameraRotation() {
        XCTAssertEqual(
            HatcheryCameraOrientation.backCamera(for: .landscapeLeft),
            HatcheryCameraOrientation(
                visionImageOrientation: .up,
                videoRotationAngle: 0
            )
        )
    }

    func testLandscapeRightMapsVisionAndCameraRotation() {
        XCTAssertEqual(
            HatcheryCameraOrientation.backCamera(for: .landscapeRight),
            HatcheryCameraOrientation(
                visionImageOrientation: .down,
                videoRotationAngle: 180
            )
        )
    }

    func testUnknownOrientationFallsBackToPortraitMapping() {
        XCTAssertEqual(
            HatcheryCameraOrientation.backCamera(for: .unknown),
            HatcheryCameraOrientation.backCamera(for: .portrait)
        )
    }
}
