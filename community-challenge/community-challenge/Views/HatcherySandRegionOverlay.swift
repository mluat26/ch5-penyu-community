import SwiftUI

/// An editable, image-normalized polygon for marking the usable sand area.
///
/// The polygon stays in source-image coordinates, while this view maps it into
/// the aspect-filled image preview. It deliberately does not own the image or
/// surrounding scanner layout, so the same editor can be used after camera
/// capture and after a photo-library selection.
struct HatcherySandRegionOverlay: View {
    @Binding var region: HatcherySandRegion?

    let imageSize: CGSize
    var fallbackBoundary: HatcheryBoundary?
    var color: Color = .appGreenPrimary
    var isEditable = true

    private let handleRadius: CGFloat = 4.52
    private let handleHitSize: CGFloat = 44
    private let edgeHitWidth: CGFloat = 44
    private let edgeInsertionDistance: CGFloat = 24
    private let coordinateSpaceName = "hatcherySandRegionOverlay"

    init(
        region: Binding<HatcherySandRegion?>,
        imageSize: CGSize,
        fallbackBoundary: HatcheryBoundary? = nil,
        color: Color = .appGreenPrimary,
        isEditable: Bool = true
    ) {
        _region = region
        self.imageSize = imageSize
        self.fallbackBoundary = fallbackBoundary
        self.color = color
        self.isEditable = isEditable
    }

