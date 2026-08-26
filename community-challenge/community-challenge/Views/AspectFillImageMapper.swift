import CoreGraphics

/// Converts points between a scaled image and its SwiftUI container.
///
/// `.fill` covers the container and crops the overflow; `.fit` shows the whole
/// image and leaves space around it. The mode must match how the image itself
/// is drawn -- a `scaledToFit` photo under a `.fill` mapper puts every overlay
/// point in the wrong place.
nonisolated struct AspectFillImageMapper {
    enum ContentMode {
        case fill
        case fit
        /// Each axis scaled independently, so the image covers the container
        /// exactly with nothing cropped and nothing left over.
        case stretch
    }

    let imageSize: CGSize
    let containerSize: CGSize
    /// Defaults to `.fill` so existing callers keep their behaviour.
    var contentMode: ContentMode = .fill

    private var horizontalScale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let horizontal = containerSize.width / imageSize.width
        let vertical = containerSize.height / imageSize.height
        return switch contentMode {
        case .fill: max(horizontal, vertical)
        case .fit: min(horizontal, vertical)
        case .stretch: horizontal
        }
    }

    private var verticalScale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let horizontal = containerSize.width / imageSize.width
        let vertical = containerSize.height / imageSize.height
        return switch contentMode {
        case .fill: max(horizontal, vertical)
        case .fit: min(horizontal, vertical)
        case .stretch: vertical
        }
    }

    private var origin: CGPoint {
        let renderedSize = CGSize(
            width: imageSize.width * horizontalScale,
            height: imageSize.height * verticalScale
        )
        return CGPoint(
            x: (containerSize.width - renderedSize.width) / 2,
            y: (containerSize.height - renderedSize.height) / 2
        )
    }

    func viewPoint(for point: NormalizedPoint) -> CGPoint {
        CGPoint(
            x: origin.x + CGFloat(point.x) * imageSize.width * horizontalScale,
            y: origin.y + CGFloat(point.y) * imageSize.height * verticalScale
        )
    }

    func normalizedPoint(for viewPoint: CGPoint) -> NormalizedPoint {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NormalizedPoint(x: 0.5, y: 0.5)
        }
        return NormalizedPoint(
            x: Double((viewPoint.x - origin.x) / (imageSize.width * horizontalScale)),
            y: Double((viewPoint.y - origin.y) / (imageSize.height * verticalScale))
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
