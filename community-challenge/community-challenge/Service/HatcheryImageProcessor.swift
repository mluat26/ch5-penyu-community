import CoreImage
import OSLog
import UIKit

/// A stable Core Graphics snapshot of a `UIImage`. Only this immutable payload
/// crosses between the main actor and detached image-rendering work.
nonisolated struct HatcheryImagePayload: Sendable {
    let cgImage: CGImage
    let scale: CGFloat
    let orientationRawValue: Int
}

nonisolated struct HatcheryRestoredImagePayloads: Sendable {
    let photo: HatcheryImagePayload
    let rectifiedPhoto: HatcheryImagePayload
    let rectifiedSandRegion: HatcherySandRegion
}

nonisolated struct HatcheryPreparedCapture: Sendable {
    let photo: HatcheryImagePayload
    let rectifiedPhoto: HatcheryImagePayload
    let rectifiedSandRegion: HatcherySandRegion
    let sourcePhoto: HatcherySourcePhoto
}

nonisolated enum HatcheryImageProcessor {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "community-challenge",
        category: "HatcheryImageProcessor"
    )
    /// The UI only renders this photo at hatchery-map scale. Keeping the stored
    /// source near the 1,960 px reference artwork avoids spending time encoding
    /// and uploading camera-original 12–48 MP files with no visible benefit.
    private static let sourcePhotoMaximumDimension: CGFloat = 2_048
    private static let sourcePhotoCompressionQuality: CGFloat = 0.82

    /// Flattens EXIF orientation and limits very large camera photos before
    /// geometry and perspective correction are applied.
    static func preparedImage(_ image: UIImage, maxDimension: CGFloat = 3072) -> UIImage {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return image }

        let resizeScale = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let outputSize = CGSize(
            width: sourceSize.width * resizeScale,
            height: sourceSize.height * resizeScale
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }

    /// Takes a small, immutable snapshot on the UI actor before a renderer task
    /// begins. `UIImage` itself never crosses the actor boundary.
    @MainActor
    static func payload(from image: UIImage) throws -> HatcheryImagePayload {
        try makePayload(from: image)
    }

    @MainActor
    static func displayImage(from payload: HatcheryImagePayload) -> UIImage {
        makeImage(from: payload)
    }

    /// Prepares the durable source photo away from the UI actor. JPEG encoding
    /// and raster resizing are the two most expensive synchronous pieces of a
    /// captured-layout save, so callers await this without freezing animation
    /// or touch handling.
    static func sourcePhoto(from payload: HatcheryImagePayload) async throws -> HatcherySourcePhoto {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let processedImage = Self.preparedImage(
                Self.makeImage(from: payload),
                maxDimension: Self.sourcePhotoMaximumDimension
            )
            try Task.checkCancellation()
            return try Self.makeSourcePhoto(from: processedImage)
        }

        return try await withTaskCancellationHandler(
            operation: { try await task.value },
            onCancel: { task.cancel() }
        )
    }

    /// Builds the display image, rectified image, and upload payload from one
    /// 2K raster pass. This keeps a full-resolution camera original off the UI
    /// path and avoids encoding the same photo again when the user taps Done.
    static func prepareCapturedLayout(
        from payload: HatcheryImagePayload,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion
    ) async throws -> HatcheryPreparedCapture {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let preparedImage = Self.preparedImage(
                Self.makeImage(from: payload),
                maxDimension: Self.sourcePhotoMaximumDimension
            )
            let preparedPayload = try Self.makePayload(from: preparedImage)
            let sourcePhoto = try Self.makeSourcePhoto(from: preparedImage)
            guard let rectification = Self.rectification(
                from: preparedImage,
                boundary: boundary,
                sandRegion: sandRegion
            ) else {
                throw HatcheryLayoutPersistenceError.invalidBoundary
            }
            try Task.checkCancellation()

            return HatcheryPreparedCapture(
                photo: preparedPayload,
                rectifiedPhoto: try Self.makePayload(from: rectification.image),
                rectifiedSandRegion: rectification.sandRegion,
                sourcePhoto: sourcePhoto
            )
        }

        return try await withTaskCancellationHandler(
            operation: { try await task.value },
            onCancel: { task.cancel() }
        )
    }

    /// Decodes and perspective-corrects a saved scan outside the UI actor.
    static func restoredImagePayloads(
        captureMode: HatcheryCaptureMode,
        sourcePhotoData: Data?,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion
    ) async throws -> HatcheryRestoredImagePayloads {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let photo: UIImage
            switch captureMode {
            case .captured:
                guard let sourcePhotoData else {
                    throw HatcheryLayoutPersistenceError.missingSourcePhoto
                }
                guard let decodedPhoto = UIImage(data: sourcePhotoData) else {
                    throw HatcheryLayoutPersistenceError.malformedPhoto
                }
                photo = decodedPhoto
            case .skipped:
                photo = Self.blankHatcheryImage()
            }

            let photoPayload = try Self.makePayload(from: photo)
            guard let rectification = Self.rectification(
                from: photo,
                boundary: boundary,
                sandRegion: sandRegion
            ) else {
                throw HatcheryLayoutPersistenceError.invalidBoundary
            }
            try Task.checkCancellation()

            return HatcheryRestoredImagePayloads(
                photo: photoPayload,
                rectifiedPhoto: try Self.makePayload(from: rectification.image),
                rectifiedSandRegion: rectification.sandRegion
            )
        }

        return try await withTaskCancellationHandler(
            operation: { try await task.value },
            onCancel: { task.cancel() }
        )
    }

    /// A deliberately blank canvas for a user who skips scanning. It is
    /// recreated locally on restore and is never uploaded as a fake photo.
    static func blankHatcheryImage() -> UIImage {
        let size = CGSize(width: 1960, height: 1102)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Straightens the confirmed quadrilateral and maps the editable sand
    /// polygon into the corrected image. The canvas remains rectangular so
    /// the logical grid retains stable coordinates; pixels outside the usable
    /// sand area become transparent.
    static func rectification(
        from image: UIImage,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion
    ) -> HatcheryRectification? {
        guard boundary.isValid, let input = CIImage(image: image) else {
            logger.error("Skipped hatchery rectification because the input boundary or image was invalid")
            return nil
        }
        let extent = input.extent

        func imagePoint(_ point: NormalizedPoint) -> CIVector {
            CIVector(
                x: extent.minX + CGFloat(point.x) * extent.width,
                y: extent.minY + (1 - CGFloat(point.y)) * extent.height
            )
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            logger.error("CIPerspectiveCorrection is unavailable")
            return nil
        }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(1, forKey: "inputCrop")
        filter.setValue(imagePoint(boundary.topLeft), forKey: "inputTopLeft")
        filter.setValue(imagePoint(boundary.topRight), forKey: "inputTopRight")
        filter.setValue(imagePoint(boundary.bottomRight), forKey: "inputBottomRight")
        filter.setValue(imagePoint(boundary.bottomLeft), forKey: "inputBottomLeft")

        guard
            let output = filter.outputImage,
            !output.extent.isEmpty,
            let cgImage = context.createCGImage(output, from: output.extent.integral)
        else {
            logger.error("Perspective correction did not produce an image")
            return nil
        }

        guard
            let mapper = HatcheryPerspectiveMapper(boundary: boundary),
            let rectifiedSandRegion = mapper.rectifiedRegion(for: sandRegion)
        else {
            logger.error("Could not map the sand region into corrected image coordinates")
            return nil
        }

        let correctedImage = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        let masked = maskedImage(correctedImage, to: rectifiedSandRegion)

        // Masking leaves the sand sitting inside the full boundary rectangle,
        // so the transparent margin is what the viewer ends up showing. Trim to
        // the sand itself: the photo then fills the viewer, and the grid drawn
        // over that viewer covers the sand rather than the margin.
        guard let cropped = croppedToSandRegion(masked, region: rectifiedSandRegion) else {
            return HatcheryRectification(image: masked, sandRegion: rectifiedSandRegion)
        }
        return HatcheryRectification(image: cropped.image, sandRegion: cropped.region)
    }

    /// Crops a masked scan to its sand region and re-expresses the region in
    /// the cropped image's coordinates, so overlays drawn from it still line up.
    ///
    /// Returns nil when the region has no area, leaving the caller with the
    /// untrimmed image rather than a zero-sized one.
    static func croppedToSandRegion(
        _ image: UIImage,
        region: HatcherySandRegion
    ) -> (image: UIImage, region: HatcherySandRegion)? {
        let xs = region.points.map(\.x)
        let ys = region.points.map(\.y)
        guard
            let minX = xs.min(), let maxX = xs.max(),
            let minY = ys.min(), let maxY = ys.max(),
            maxX > minX, maxY > minY,
            let cgImage = image.cgImage
        else { return nil }

        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: CGFloat(minX) * pixelWidth,
            y: CGFloat(minY) * pixelHeight,
            width: CGFloat(maxX - minX) * pixelWidth,
            height: CGFloat(maxY - minY) * pixelHeight
        ).integral

        guard
            cropRect.width >= 1, cropRect.height >= 1,
            let cropped = cgImage.cropping(to: cropRect)
        else { return nil }

        let spanX = maxX - minX
        let spanY = maxY - minY
        let movedPoints = region.points.map { point in
            NormalizedPoint(
                x: (point.x - minX) / spanX,
                y: (point.y - minY) / spanY
            )
        }
        guard let movedRegion = HatcherySandRegion(points: movedPoints) else { return nil }

        return (
            UIImage(cgImage: cropped, scale: 1, orientation: .up),
            movedRegion
        )
    }

    /// Applies the corrected-coordinate sand polygon as an alpha mask without
    /// changing image dimensions. It remains internal so focused tests can
    /// assert that post-capture screens receive a real segmented image.
    static func maskedImage(
        _ image: UIImage,
        to region: HatcherySandRegion
    ) -> UIImage {
        guard image.size.width > 0, image.size.height > 0 else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            guard let first = region.points.first else { return }

            let path = UIBezierPath()
            path.move(
                to: CGPoint(
                    x: CGFloat(first.x) * image.size.width,
                    y: CGFloat(first.y) * image.size.height
                )
            )
            for point in region.points.dropFirst() {
                path.addLine(
                    to: CGPoint(
                        x: CGFloat(point.x) * image.size.width,
                        y: CGFloat(point.y) * image.size.height
                    )
                )
            }
            path.close()
            path.addClip()
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func makePayload(from image: UIImage) throws -> HatcheryImagePayload {
        guard let cgImage = image.cgImage else {
            throw HatcheryLayoutPersistenceError.malformedPhoto
        }
        return HatcheryImagePayload(
            cgImage: cgImage,
            scale: image.scale,
            orientationRawValue: image.imageOrientation.rawValue
        )
    }

    private static func makeImage(from payload: HatcheryImagePayload) -> UIImage {
        let orientation = UIImage.Orientation(rawValue: payload.orientationRawValue) ?? .up
        return UIImage(
            cgImage: payload.cgImage,
            scale: max(payload.scale, 1),
            orientation: orientation
        )
    }

    private static func makeSourcePhoto(from image: UIImage) throws -> HatcherySourcePhoto {
        guard let jpegData = image.jpegData(
            compressionQuality: sourcePhotoCompressionQuality
        ) else {
            throw HatcheryLayoutPersistenceError.malformedPhoto
        }

        let pixelWidth = Int((image.size.width * image.scale).rounded())
        let pixelHeight = Int((image.size.height * image.scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw HatcheryLayoutPersistenceError.malformedPhoto
        }

        return HatcherySourcePhoto(
            data: jpegData,
            width: pixelWidth,
            height: pixelHeight
        )
    }
}

struct HatcheryRectification {
    let image: UIImage
    let sandRegion: HatcherySandRegion
}
