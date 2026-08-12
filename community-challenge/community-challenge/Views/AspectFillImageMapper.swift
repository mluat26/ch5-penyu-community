import CoreGraphics

/// Converts points between an aspect-filled image and its SwiftUI container.
nonisolated struct AspectFillImageMapper {
    let imageSize: CGSize
    let containerSize: CGSize

    private var scale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return max(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
    }

    private var origin: CGPoint {
        let renderedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGPoint(
            x: (containerSize.width - renderedSize.width) / 2,
            y: (containerSize.height - renderedSize.height) / 2
        )
    }

    func viewPoint(for point: NormalizedPoint) -> CGPoint {
        CGPoint(
            x: origin.x + CGFloat(point.x) * imageSize.width * scale,
            y: origin.y + CGFloat(point.y) * imageSize.height * scale
        )
    }

    func normalizedPoint(for viewPoint: CGPoint) -> NormalizedPoint {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NormalizedPoint(x: 0.5, y: 0.5)
        }
        return NormalizedPoint(
            x: Double((viewPoint.x - origin.x) / (imageSize.width * scale)),
            y: Double((viewPoint.y - origin.y) / (imageSize.height * scale))
        )
    }

    func viewQuad(for boundary: HatcheryBoundary) -> QuadPoints {
        QuadPoints(
            topLeft: viewPoint(for: boundary.topLeft),
            topRight: viewPoint(for: boundary.topRight),
            bottomRight: viewPoint(for: boundary.bottomRight),
            bottomLeft: viewPoint(for: boundary.bottomLeft)
        )
    }

    func boundary(for quad: QuadPoints) -> HatcheryBoundary {
        HatcheryBoundary(
            topLeft: normalizedPoint(for: quad.topLeft),
            topRight: normalizedPoint(for: quad.topRight),
            bottomRight: normalizedPoint(for: quad.bottomRight),
            bottomLeft: normalizedPoint(for: quad.bottomLeft)
        )
    }
}
