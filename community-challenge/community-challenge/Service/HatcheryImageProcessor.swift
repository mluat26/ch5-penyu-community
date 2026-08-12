import CoreImage
import UIKit

nonisolated enum HatcheryImageProcessor {
    private static let context = CIContext(options: [.cacheIntermediates: false])

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

    /// Straightens the confirmed quadrilateral into the rectangular image used
    /// by Dimension, Preview, and Home. The original image and normalized
    /// boundary remain available in `HatcherySessionState` for section zooming.
    static func rectifiedImage(
        from image: UIImage,
        boundary: HatcheryBoundary
    ) -> UIImage {
        guard boundary.isValid, let input = CIImage(image: image) else { return image }
        let extent = input.extent

        func imagePoint(_ point: NormalizedPoint) -> CIVector {
            CIVector(
                x: extent.minX + CGFloat(point.x) * extent.width,
                y: extent.minY + (1 - CGFloat(point.y)) * extent.height
            )
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return image }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(imagePoint(boundary.topLeft), forKey: "inputTopLeft")
        filter.setValue(imagePoint(boundary.topRight), forKey: "inputTopRight")
        filter.setValue(imagePoint(boundary.bottomRight), forKey: "inputBottomRight")
        filter.setValue(imagePoint(boundary.bottomLeft), forKey: "inputBottomLeft")

        guard
            let output = filter.outputImage,
            !output.extent.isEmpty,
            let cgImage = context.createCGImage(output, from: output.extent.integral)
        else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}
