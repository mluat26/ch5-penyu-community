import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import ImageIO
import OSLog
import Vision

/// A one-class object-detection result expressed in the app's image-relative,
/// top-left coordinate system.
nonisolated struct HatcheryObjectDetection: Equatable {
    let boundary: HatcheryBoundary
    let confidence: Float
}

/// Keeps model inference separate from the rectangle detector so a missing or
/// incompatible model can never interrupt the existing Vision fallback.
nonisolated protocol HatcheryObjectCandidateProviding: AnyObject {
    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> HatcheryObjectDetection?

    func detect(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> HatcheryObjectDetection?
}

/// Optional on-device detector for the single `hatchery` class.
///
/// The provider is deliberately unavailable when the compiled Core ML model is
/// absent or cannot produce `VNRecognizedObjectObservation` values. Callers
/// then keep using the rectangle detector without a degraded capture flow.
nonisolated final class HatcheryCoreMLObjectCandidateProvider: @unchecked Sendable,
    HatcheryObjectCandidateProviding {

    private static let expectedLabel = "hatchery"
    private static let minimumConfidence: Float = 0.60
    private static let minimumArea = 0.08
    private static let maximumArea = 0.92
    /// Create ML can emit a box that extends a few pixels beyond an image edge.
    /// Accepting that small numerical overshoot preserves an otherwise useful
    /// detection, while still rejecting boxes that are materially outside the
    /// captured image.
    private static let normalizedBoundsTolerance = 0.02

    private let model: VNCoreMLModel
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "community-challenge",
        category: "HatcheryCoreMLDetector"
    )

    private init(model: VNCoreMLModel) {
        self.model = model
    }

    /// Loads the model only when it is bundled with the app. The repository can
    /// therefore ship this scanner before its trained model is available.
    static func bundled(
        resourceName: String = "HatcheryDetector",
        bundle: Bundle = .main
    ) -> HatcheryCoreMLObjectCandidateProvider? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "mlmodelc") else {
            return nil
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        guard
            let coreMLModel = try? MLModel(contentsOf: url, configuration: configuration),
            let visionModel = try? VNCoreMLModel(for: coreMLModel)
        else {
            return nil
        }

        return HatcheryCoreMLObjectCandidateProvider(model: visionModel)
    }

    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> HatcheryObjectDetection? {
        detect(
            handler: VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )
        )
    }

    func detect(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> HatcheryObjectDetection? {
        detect(
            handler: VNImageRequestHandler(
                cgImage: cgImage,
                orientation: orientation,
                options: [:]
            )
        )
    }

    /// Vision object-detection boxes use a normalized lower-left origin;
    /// SwiftUI and the hatchery geometry use a normalized top-left origin.
    static func boundary(forVisionBoundingBox box: CGRect) -> HatcheryBoundary? {
        guard
            box.minX.isFinite,
            box.minY.isFinite,
            box.maxX.isFinite,
            box.maxY.isFinite,
            box.minX >= -Self.normalizedBoundsTolerance,
            box.minY >= -Self.normalizedBoundsTolerance,
            box.maxX <= 1 + Self.normalizedBoundsTolerance,
            box.maxY <= 1 + Self.normalizedBoundsTolerance,
            box.size.width > 0,
            box.size.height > 0
        else {
            return nil
        }

        let minX = max(0, min(1, box.minX))
        let minY = max(0, min(1, box.minY))
        let maxX = max(0, min(1, box.maxX))
        let maxY = max(0, min(1, box.maxY))
        let normalizedBox = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )

        guard normalizedBox.width > 0, normalizedBox.height > 0 else {
            return nil
        }

        let boundary = HatcheryBoundary(
            topLeft: NormalizedPoint(x: normalizedBox.minX, y: 1 - normalizedBox.maxY),
            topRight: NormalizedPoint(x: normalizedBox.maxX, y: 1 - normalizedBox.maxY),
            bottomRight: NormalizedPoint(x: normalizedBox.maxX, y: 1 - normalizedBox.minY),
            bottomLeft: NormalizedPoint(x: normalizedBox.minX, y: 1 - normalizedBox.minY)
        )
        let area = Double(normalizedBox.width * normalizedBox.height)
        guard
            boundary.isValid,
            (Self.minimumArea...Self.maximumArea).contains(area)
        else {
            return nil
        }
        return boundary
    }

    private func detect(handler: VNImageRequestHandler) -> HatcheryObjectDetection? {
        let request = VNCoreMLRequest(model: model)
        // Create ML's detector export produces image-relative boxes under
        // scale-fill. Keep this identical to the offline evaluator.
        request.imageCropAndScaleOption = .scaleFill

        do {
            try handler.perform([request])
        } catch {
            logger.error("Core ML hatchery analysis failed")
            return nil
        }

        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            logger.debug("Core ML hatchery model returned an incompatible observation type")
            return nil
        }

        let candidate = observations.compactMap { observation -> HatcheryObjectDetection? in
            guard
                let label = observation.labels
                    .filter({ $0.identifier.caseInsensitiveCompare(Self.expectedLabel) == .orderedSame })
                    .max(by: { $0.confidence < $1.confidence }),
                label.confidence >= Self.minimumConfidence,
                let boundary = Self.boundary(forVisionBoundingBox: observation.boundingBox)
            else {
                return nil
            }

            return HatcheryObjectDetection(
                boundary: boundary,
                confidence: label.confidence
            )
        }
        .max(by: { $0.confidence < $1.confidence })

        let result = candidate == nil ? "fallback" : "detected"
        logger.debug(
            "Core ML hatchery analysis: observations=\(observations.count, privacy: .public), result=\(result, privacy: .public)"
        )
        return candidate
    }
}
