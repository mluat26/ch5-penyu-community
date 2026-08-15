#!/usr/bin/env swift
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Creates deterministic, training-only image variants for the hatchery
/// detector. Validation and test data must remain untouched so the evaluator
/// continues to measure generalisation instead of memorisation.
///
/// Usage:
///   xcrun swift training/scripts/augment_hatchery_training.swift <train-dir> <new-train-dir>
///
/// The input directory must contain one `annotations.json` file using the
/// Apple Create ML pixel/top-left bounding-box format. The output is a new
/// directory containing the untouched source images plus two variants of each:
/// horizontal mirror and restrained low-light exposure.
enum HatcheryTrainingAugmentation {
    private static let annotationName = "annotations.json"
    private static let jpegQuality = 0.92

    private enum Augmentation: String, CaseIterable {
        case original
        case mirrored
        case lowLight
    }

    private struct Coordinates: Codable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    private struct Annotation: Codable {
        let label: String
        let coordinates: Coordinates
    }

    private struct Record: Codable {
        let imagefilename: String
        let annotation: [Annotation]
    }

    private enum AugmentationError: LocalizedError {
        case invalidArguments
        case outputExists(URL)
        case missingInput(URL)
        case unreadableImage(URL)
        case cannotCreateImage(URL)
        case cannotWriteImage(URL)
        case sourceDimensionsMissing(URL)

        var errorDescription: String? {
            switch self {
            case .invalidArguments:
                return "Usage: augment_hatchery_training.swift <train-dir> <new-train-dir>"
            case let .outputExists(url):
                return "Refusing to overwrite existing output directory: \(url.path)"
            case let .missingInput(url):
                return "Missing input annotation file: \(url.path)"
            case let .unreadableImage(url):
                return "Could not decode image: \(url.path)"
            case let .cannotCreateImage(url):
                return "Could not render augmented image: \(url.path)"
            case let .cannotWriteImage(url):
                return "Could not write JPEG image: \(url.path)"
            case let .sourceDimensionsMissing(url):
                return "Could not read source image dimensions: \(url.path)"
            }
        }
    }

    static func run(arguments: [String]) throws {
        guard arguments.count == 2 else {
            throw AugmentationError.invalidArguments
        }

        let inputDirectory = URL(fileURLWithPath: arguments[0], isDirectory: true)
        let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let inputAnnotations = inputDirectory.appendingPathComponent(annotationName)

        guard FileManager.default.fileExists(atPath: inputAnnotations.path) else {
            throw AugmentationError.missingInput(inputAnnotations)
        }
        guard !FileManager.default.fileExists(atPath: outputDirectory.path) else {
            throw AugmentationError.outputExists(outputDirectory)
        }

        let records = try JSONDecoder().decode(
            [Record].self,
            from: Data(contentsOf: inputAnnotations)
        )
        guard !records.isEmpty else {
            throw AugmentationError.missingInput(inputAnnotations)
        }

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let context = CIContext(options: [.cacheIntermediates: false])
        var outputRecords: [Record] = []
        outputRecords.reserveCapacity(records.count * Augmentation.allCases.count)

        for (index, record) in records.enumerated() {
            let inputImage = inputDirectory.appendingPathComponent(record.imagefilename)
            let sourceDimensions = try dimensions(of: inputImage)

            for augmentation in Augmentation.allCases {
                let outputName = outputFilename(
                    index: index + 1,
                    sourceFilename: record.imagefilename,
                    augmentation: augmentation
                )
                let outputImage = outputDirectory.appendingPathComponent(outputName)

                switch augmentation {
                case .original:
                    try FileManager.default.copyItem(at: inputImage, to: outputImage)
                case .mirrored, .lowLight:
                    let source = try decodedImage(at: inputImage)
                    let variant = apply(augmentation, to: source)
                    try writeJPEG(variant, to: outputImage, context: context)
                }

                let annotations: [Annotation]
                if augmentation == .mirrored {
                    annotations = record.annotation.map {
                        Annotation(
                            label: $0.label,
                            coordinates: Coordinates(
                                x: sourceDimensions.width - $0.coordinates.x - $0.coordinates.width,
                                y: $0.coordinates.y,
                                width: $0.coordinates.width,
                                height: $0.coordinates.height
                            )
                        )
                    }
                } else {
                    annotations = record.annotation
                }

                outputRecords.append(
                    Record(imagefilename: outputName, annotation: annotations)
                )
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let outputAnnotations = outputDirectory.appendingPathComponent(annotationName)
        try encoder.encode(outputRecords).write(to: outputAnnotations, options: .atomic)

        let positiveCount = outputRecords.reduce(into: 0) { count, record in
            if !record.annotation.isEmpty { count += 1 }
        }
        print("Created \(outputRecords.count) training images (\(positiveCount) positive) at \(outputDirectory.path)")
    }

    private static func outputFilename(
        index: Int,
        sourceFilename: String,
        augmentation: Augmentation
    ) -> String {
        let base = URL(fileURLWithPath: sourceFilename).deletingPathExtension().lastPathComponent
        return String(format: "%04d-%@-%@.jpg", index, augmentation.rawValue, base)
    }

    private static func dimensions(of url: URL) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw AugmentationError.sourceDimensionsMissing(url)
        }
        return (width, height)
    }

    private static func decodedImage(at url: URL) throws -> CIImage {
        guard let image = CIImage(contentsOf: url) else {
            throw AugmentationError.unreadableImage(url)
        }
        return image
    }

    private static func apply(_ augmentation: Augmentation, to image: CIImage) -> CIImage {
        switch augmentation {
        case .original:
            return image
        case .mirrored:
            let extent = image.extent
            return image.transformed(
                by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: extent.width, ty: 0)
            )
        case .lowLight:
            let exposure = image.applyingFilter(
                "CIExposureAdjust",
                parameters: [kCIInputEVKey: -0.85]
            )
            return exposure.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputContrastKey: 1.08,
                    kCIInputSaturationKey: 0.92,
                ]
            )
        }
    }

    private static func writeJPEG(_ image: CIImage, to url: URL, context: CIContext) throws {
        guard let rendered = context.createCGImage(image, from: image.extent) else {
            throw AugmentationError.cannotCreateImage(url)
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw AugmentationError.cannotWriteImage(url)
        }
        CGImageDestinationAddImage(
            destination,
            rendered,
            [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw AugmentationError.cannotWriteImage(url)
        }
    }
}

do {
    try HatcheryTrainingAugmentation.run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