    var body: some View {
        GeometryReader { geometry in
            let mapper = AspectFillImageMapper(
                imageSize: imageSize,
                containerSize: geometry.size
            )
            let displayedRegion = region ?? initialRegion(using: mapper, in: geometry.size)

            if let displayedRegion {
                let viewPoints = displayedRegion.points.map(mapper.viewPoint)

                ZStack {
                    HatcherySandRegionPolygon(points: viewPoints)
                        .fill(color.opacity(0.30))

                    HatcherySandRegionPolygon(points: viewPoints)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: 2, lineJoin: .round)
                        )

                    if isEditable {
                        HatcherySandRegionEdgeHitArea(
                            points: viewPoints,
                            hitWidth: edgeHitWidth
                        )
                        .fill(.clear)
                        .contentShape(
                            HatcherySandRegionEdgeHitArea(
                                points: viewPoints,
                                hitWidth: edgeHitWidth
                            )
                        )
                        .gesture(
                            SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                                .onEnded { value in
                                    insertVertex(
                                        near: value.location,
                                        in: displayedRegion,
                                        viewPoints: viewPoints,
                                        mapper: mapper
                                    )
                                }
                        )
                    }

                    if isEditable {
                        ForEach(Array(viewPoints.enumerated()), id: \.offset) { index, point in
                            vertexHandle(
                                at: index,
                                in: displayedRegion,
                                mapper: mapper
                            )
                            .position(point)
                        }
                    }
                }
                .coordinateSpace(name: coordinateSpaceName)
                .onAppear {
                    persistInitialRegionIfNeeded(
                        using: mapper,
                        containerSize: geometry.size
                    )
                }
            }
        }
    }

    private func vertexHandle(
        at index: Int,
        in displayedRegion: HatcherySandRegion,
        mapper: AspectFillImageMapper
    ) -> some View {
        Circle()
            .fill(color)
            .frame(width: handleRadius * 2, height: handleRadius * 2)
            .frame(width: handleHitSize, height: handleHitSize)
            .contentShape(Rectangle())
            .accessibilityLabel("Sand-area corner \(index + 1)")
            .gesture(
                DragGesture(coordinateSpace: .named(coordinateSpaceName))
                    .onChanged { value in
                        moveVertex(
                            at: index,
                            to: value.location,
                            in: displayedRegion,
                            mapper: mapper
                        )
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        removeVertex(at: index, from: displayedRegion)
                    }
            )
            .allowsHitTesting(isEditable)
    }

    private func persistInitialRegionIfNeeded(
        using mapper: AspectFillImageMapper,
        containerSize: CGSize
    ) {
        guard isEditable, region == nil,
              let initialRegion = initialRegion(using: mapper, in: containerSize)
        else {
            return
        }
        region = initialRegion
    }

    private func initialRegion(
        using mapper: AspectFillImageMapper,
        in containerSize: CGSize
    ) -> HatcherySandRegion? {
        if let fallbackBoundary {
            return HatcherySandRegion.default(from: fallbackBoundary)
        }

        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0
        else {
            return nil
        }

        let guide = QuadPoints.defaultShape(in: containerSize)
        return HatcherySandRegion(points: mapper.boundary(for: guide).ordered)
    }

    private func moveVertex(
        at index: Int,
        to viewPoint: CGPoint,
        in displayedRegion: HatcherySandRegion,
        mapper: AspectFillImageMapper
    ) {
        guard isEditable, displayedRegion.points.indices.contains(index) else { return }

        var points = displayedRegion.points
        points[index] = mapper.normalizedPoint(for: viewPoint)
        guard let updatedRegion = HatcherySandRegion(points: points) else { return }
        region = updatedRegion
    }

    private func insertVertex(
        near viewPoint: CGPoint,
        in displayedRegion: HatcherySandRegion,
        viewPoints: [CGPoint],
        mapper: AspectFillImageMapper
    ) {
        guard isEditable,
              displayedRegion.points.count < HatcherySandRegion.maximumPointCount,
              let edge = closestEdge(to: viewPoint, in: viewPoints),
              edge.distance <= edgeInsertionDistance
        else {
            return
        }

        var points = displayedRegion.points
        points.insert(mapper.normalizedPoint(for: edge.closestPoint), at: edge.index + 1)
        guard let updatedRegion = HatcherySandRegion(points: points) else { return }
        region = updatedRegion
    }

    private func removeVertex(at index: Int, from displayedRegion: HatcherySandRegion) {
        guard isEditable,
              displayedRegion.points.count > HatcherySandRegion.minimumPointCount,
              displayedRegion.points.indices.contains(index)
        else {
            return
        }

        var points = displayedRegion.points
        points.remove(at: index)
        guard let updatedRegion = HatcherySandRegion(points: points) else { return }
        region = updatedRegion
    }

    private func closestEdge(to point: CGPoint, in points: [CGPoint]) -> ClosestEdge? {
        guard points.count >= HatcherySandRegion.minimumPointCount else { return nil }

        return points.indices
            .map { index in
                let closestPoint = closestPoint(
                    to: point,
                    on: points[index],
                    and: points[(index + 1) % points.count]
                )
                return ClosestEdge(
                    index: index,
                    closestPoint: closestPoint,
                    distance: hypot(closestPoint.x - point.x, closestPoint.y - point.y)
                )
            }
            .min(by: { $0.distance < $1.distance })
    }

    private func closestPoint(to point: CGPoint, on start: CGPoint, and end: CGPoint) -> CGPoint {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let squaredLength = deltaX * deltaX + deltaY * deltaY
        guard squaredLength > 0 else { return start }

        let projection = ((point.x - start.x) * deltaX + (point.y - start.y) * deltaY) / squaredLength
        let t = min(max(projection, 0), 1)
        return CGPoint(x: start.x + t * deltaX, y: start.y + t * deltaY)
    }
}

private extension HatcherySandRegionOverlay {
    struct ClosestEdge {
        let index: Int
        let closestPoint: CGPoint
        let distance: CGFloat
    }
}

private struct HatcherySandRegionPolygon: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first else { return Path() }

        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct HatcherySandRegionEdgeHitArea: Shape {
    let points: [CGPoint]
    let hitWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        HatcherySandRegionPolygon(points: points)
            .path(in: rect)
            .strokedPath(
                StrokeStyle(lineWidth: hitWidth, lineCap: .round, lineJoin: .round)
            )
    }
}
