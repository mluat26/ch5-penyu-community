import CoreGraphics
import CoreML
import Foundation
import ImageIO
import Vision

/// Evaluates a Create ML object-detector export through the same Vision shape
/// used by the app. This is intentionally a small prototype gate, not a
/// replacement for a full production evaluation harness.
enum HatcheryDetectorEvaluation {
    private static let expectedLabel = "hatchery"
    private static let defaultMinimumConfidence: Float = 0.60
    private static let matchIoU: CGFloat = 0.50

    private struct Coordinates: Decodable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private struct Annotation: Decodable {
        let label: String
        let coordinates: Coordinates
    }

    private struct Record: Decodable {
        let imagefilename: String
        let annotation: [Annotation]
    }

    private struct Totals {
        var truePositives = 0
        var falsePositives = 0
        var falseNegatives = 0
        var incompatibleResultImages = 0
    }

    static func run(
        modelURL: URL,
        dataSetURL: URL,
        minimumConfidence: Float = defaultMinimumConfidence
    ) throws {
        let annotationsURL = dataSetURL.appendingPathComponent("annotations.json")
        let annotationsData = try Data(contentsOf: annotationsURL)
        let records = try JSONDecoder().decode([Record].self, from: annotationsData)

        let compiledURL = try MLModel.compileModel(at: modelURL)
        defer { try? FileManager.default.removeItem(at: compiledURL) }

        let model = try MLModel(contentsOf: compiledURL)
        let visionModel = try VNCoreMLModel(for: model)
        var totals = Totals()

        for record in records {
            let imageURL = dataSetURL.appendingPathComponent(record.imagefilename)
            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw EvaluationError.unreadableImage(imageURL)
            }

            let expected = record.annotation.compactMap { annotation -> CGRect? in
                guard annotation.label.caseInsensitiveCompare(expectedLabel) == .orderedSame else {
                    return nil
                }
                return CGRect(
                    x: annotation.coordinates.x / CGFloat(image.width),
                    y: 1 - (annotation.coordinates.y + annotation.coordinates.height) / CGFloat(image.height),
                    width: annotation.coordinates.width / CGFloat(image.width),
                    height: annotation.coordinates.height / CGFloat(image.height)
                )
            }

            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFill
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
            try handler.perform([request])

            guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                totals.incompatibleResultImages += 1
                totals.falseNegatives += expected.count
                print("INCOMPATIBLE \(record.imagefilename): \(String(describing: request.results))")
                continue
            }

            let predictions = observations.compactMap { observation -> (box: CGRect, confidence: Float)? in
                guard let label = observation.labels.first(where: {
                    $0.identifier.caseInsensitiveCompare(expectedLabel) == .orderedSame
                        && $0.confidence >= minimumConfidence
                }) else {
                    return nil
                }
                guard appAccepts(observation.boundingBox) else {
                    return nil
                }
                return (observation.boundingBox, label.confidence)
            }

            var unmatchedExpected = expected
            var matchedPredictions = 0
            for prediction in predictions.sorted(by: { $0.box.width * $0.box.height > $1.box.width * $1.box.height }) {
                guard let index = unmatchedExpected.indices.max(by: {
                    intersectionOverUnion(prediction.box, unmatchedExpected[$0])
                        < intersectionOverUnion(prediction.box, unmatchedExpected[$1])
                }), intersectionOverUnion(prediction.box, unmatchedExpected[index]) >= matchIoU else {
                    continue
                }
                unmatchedExpected.remove(at: index)
                matchedPredictions += 1
            }

            totals.truePositives += matchedPredictions
            totals.falsePositives += predictions.count - matchedPredictions
            totals.falseNegatives += unmatchedExpected.count

            if matchedPredictions != expected.count || predictions.count != expected.count {
                let predictionSummary = predictions.map {
                    String(
                        format: "(x=%.2f,y=%.2f,w=%.2f,h=%.2f,c=%.2f)",
                        $0.box.minX,
                        $0.box.minY,
                        $0.box.width,
                        $0.box.height,
                        $0.confidence
                    )
                }.joined(separator: ", ")
                print(
                    "MISS \(record.imagefilename): expected=\(expected.count), " +
                        "predictions=\(predictions.count), matched=\(matchedPredictions), boxes=[\(predictionSummary)]"
                )
            }
        }

        let precision = ratio(numerator: totals.truePositives, denominator: totals.truePositives + totals.falsePositives)
        let recall = ratio(numerator: totals.truePositives, denominator: totals.truePositives + totals.falseNegatives)
        let f1 = precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall)

        print("Evaluation at IoU \(matchIoU), confidence \(minimumConfidence):")
        print("  true positives: \(totals.truePositives)")
        print("  false positives: \(totals.falsePositives)")
        print("  false negatives: \(totals.falseNegatives)")
        print("  precision: \(format(precision))")
        print("  recall: \(format(recall))")
        print("  F1: \(format(f1))")
        print("  incompatible result images: \(totals.incompatibleResultImages)")
    }

    private static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let union = lhs.width * lhs.height + rhs.width * rhs.height - intersection.width * intersection.height
        return union > 0 ? intersection.width * intersection.height / union : 0
    }

    /// Mirrors the app provider's normalized-box gate. A model prediction that
    /// cannot become a valid `HatcheryBoundary` is not a runtime detection.
    private static func appAccepts(_ box: CGRect) -> Bool {
        guard
            box.minX.isFinite,
            box.minY.isFinite,
            box.maxX.isFinite,
            box.maxY.isFinite,
            box.minX >= 0,
            box.minY >= 0,
            box.maxX <= 1,
            box.maxY <= 1,
            box.width > 0,
            box.height > 0
        else {
            return false
        }
        return (0.08...0.92).contains(box.width * box.height)
    }

    private static func ratio(numerator: Int, denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private enum EvaluationError: LocalizedError {
        case invalidArguments
        case unreadableImage(URL)

        var errorDescription: String? {
            switch self {
            case .invalidArguments:
                return "Usage: HatcheryDetectorEvaluation <model.mlmodel> <test-dataset-directory>"
            case let .unreadableImage(url):
                return "Could not read test image: \(url.path)"
            }
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 || arguments.count == 3 else {
    fputs(
        "Usage: HatcheryDetectorEvaluation <model.mlmodel> <test-dataset-directory> [minimum-confidence]\n",
        stderr
    )
    exit(EXIT_FAILURE)
}

let minimumConfidence: Float
if arguments.count == 3 {
    guard let parsedConfidence = Float(arguments[2]), (0...1).contains(parsedConfidence) else {
        fputs("error: minimum-confidence must be a number from 0 through 1\n", stderr)
        exit(EXIT_FAILURE)
    }
    minimumConfidence = parsedConfidence
} else {
    minimumConfidence = 0.60
}

do {
    try HatcheryDetectorEvaluation.run(
        modelURL: URL(fileURLWithPath: arguments[0]),
        dataSetURL: URL(fileURLWithPath: arguments[1]),
        minimumConfidence: minimumConfidence
    )
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
