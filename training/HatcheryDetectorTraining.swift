import CoreGraphics
import CreateML
import Darwin
import Foundation

/// Trains a one-class hatchery detector on macOS and exports a Core ML model.
///
/// Run `xcrun swift HatcheryDetectorTraining.swift --help` for the data contract.
enum HatcheryDetectorTraining {
    private enum TrainingError: LocalizedError {
        case invalidArguments(String)
        case invalidDataset(URL, String)
        case outputAlreadyExists(URL)

        var errorDescription: String? {
            switch self {
            case let .invalidArguments(message):
                return message
            case let .invalidDataset(url, message):
                return "Invalid dataset at \(url.path): \(message)"
            case let .outputAlreadyExists(url):
                return "Refusing to overwrite existing model: \(url.path)"
            }
        }
    }

    private enum Algorithm: String {
        case transferLearning = "transfer-learning"
        case darknetYOLO = "darknet-yolo"

        var modelAlgorithm: MLObjectDetector.ModelParameters.ModelAlgorithmType {
            switch self {
            case .transferLearning:
                return .transferLearning(.objectPrint())
            case .darknetYOLO:
                return .darknetYolo
            }
        }
    }

    private struct Options {
        let trainingURL: URL
        let validationURL: URL
        let testURL: URL
        let outputURL: URL
        let algorithm: Algorithm
        let maxIterations: Int?

        init(arguments: [String]) throws {
            guard arguments.count >= 4 else {
                throw TrainingError.invalidArguments(Self.usage)
            }

            let trainingURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
            let validationURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
            let testURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
            let outputURL = URL(fileURLWithPath: arguments[3]).standardizedFileURL

            var algorithm: Algorithm = .transferLearning
            var maxIterations: Int?
            var index = 4

            while index < arguments.count {
                switch arguments[index] {
                case "--algorithm":
                    index += 1
                    guard index < arguments.count,
                          let value = Algorithm(rawValue: arguments[index]) else {
                        throw TrainingError.invalidArguments(
                            "--algorithm must be transfer-learning or darknet-yolo.\n\n\(Self.usage)"
                        )
                    }
                    algorithm = value

                case "--max-iterations":
                    index += 1
                    guard index < arguments.count,
                          let value = Int(arguments[index]),
                          value > 0 else {
                        throw TrainingError.invalidArguments(
                            "--max-iterations must be a positive integer.\n\n\(Self.usage)"
                        )
                    }
                    maxIterations = value

                default:
                    throw TrainingError.invalidArguments(
                        "Unknown argument: \(arguments[index])\n\n\(Self.usage)"
                    )
                }
                index += 1
            }

            guard outputURL.pathExtension.lowercased() == "mlmodel" else {
                throw TrainingError.invalidArguments(
                    "Output must have a .mlmodel extension.\n\n\(Self.usage)"
                )
            }

            self.trainingURL = trainingURL
            self.validationURL = validationURL
            self.testURL = testURL
            self.outputURL = outputURL
            self.algorithm = algorithm
            self.maxIterations = maxIterations
        }

        static let usage = """
        Usage:
          HatcheryDetectorTraining <train-dir> <validation-dir> <test-dir> <output.mlmodel> \\
            [--algorithm transfer-learning|darknet-yolo] [--max-iterations N]

        Each dataset directory must contain its images and exactly one Apple JSON annotation file.
        See training/README.md for the annotation contract and split policy.
        """
    }

    static var usage: String {
        Options.usage
    }

    static func run(arguments: [String]) throws {
        let options = try Options(arguments: arguments)
        try validateDataset(at: options.trainingURL)
        try validateDataset(at: options.validationURL)
        try validateDataset(at: options.testURL)
        try validateOutput(options.outputURL)

        let trainingData = MLObjectDetector.DataSource
            .directoryWithImagesAndJsonAnnotation(at: options.trainingURL)
        let validationData = MLObjectDetector.DataSource
            .directoryWithImagesAndJsonAnnotation(at: options.validationURL)
        let testData = MLObjectDetector.DataSource
            .directoryWithImagesAndJsonAnnotation(at: options.testURL)

        let parameters = MLObjectDetector.ModelParameters(
            validation: .dataSource(validationData),
            batchSize: nil,
            maxIterations: options.maxIterations,
            gridSize: CGSize(width: 13, height: 13),
            algorithm: options.algorithm.modelAlgorithm
        )
        let annotationType: MLObjectDetector.AnnotationType = .boundingBox(
            units: .pixel,
            origin: .topLeft,
            anchor: .topLeft
        )

        print("Training with \(options.algorithm.rawValue)…")
        let detector = try MLObjectDetector(
            trainingData: trainingData,
            parameters: parameters,
            annotationType: annotationType
        )

        printMetrics(detector.trainingMetrics, named: "Training")
        printMetrics(detector.validationMetrics, named: "Validation")
        printMetrics(detector.evaluation(on: testData), named: "Test")

        try detector.write(to: options.outputURL)
        print("Exported \(options.outputURL.path)")
    }

    private static func validateDataset(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw TrainingError.invalidDataset(url, "directory does not exist")
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let annotationFiles = contents.filter {
            $0.pathExtension.caseInsensitiveCompare("json") == .orderedSame
        }
        guard annotationFiles.count == 1 else {
            throw TrainingError.invalidDataset(
                url,
                "expected exactly one JSON annotation file, found \(annotationFiles.count)"
            )
        }
    }

    private static func validateOutput(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else {
            throw TrainingError.invalidArguments(
                "Output directory does not exist: \(url.deletingLastPathComponent().path)"
            )
        }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw TrainingError.outputAlreadyExists(url)
        }
    }

    private static func printMetrics(
        _ metrics: MLObjectDetectorMetrics,
        named name: String
    ) {
        guard metrics.isValid else {
            print("\(name) metrics unavailable: \(String(describing: metrics.error))")
            return
        }

        print(
            "\(name) mAP: IoU 0.5 = \(metrics.meanAveragePrecision.IoU50), " +
            "varied IoU = \(metrics.meanAveragePrecision.variedIoU)"
        )
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] || arguments == ["-h"] {
    print(HatcheryDetectorTraining.usage)
} else {
    do {
        try HatcheryDetectorTraining.run(arguments: arguments)
    } catch {
        fputs("error: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
